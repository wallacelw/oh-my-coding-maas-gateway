#!/usr/bin/env bash
set -euo pipefail

# ─── 02_litellm.sh — LiteLLM proxy + observability (pipeline step 02, core) ──
#
# Domain:        LiteLLM proxy + observability (Prometheus + Grafana)
# Order:         02 (after .env — tools need the proxy live)
# Optional:      no (core, always runs)
# Description:   Generate configs/litellm/config.yaml from .env (N deployments
#                per model per format, dual OpenAI + Anthropic), check required
#                ports are free, and deploy the Docker Compose stack
#                (LiteLLM + PostgreSQL + Prometheus + Grafana). Waits for
#                LiteLLM to become healthy.
# Inputs:        .env (HUAWEI_MAAS_API_KEY_0..N, HUAWEI_MAAS_API_KEY_COUNT,
#                HUAWEI_MAAS_API_BASE, HUAWEI_MAAS_ANTHROPIC_API_BASE)
# Outputs:       configs/litellm/config.yaml, running Docker Compose stack
# Standalone:    yes — ./scripts/02_litellm.sh
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_DIR/.env"
CONFIG_FILE="$PROJECT_DIR/configs/litellm/config.yaml"

source "$SCRIPT_DIR/helpers/prereqs.sh"
source "$SCRIPT_DIR/helpers/common.sh"
source "$SCRIPT_DIR/helpers/models.sh"
source "$SCRIPT_DIR/helpers/versions.sh"

# ── Parse args ──
ROUTING_STRATEGY="usage-based-routing-v2"
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --routing-strategy=*) ROUTING_STRATEGY="${arg#--routing-strategy=}" ;;
    --dry-run)            DRY_RUN=true ;;
    *)
      echo "Usage: $0 [--routing-strategy=STRATEGY] [--dry-run]" >&2
      echo "  Strategies: simple-shuffle, least-busy, latency-based-routing, usage-based-routing, usage-based-routing-v2, cost-based-routing" >&2
      exit 1
      ;;
  esac
done

# ── Validate routing strategy (fail fast — an invalid value would only
# surface later as a LiteLLM startup failure) ──
case "$ROUTING_STRATEGY" in
  simple-shuffle|least-busy|latency-based-routing|usage-based-routing|usage-based-routing-v2|cost-based-routing)
    ;;
  *)
    log_error "Invalid routing strategy: '$ROUTING_STRATEGY'"
    log_dim "  Valid values: simple-shuffle, least-busy, latency-based-routing, usage-based-routing, usage-based-routing-v2, cost-based-routing"
    exit 1
    ;;
esac

log_step "Step 02 — LiteLLM proxy + observability"

# ── Prerequisites (system-level, not LiteLLM-specific) ──
# Dry-run must be side-effect-free: never install packages or start daemons.
if [ "$DRY_RUN" = true ]; then
  log_dim "Dry-run: skipping prerequisite installs"
else
  prereq_ensure_apt "curl" curl curl "curl is needed for LiteLLM health checks and API calls"
  prereq_ensure_docker "Docker Engine runs the LiteLLM proxy, Prometheus, and Grafana containers"
fi

# ── Port conflict check ──
echo ""
our_containers=""
our_containers_loaded=false
for port in 4000 5432 9090 3000; do
  port_in_use=false
  if command -v ss &>/dev/null && ss -tlnp 2>/dev/null | grep -qE "[:.]${port}([^0-9]|$)"; then
    port_in_use=true
  elif command -v netstat &>/dev/null && netstat -tlnp 2>/dev/null | grep -qE "[:.]${port}([^0-9]|$)"; then
    port_in_use=true
  fi
  if [ "$port_in_use" = true ] && [ "$DRY_RUN" != true ]; then
    # Look up this compose project's own containers (once) — the live
    # stack holds these ports on every re-run and must never be removed.
    if [ "$our_containers_loaded" != true ]; then
      our_containers="$(docker compose -f "$PROJECT_DIR/docker-compose.yml" ps --format '{{.Name}}' 2>/dev/null || true)"
      our_containers_loaded=true
    fi
    # Any container publishing on this port: ours (live), stale litellm_*, or foreign
    port_containers=$(docker ps --filter "publish=${port}" --format '{{.Names}}' 2>/dev/null || true)
    if [ -n "$port_containers" ]; then
      # for-loop (not a pipe) so `exit 1` terminates the script, not a subshell
      for c in $port_containers; do
        if printf '%s\n' "$our_containers" | grep -qxF "$c"; then
          log_dim "Port $port held by this stack's container $c — compose will handle it"
        elif [[ "$c" == litellm_* ]]; then
          log_warn "Port $port held by stale LiteLLM container: $c — removing it"
          docker rm -f "$c" 2>/dev/null || true
        else
          log_error "Port $port held by foreign container '$c' — refusing to remove."
          log_dim "  Stop it manually: docker stop $c"
          exit 1
        fi
      done
    else
      log_warn "Port $port is already in use by a non-Docker process. Docker Compose may fail."
    fi
  fi
done

# ── Load .env ──
if [ ! -f "$ENV_FILE" ]; then
  log_error ".env not found. Run scripts/01_env.sh first."
  exit 1
fi
source_env "$PROJECT_DIR"

# ── Determine key count ──
KEY_COUNT="${HUAWEI_MAAS_API_KEY_COUNT:-1}"
if ! [[ "$KEY_COUNT" =~ ^[0-9]+$ ]]; then
  log_error "HUAWEI_MAAS_API_KEY_COUNT must be a positive integer. Got: $KEY_COUNT"
  exit 1
fi
if [ "$KEY_COUNT" -lt 1 ]; then
  log_error "HUAWEI_MAAS_API_KEY_COUNT must be >= 1. Got: $KEY_COUNT"
  exit 1
fi

# ── Validate all keys exist ──
if [ "$DRY_RUN" != true ]; then
  for i in $(seq 0 $((KEY_COUNT - 1))); do
    VAR="HUAWEI_MAAS_API_KEY_$i"
    VAL="${!VAR:-}"
    if [ -z "$VAL" ]; then
      log_error "$VAR is not set in .env. Each key must be present."
      exit 1
    fi
    if echo "$VAL" | grep -qi 'change-me\|replace\|xxx'; then
      log_error "$VAR still has a placeholder value."
      exit 1
    fi
  done
else
  log_dim "Dry-run: skipping MaaS key presence checks"
fi

# ── Model catalog ──
# (Sourced from helpers/models.sh)
MODEL_COUNT=${#MODELS[@]}
TOTAL_DEPLOYMENTS=$((KEY_COUNT * MODEL_COUNT * 2))

# ── Config generation target ──
# BACKUP is set only when the generated config differs from the live one
# (compare-before-write below) — an unchanged rerun creates no backup and
# rewrites nothing, killing identical config.yaml.bak.* churn.
BACKUP=""

# Look up off-peak pricing for a model from OFF_PEAK_PRICING array
get_off_peak_pricing() {
  local model="$1"
  for entry in "${OFF_PEAK_PRICING[@]}"; do
    local name="${entry%%|*}"
    if [ "$name" = "$model" ]; then
      echo "${entry#*|}"
      return 0
    fi
  done
  return 1
}

# Check if a model supports reasoning_effort
supports_reasoning() {
  local model="$1"
  for m in "${REASONING_MODELS[@]}"; do
    [ "$m" = "$model" ] && return 0
  done
  return 1
}

# Check if a model accepts image input (multimodal)
supports_vision() {
  local model="$1"
  for m in "${VISION_MODELS[@]}"; do
    [ "$m" = "$model" ] && return 0
  done
  return 1
}

# ── Validate catalog before generating config ──
if ! validate_catalog; then
  log_error "Model catalog validation failed — fix models.sh before proceeding"
  exit 1
fi

# ── Generate config ──

# emit_deployment <model_entry> <key_idx> <name_prefix> <provider_prefix> <api_base_env> <bridge>
# Emits one LiteLLM deployment block. bridge="true" adds use_chat_completions_api (OpenAI only).
emit_deployment() {
  local model_entry="$1" i="$2" name_prefix="$3" provider_prefix="$4" api_base_env="$5" bridge="$6"
  local model_name tpm rpm max_tokens max_input max_output input_cost output_cost cache_read_cost cache_creation_cost OFF_PEAK op_hours op_input op_output op_cache
  IFS=':' read -r model_name tpm rpm max_tokens max_input max_output input_cost output_cost cache_read_cost cache_creation_cost <<< "$model_entry"

  if [ "$KEY_COUNT" -gt 1 ]; then
    echo "  # ── deployment $i (key _${i}) ──"
  fi
  echo "  - model_name: ${name_prefix}${model_name}"
  echo "    litellm_params:"
  echo "      model: ${provider_prefix}${model_name}"
  echo "      api_base: os.environ/${api_base_env}"
  echo "      api_key: os.environ/HUAWEI_MAAS_API_KEY_$i"
  if [ "$bridge" = "true" ]; then
    echo "      use_chat_completions_api: true"
  fi
  echo "      tpm: $tpm"
  echo "      rpm: $rpm"
  echo "    model_info:"
  echo "      max_tokens: $max_tokens"
  echo "      max_input_tokens: $max_input"
  echo "      max_output_tokens: $max_output"
  echo "      input_cost_per_token: $input_cost"
  echo "      output_cost_per_token: $output_cost"
  if [ "${cache_read_cost:-0}" != "0" ]; then
    echo "      cache_read_input_token_cost: $cache_read_cost"
  fi
  if [ "${cache_creation_cost:-0}" != "0" ]; then
    echo "      cache_creation_input_token_cost: $cache_creation_cost"
  fi
  # Off-peak pricing (if configured for this model)
  OFF_PEAK=$(get_off_peak_pricing "$model_name") || true
  if [ -n "$OFF_PEAK" ]; then
    IFS='|' read -r op_hours op_input op_output op_cache <<< "$OFF_PEAK"
    echo "      off_peak_pricing:"
    echo "        hours_utc: \"$op_hours\""
    echo "        input_cost_per_token: $op_input"
    echo "        output_cost_per_token: $op_output"
    if [ "${op_cache:-0}" != "0" ]; then
      echo "        cache_read_input_token_cost: $op_cache"
    fi
  fi
  # Capability flags and metadata
  echo "      mode: chat"
  echo "      supports_function_calling: true"
  if [ "${cache_read_cost:-0}" != "0" ]; then
    echo "      supports_prompt_caching: true"
  else
    echo "      supports_prompt_caching: false"
  fi
  if supports_reasoning "$model_name"; then
    echo "      supports_reasoning: true"
  else
    echo "      supports_reasoning: false"
  fi
  if supports_vision "$model_name"; then
    echo "      supports_vision: true"
  else
    echo "      supports_vision: false"
  fi
  echo "      description: \"$model_name on Huawei Cloud MaaS\""
  echo "      organization: Huawei Cloud"
  echo ""
}

# Render to a temp file first: dry-run diffs it against the live config and
# discards it; a real run compares then either leaves the live config
# byte-identical (no backup, no rewrite) or backs it up and replaces it. The
# live config is bind-mounted into the running LiteLLM container.
CONFIG_OUT=$(mktemp)
trap 'rm -f "$CONFIG_OUT"' EXIT

{
  echo "model_list:"
  echo ""
  echo "  # ───────── Huawei MaaS OpenAI Models (${KEY_COUNT} deployment(s) per model, ${KEY_COUNT} * ${MODEL_COUNT} total) ───────────"
  echo "  # (Anthropic section below adds an equal batch — total: 2 * ${KEY_COUNT} * ${MODEL_COUNT})"
  echo ""

  for model_entry in "${MODELS[@]}"; do
    for i in $(seq 0 $((KEY_COUNT - 1))); do
      emit_deployment "$model_entry" "$i" "" "openai/" "HUAWEI_MAAS_API_BASE" "true"
    done
  done

  echo ""
  echo "  # ───────── Huawei MaaS Anthropic Models (for Claude Code CLI) ───────────"
  echo "  # Anthropic-compatible endpoint (/anthropic/v1/messages)"
  echo "  # Prefixed with claude- to avoid routing conflicts with OpenAI deployments"
  echo "  # (LiteLLM routes by model_name; same name for both formats causes"
  echo "  #  /v1/messages to sometimes hit the OpenAI deployment, losing content)"
  echo ""

  for model_entry in "${MODELS[@]}"; do
    for i in $(seq 0 $((KEY_COUNT - 1))); do
      emit_deployment "$model_entry" "$i" "claude-" "anthropic/" "HUAWEI_MAAS_ANTHROPIC_API_BASE" "false"
    done
  done

  echo ""
  echo "litellm_settings:"
  echo "  num_retries: 3 # proxy-level retry default; cross-deployment failover is router_settings.num_retries"
  echo "  request_timeout: 600 # full request: 10 min"
  echo "  stream_timeout: 60 # TTFT only: 60s"
  echo "  drop_params: True"
  echo "  callbacks: [\"prometheus\"]"
  echo "  prometheus_initialize_budget_metrics: true"
  echo "  require_auth_for_metrics_endpoint: false"
  echo "  ui_theme_config:"
  echo "    logo_url: \"https://upload.wikimedia.org/wikipedia/en/thumb/0/04/Huawei_Standard_logo.svg/3840px-Huawei_Standard_logo.svg.png\""
  echo "    favicon_url: \"https://upload.wikimedia.org/wikipedia/en/thumb/0/04/Huawei_Standard_logo.svg/3840px-Huawei_Standard_logo.svg.png\""
  echo ""
  echo "router_settings:"
  echo "  routing_strategy: $ROUTING_STRATEGY"
  echo "  num_retries: 6 # 7 attempts: survive re-picks of a hot key and still rotate"
  echo "  cooldown_time: 60 # benched key returns with in-flight drained and the upstream minute rolled"
  echo "  allowed_fails: 1 # non-429 failures before cooldown (60s window)"
  echo "  enable_pre_call_checks: true # pre-call context-window filtering"
  echo "  allowed_fails_policy:"
  echo "    RateLimitErrorAllowedFails: 3 # tolerate a few upstream 429s before benching; avoids empty-pool cascades"
  echo ""
   echo "general_settings:"
   echo "  database_connection_pool_limit: 10"
   echo "  database_connection_timeout: 60"
   echo "  allow_client_side_credentials: true"
   echo "  disable_env_credential_login: true # UI sign-in via DB-backed admin account only; master key cannot sign in to the UI"
   echo "  background_health_checks: true # periodically health-check all deployments"
   echo "  health_check_interval: 300 # seconds between background health checks"

} > "$CONFIG_OUT"

if [ "$DRY_RUN" = true ]; then
  log_info "Would write configs/litellm/config.yaml ($(wc -l < "$CONFIG_OUT") lines)"
  if [ -f "$CONFIG_FILE" ]; then
    if diff -q "$CONFIG_FILE" "$CONFIG_OUT" &>/dev/null; then
      log_dim "  No changes vs current configs/litellm/config.yaml"
    else
      CHANGED_LINES=$(diff "$CONFIG_FILE" "$CONFIG_OUT" | grep -cE '^[<>]' || true)
      log_dim "  $CHANGED_LINES line(s) differ from current configs/litellm/config.yaml"
    fi
  fi
elif [ -f "$CONFIG_FILE" ] && diff -q "$CONFIG_FILE" "$CONFIG_OUT" &>/dev/null; then
  log_dim "Config unchanged — skipping write"
  # Fix permissions even when content unchanged (a loose umask or external
  # edit may have left config.yaml non-600).
  if [ "$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null)" != "600" ]; then
    chmod 600 "$CONFIG_FILE"
    log_ok "Fixed permissions: $CONFIG_FILE (600)"
  fi
  # Record freshness without rewriting content: 01_env rewrites .env on
  # every run, so an untouched mtime would make 05's H5 warn ".env newer
  # than config.yaml" with a remediation (re-run 02) that no longer clears it.
  touch "$CONFIG_FILE"
else
  if [ -f "$CONFIG_FILE" ]; then
    BACKUP=$(backup_with_prune "$CONFIG_FILE")
    if [ -n "$BACKUP" ]; then
      log_info "Backed up existing config to $(basename "$BACKUP")"
    fi
  fi
  cat "$CONFIG_OUT" > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE"
  log_ok "Generated: $CONFIG_FILE"
fi
log_info "Deployments: ${TOTAL_DEPLOYMENTS} total (${KEY_COUNT} per model × ${MODEL_COUNT} models × 2 formats)"
log_info "Routing strategy: $ROUTING_STRATEGY"
if [ "$KEY_COUNT" -gt 1 ]; then
  echo ""
  log_info "Effective enforced capacity (per model):"
  for model_entry in "${MODELS[@]}"; do
    IFS=':' read -r model_name tpm rpm _ <<< "$model_entry"
    total_rpm=$((rpm * KEY_COUNT))
    total_tpm=$((tpm * KEY_COUNT))
    log_dim "  $model_name: $total_rpm RPM, $total_tpm TPM ($KEY_COUNT × $rpm RPM, $KEY_COUNT × $tpm TPM)"
  done
fi

# ── Pre-flight MaaS key validation ──
# Probe every key (0..KEY_COUNT-1) with the same request. Key 0 failure
# aborts the install (existing behavior); extra-key failures only warn —
# key 0 still serves traffic and per-deployment health shows in Grafana.
# Never log the key value itself — only the env var name and HTTP status.
if [ "$DRY_RUN" != true ]; then
  log_info "Validating MaaS API keys (0..$((KEY_COUNT - 1)))..."
  MAAS_BASE="${HUAWEI_MAAS_API_BASE:-https://api-ap-southeast-1.modelarts-maas.com/openai/v1}"
  for i in $(seq 0 $((KEY_COUNT - 1))); do
    KEY_VAR="HUAWEI_MAAS_API_KEY_$i"
    MAAS_KEY="${!KEY_VAR:-}"
    if [ "$i" -eq 0 ]; then
      MAAS_KEY="${MAAS_KEY:-${HUAWEI_MAAS_API_KEY:-}}"
    fi
    if [ -z "$MAAS_KEY" ]; then
      continue
    fi
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 "$MAAS_BASE/models" --config - 2>/dev/null <<CURLCFG
header = "Authorization: Bearer $MAAS_KEY"
CURLCFG
) || HTTP_CODE="000"
    if [ "$HTTP_CODE" = "200" ]; then
      log_ok "$KEY_VAR valid"
    elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
      if [ "$i" -eq 0 ]; then
        log_error "MaaS API key rejected (HTTP $HTTP_CODE). Check HUAWEI_MAAS_API_KEY in .env."
        exit 1
      fi
      log_warn "$KEY_VAR rejected (HTTP $HTTP_CODE) — continuing; its deployments will show unhealthy in Grafana."
    else
      log_warn "$KEY_VAR endpoint unreachable (HTTP $HTTP_CODE) — may be transient. Continuing (LiteLLM will retry)."
    fi
  done
else
  log_dim "Dry-run: skipping MaaS key validation"
fi

# ── Deploy Docker Compose ──
echo ""
if [ "$DRY_RUN" = true ]; then
  log_info "Would run: docker compose up -d"
  exit 0
fi

was_running=$(docker compose -f "$PROJECT_DIR/docker-compose.yml" ps --services --filter "status=running" 2>/dev/null | grep -c litellm || true)
old_litellm_cid="$(docker inspect litellm_proxy --format '{{.Id}}' 2>/dev/null || echo "")"
log_info "Starting Docker Compose (idempotent — no-op if already running)..."
log_info "Images: LiteLLM $(compose_image_tag litellm "$PROJECT_DIR/docker-compose.yml") · PostgreSQL $(compose_image_tag postgres "$PROJECT_DIR/docker-compose.yml") · Prometheus $(compose_image_tag prometheus "$PROJECT_DIR/docker-compose.yml") · Grafana $(compose_image_tag grafana "$PROJECT_DIR/docker-compose.yml")"
if ! run_with_spinner "Starting containers" docker compose -f "$PROJECT_DIR/docker-compose.yml" up -d; then
  log_error "Docker Compose failed to start."
  exit 1
fi
new_litellm_cid="$(docker inspect litellm_proxy --format '{{.Id}}' 2>/dev/null || echo "")"

# Restart LiteLLM if config changed (bind mount — compose won't auto-restart).
# Skip the restart when `up -d` just recreated the container (image or compose
# change): the recreated container already reads the new config, and an extra
# restart only adds downtime (and can interrupt startup migrations).
if [ "${was_running:-0}" -gt 0 ] && [ -n "${BACKUP:-}" ] && [ -f "$BACKUP" ] && ! diff -q "$BACKUP" "$CONFIG_FILE" &>/dev/null; then
  if [ -n "$old_litellm_cid" ] && [ "$old_litellm_cid" != "$new_litellm_cid" ]; then
    log_info "Config changed — LiteLLM was recreated by compose; new config already loaded"
  else
    log_info "Config changed — restarting LiteLLM to load new config..."
    run_with_spinner "Restarting LiteLLM" docker compose -f "$PROJECT_DIR/docker-compose.yml" restart litellm || log_warn "LiteLLM restart failed — health check will verify"
  fi
fi

# Wait for LiteLLM to become healthy. The 180s budget covers big-version
# upgrades (prisma migrations on an existing volume can outpace a short wait
# on slow disks). Crash-looping and DB-auth failures are detected from the
# container state/logs and fail fast with actionable output instead of
# burning the whole budget.
LITELLM_URL="http://127.0.0.1:4000"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
print_litellm_logs() {
  log_dim "  Last LiteLLM log lines:"
  docker logs --tail 12 litellm_proxy 2>&1 | while IFS= read -r line; do log_dim "    $line"; done || true
}
if curl -sf -m 15 "$LITELLM_URL/health/liveliness" &>/dev/null; then
  log_ok "LiteLLM already healthy."
else
  log_info "Waiting for LiteLLM to become healthy (up to 180s)..."
  waited=0
  health_rc=1
  while [ $waited -lt 180 ]; do
    if curl -sf -m 15 "$LITELLM_URL/health/liveliness" &>/dev/null; then
      log_ok "LiteLLM healthy after ~${waited}s."
      log_dim "  (docker ps health badge may lag up to ~70s — start_period 40s + interval 30s; the HTTP check above is authoritative)"
      health_rc=0
      break
    fi
    # DB auth failure: the classic update-path desync (DB_PASSWORD no longer
    # matches the volume's first-init password) — waiting longer cannot help.
    # NOTE: no grep -q here — -q exits on first match, docker logs takes
    # SIGPIPE (141), and pipefail turns a MATCHED pattern into rc!=0.
    if docker logs --since 2m litellm_proxy 2>&1 | grep 'password authentication failed' &>/dev/null; then
      health_rc=3
      break
    fi
    # Crash-loop: a container that keeps restarting will never become healthy.
    _st="$(docker inspect litellm_proxy --format '{{.State.Status}}' 2>/dev/null || echo "")"
    _rc="$(docker inspect litellm_proxy --format '{{.RestartCount}}' 2>/dev/null || echo 0)"
    if [ "$_st" = "restarting" ] || [ "${_rc:-0}" -ge 2 ]; then
      health_rc=2
      break
    fi
    printf "  ."
    sleep 5
    waited=$((waited + 5))
  done
  echo ""
  case "$health_rc" in
    0)
      ;;
    3)
      log_error "LiteLLM cannot authenticate to PostgreSQL: 'password authentication failed'."
      log_dim "  DB_PASSWORD in .env does not match the postgres volume litellm_postgres_data"
      log_dim "  (the volume keeps the password it was FIRST initialized with)."
      log_dim "  Recovery (no data loss) — align the database with the current .env value:"
      log_dim "    docker exec litellm_pg_db psql -U llmproxy -d litellm -c \"ALTER USER llmproxy WITH PASSWORD '<DB_PASSWORD from .env>';\""
      log_dim "  Or restore DB_PASSWORD from the .env used when the volume was created,"
      log_dim "  or re-initialize the volume (loses virtual keys and usage history):"
      log_dim "    docker compose down && docker volume rm litellm_postgres_data"
      print_litellm_logs
      exit 1
      ;;
    2)
      log_error "LiteLLM container is crash-looping (restarting repeatedly)."
      print_litellm_logs
      log_dim "  Full logs: docker compose -f $COMPOSE_FILE logs litellm"
      exit 1
      ;;
    *)
      log_error "LiteLLM did not become healthy within 180s."
      log_dim "  A big-version upgrade can run long migrations — check whether it is still progressing:"
      log_dim "    docker compose -f $COMPOSE_FILE logs -f litellm"
      print_litellm_logs
      exit 1
      ;;
  esac
fi
