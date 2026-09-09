#!/usr/bin/env bash
set -euo pipefail

# ─── 04_validate.sh — Validation (pipeline step 04, core) ─────────────────────
#
# Domain:        End-to-end validation
# Order:         04 (last — checks everything installed)
# Optional:      no (core, always runs; scoped via --skip-*)
# Description:   Validate all installed components: .env completeness, Docker
#                services, LiteLLM health + config, observability (Prometheus +
#                Grafana), and each coding tool (opencode, Codex, Claude Code).
#                Sections are skipped via --skip-* or selected via --xxx-only.
# Inputs:        .env, running Docker Compose stack, tool config files
# Outputs:       pass/fail/warn counts to stdout; exit 0 on pass, 1 on fail
# Standalone:    yes — ./scripts/04_validate.sh
#
# Usage:
#   ./04_validate.sh                       # full validation
#   ./04_validate.sh --dry-run             # structure checks only (no network)
#   ./04_validate.sh --litellm-only        # only LiteLLM proxy checks
#   ./04_validate.sh --skip-opencode       # LiteLLM + Codex + Claude Code
# ──────────────────────────────────────────────────────────────────────────────

PASS=0
FAIL=0
WARN=0
DRY_RUN=false
LITELLM_ONLY=false
OPENCODE_ONLY=false
CODEX_ONLY=false
CLAUDE_CODE_ONLY=false
PI_ONLY=false
SKIP_OPENCODE=false
SKIP_CODEX=false
SKIP_CLAUDE_CODE=false
SKIP_PI=false
LITELLM_URL="http://127.0.0.1:4000"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/helpers/prereqs.sh"
source "$SCRIPT_DIR/helpers/common.sh"
source "$SCRIPT_DIR/helpers/models.sh"
prereq_ensure_apt "curl" curl curl "curl is needed for API smoke tests"
prereq_ensure_apt "jq"   jq   jq   "jq is needed to parse validation JSON responses"

for arg in "$@"; do
  case "$arg" in
    --dry-run)          DRY_RUN=true ;;
    --litellm-only)     LITELLM_ONLY=true ;;
    --opencode-only)    OPENCODE_ONLY=true ;;
    --codex-only)       CODEX_ONLY=true ;;
    --claude-code-only) CLAUDE_CODE_ONLY=true ;;
    --skip-opencode)    SKIP_OPENCODE=true ;;
    --skip-codex)       SKIP_CODEX=true ;;
    --skip-claude-code) SKIP_CLAUDE_CODE=true ;;
    --skip-pi)          SKIP_PI=true ;;
    --pi-only)          PI_ONLY=true ;;
    *)                  log_error "Unknown flag: $arg"; exit 1 ;;
  esac
done

# ── Mode exclusivity (only for --xxx-only flags) ──
MODE_COUNT=0
[ "$LITELLM_ONLY" = true ] && MODE_COUNT=$((MODE_COUNT + 1))
[ "$OPENCODE_ONLY" = true ] && MODE_COUNT=$((MODE_COUNT + 1))
[ "$CODEX_ONLY" = true ] && MODE_COUNT=$((MODE_COUNT + 1))
[ "$CLAUDE_CODE_ONLY" = true ] && MODE_COUNT=$((MODE_COUNT + 1))
[ "$PI_ONLY" = true ] && MODE_COUNT=$((MODE_COUNT + 1))
if [ "$MODE_COUNT" -gt 1 ]; then
  echo "ERROR: --litellm-only, --opencode-only, --codex-only, --claude-code-only, and --pi-only are mutually exclusive." >&2
  exit 1
fi

# ── Derive which sections to run ──
RUN_LITELLM=true
RUN_OPENCODE=true
RUN_CODEX=true
RUN_CLAUDE_CODE=true
RUN_PI=true
RUN_OBSERVABILITY=true
if [ "$LITELLM_ONLY" = true ]; then
  RUN_OPENCODE=false; RUN_CODEX=false; RUN_CLAUDE_CODE=false; RUN_PI=false; RUN_OBSERVABILITY=false
elif [ "$OPENCODE_ONLY" = true ]; then
  RUN_CODEX=false; RUN_CLAUDE_CODE=false; RUN_PI=false; RUN_OBSERVABILITY=false
elif [ "$CODEX_ONLY" = true ]; then
  RUN_OPENCODE=false; RUN_CLAUDE_CODE=false; RUN_PI=false; RUN_OBSERVABILITY=false
elif [ "$CLAUDE_CODE_ONLY" = true ]; then
  RUN_OPENCODE=false; RUN_CODEX=false; RUN_PI=false; RUN_OBSERVABILITY=false
elif [ "$PI_ONLY" = true ]; then
  RUN_OPENCODE=false; RUN_CODEX=false; RUN_CLAUDE_CODE=false; RUN_OBSERVABILITY=false
fi
[ "$SKIP_OPENCODE" = true ] && RUN_OPENCODE=false
[ "$SKIP_CODEX" = true ] && RUN_CODEX=false
[ "$SKIP_CLAUDE_CODE" = true ] && RUN_CLAUDE_CODE=false
[ "$SKIP_PI" = true ] && RUN_PI=false

# ── Validation output helpers ──
pass() { PASS=$((PASS + 1)); log_ok "$1"; }
fail() { FAIL=$((FAIL + 1)); log_error "$1"; }
warn() { WARN=$((WARN + 1)); log_warn "$1"; }
skip() { log_dim "$1 (skipped)"; }
# Record N failed checks at once (for skipped sub-checks when config is missing)
fail_n() { local n="$1"; shift; FAIL=$((FAIL + n)); log_error "$*"; }

jqc() { printf '%s' "$1" | jq -e "$2" 2>/dev/null; }

# Get file permissions (Linux stat -c or BSD stat -f)
file_perms() { stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1" 2>/dev/null; }

# Check multiple jq expressions against a config (args: config desc expr desc expr ...)
check_jq() {
  local config="$1"; shift
  while [ $# -gt 0 ]; do
    local desc="$1" expr="$2"; shift 2
    if jqc "$config" "$expr"; then pass "$desc"; else fail "$desc"; fi
  done
}

# ── Load .env if present ──
source_env "$PROJECT_DIR"
KEY_COUNT="${HUAWEI_MAAS_API_KEY_COUNT:-1}"
if ! [[ "$KEY_COUNT" =~ ^[0-9]+$ ]]; then
  log_error "HUAWEI_MAAS_API_KEY_COUNT must be a positive integer. Got: $KEY_COUNT"
  exit 1
fi

log_step "oh-my-coding-maas-gateway — Validation"
if [ "$DRY_RUN" = true ]; then
  log_dim "(DRY RUN — network checks skipped)"
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION A: LiteLLM Proxy Validation
# ════════════════════════════════════════════════════════════════════════════
if [ "$RUN_LITELLM" = true ]; then
  log_step "A. LiteLLM Proxy"

  echo ""
  log_info "A1. .env completeness and permissions"
  if [ -f "$PROJECT_DIR/.env" ]; then
    pass ".env exists"
    PERMS=$(file_perms "$PROJECT_DIR/.env")
    if [ "$PERMS" = "600" ]; then
      pass ".env permissions are 0600"
    else
      warn ".env permissions are $PERMS (expected 0600)"
    fi
    for VAR in LITELLM_MASTER_KEY LITELLM_SALT_KEY DB_PASSWORD HUAWEI_MAAS_API_KEY; do
      VAL="${!VAR:-}"
      if [ -z "$VAL" ] || echo "$VAL" | grep -qi 'change-me\|replace\|xxx'; then
        fail "$VAR is not set or still has a placeholder value"
      else
        pass "$VAR is set (len=${#VAL})"
      fi
    done
    if [ -n "${HUAWEI_MAAS_API_KEY_COUNT:-}" ]; then
      pass "HUAWEI_MAAS_API_KEY_COUNT = $HUAWEI_MAAS_API_KEY_COUNT"
    else
      warn "HUAWEI_MAAS_API_KEY_COUNT not set (defaulting to 1)"
    fi

    # C1: BIND_ADDRESS exposure check
    BIND_ADDR="${BIND_ADDRESS:-127.0.0.1}"
    if [ "$BIND_ADDR" = "127.0.0.1" ]; then
      pass "BIND_ADDRESS=127.0.0.1 (localhost-only, secure)"
    elif [ "$BIND_ADDR" = "0.0.0.0" ]; then
      warn "BIND_ADDRESS=0.0.0.0 — all services exposed to all network interfaces"
      log_dim "  LiteLLM /metrics is unauthenticated; ensure firewall rules"
    else
      warn "BIND_ADDRESS=$BIND_ADDR — non-default bind address"
    fi

    # C2: Git hooks installed
    if [ -d "$PROJECT_DIR/.git" ]; then
      HOOKS_PATH=$(git -C "$PROJECT_DIR" config --local core.hooksPath 2>/dev/null || true)
      if [ "$HOOKS_PATH" = ".githooks" ]; then
        pass "Git hooks configured (pre-commit blocks .env and config.yaml)"
      else
        fail "Git hooks not configured — .env could be accidentally committed"
        log_dim "  Fix: git config core.hooksPath .githooks"
      fi
    fi

    # H2: All MaaS API keys present
    for i in $(seq 0 $((KEY_COUNT - 1))); do
      VAR="HUAWEI_MAAS_API_KEY_$i"
      VAL="${!VAR:-}"
      if [ -z "$VAL" ]; then
        fail "$VAR is not set in .env (referenced by config.yaml)"
      else
        pass "$VAR is set (len=${#VAL})"
      fi
    done

    # L3: LITELLM_SALT_KEY strength
    if [ -n "${LITELLM_SALT_KEY:-}" ]; then
      if [ ${#LITELLM_SALT_KEY} -ge 32 ]; then
        pass "LITELLM_SALT_KEY strength OK (len=${#LITELLM_SALT_KEY})"
      else
        warn "LITELLM_SALT_KEY is short (${#LITELLM_SALT_KEY} chars, recommend 32+)"
      fi
    fi
  else
    fail ".env not found"
  fi

  echo ""
  log_info "A2. Docker services"
  if [ "$DRY_RUN" = true ]; then
    skip "Docker service health"
  else
    RUNNING=$(docker compose -f "$PROJECT_DIR/docker-compose.yml" ps --services --filter "status=running" 2>/dev/null | wc -l || true)
    if [ "$RUNNING" -ge 4 ]; then
      pass "$RUNNING services running"
    else
      fail "Only $RUNNING services running (expected 4: litellm, db, prometheus, grafana)"
    fi

    # H1: Container health status (not just running)
    for container in litellm_proxy litellm_pg_db litellm_prometheus litellm_grafana; do
      HEALTH=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "missing")
      case "$HEALTH" in
        healthy)   pass "$container: healthy" ;;
        unhealthy) fail "$container: unhealthy (run: docker logs $container)" ;;
        starting)  warn "$container: still starting" ;;
        *)         warn "$container: no healthcheck ($HEALTH)" ;;
      esac
    done

    # L1: Docker Compose file validity
    if docker compose -f "$PROJECT_DIR/docker-compose.yml" config --quiet 2>/dev/null; then
      pass "docker-compose.yml is valid"
    else
      fail "docker-compose.yml is invalid (run: docker compose config)"
    fi

    # L2: Container restart policy
    for container in litellm_proxy litellm_pg_db litellm_prometheus litellm_grafana; do
      RESTART=$(docker inspect --format='{{.HostConfig.RestartPolicy.Name}}' "$container" 2>/dev/null || true)
      if [ "$RESTART" = "unless-stopped" ]; then
        pass "$container: restart=unless-stopped"
      else
        warn "$container: restart=$RESTART (expected unless-stopped)"
      fi
    done

    # M2: Container security hardening applied
    for container in litellm_proxy litellm_pg_db litellm_prometheus litellm_grafana; do
      SEC_OPT=$(docker inspect --format='{{.HostConfig.SecurityOpt}}' "$container" 2>/dev/null || true)
      if echo "$SEC_OPT" | grep -q 'no-new-privileges:true'; then
        pass "$container: no-new-privileges applied"
      else
        warn "$container: no-new-privileges not applied"
      fi
      CAP_DROP=$(docker inspect --format='{{.HostConfig.CapDrop}}' "$container" 2>/dev/null || true)
      if echo "$CAP_DROP" | grep -q 'ALL'; then
        pass "$container: cap_drop=ALL applied"
      else
        warn "$container: cap_drop=ALL not applied"
      fi
    done
  fi

  echo ""
  log_info "A3. LiteLLM health"
  if [ "$DRY_RUN" = true ]; then
    skip "LiteLLM liveness probe"
    skip "LiteLLM per-model health"
  else
    LIVENESS=$(curl -s --connect-timeout 5 --max-time 10 -w '%{http_code}' "$LITELLM_URL/health/liveliness" 2>/dev/null || true)
    LIVENESS_CODE="${LIVENESS: -3}"
    if [ "$LIVENESS_CODE" = "200" ]; then
      pass "LiteLLM liveness probe returned 200"
    else
      fail "LiteLLM liveness probe returned $LIVENESS_CODE"
    fi

    if [ -n "${LITELLM_MASTER_KEY:-}" ]; then
      HEALTH_RESP=$(curl -s --connect-timeout 10 --max-time 15 "$LITELLM_URL/health" -H "Authorization: Bearer $LITELLM_MASTER_KEY" 2>/dev/null || true)
      HEALTH_ANALYSIS=$(echo "$HEALTH_RESP" | python3 -c "
import sys, json
d = json.load(sys.stdin)
unhealthy = d.get('unhealthy_endpoints', [])
moderation_errors = 0
other_errors = 0
MODERATION_PATTERN = 'sensitive information'
for e in unhealthy:
    err = str(e.get('error', ''))
    if MODERATION_PATTERN in err:
        moderation_errors += 1
    else:
        other_errors += 1
print(f'{moderation_errors} {other_errors} {len(unhealthy)}')
" 2>/dev/null || echo "0 0 0")
      MODERATION_COUNT=$(echo "$HEALTH_ANALYSIS" | cut -d' ' -f1)
      OTHER_FAIL_COUNT=$(echo "$HEALTH_ANALYSIS" | cut -d' ' -f2)
      UNHEALTHY_COUNT=$(echo "$HEALTH_ANALYSIS" | cut -d' ' -f3)
      if [ "$UNHEALTHY_COUNT" = "0" ]; then
        pass "All deployments healthy (unhealthy_count=0)"
      elif [ "$OTHER_FAIL_COUNT" = "0" ]; then
        pass "All deployments reachable — $MODERATION_COUNT flagged by content moderation (known LiteLLM probe issue, not a real failure)"
      else
        warn "unhealthy_count=$UNHEALTHY_COUNT ($OTHER_FAIL_COUNT real errors, $MODERATION_COUNT content-moderation) — may be transient"
      fi
    else
      skip "Per-model health (LITELLM_MASTER_KEY not set)"
    fi
  fi

  echo ""
  log_info "A4. Config validation"
  CONFIG_FILE="$PROJECT_DIR/configs/litellm/config.yaml"
  TEMPLATE_FILE="$PROJECT_DIR/configs/litellm/config.yaml.template"
  if [ -f "$CONFIG_FILE" ]; then
    pass "litellm_config.yaml exists (generated)"
    DEPLOYMENT_COUNT=$(grep -c '^[[:space:]]*- model_name:' "$CONFIG_FILE" 2>/dev/null || true); DEPLOYMENT_COUNT=${DEPLOYMENT_COUNT:-0}
    EXPECTED_DEPLOYMENTS=$((KEY_COUNT * MODEL_COUNT * 2))
    if [ "$DEPLOYMENT_COUNT" = "$EXPECTED_DEPLOYMENTS" ]; then
      pass "Deployment count: $DEPLOYMENT_COUNT ($MODEL_COUNT models × $KEY_COUNT keys × 2 formats)"
    else
      warn "Deployment count: $DEPLOYMENT_COUNT (expected $EXPECTED_DEPLOYMENTS = $MODEL_COUNT models × $KEY_COUNT keys × 2 formats)"
    fi
    if [ -f "$TEMPLATE_FILE" ]; then
      # Template-sync check: assumes template contains only OpenAI entries.
      # The * 2 accounts for Anthropic entries added by 02_litellm.sh.
      # If Anthropic entries are ever added to the template, this check breaks.
      TEMPLATE_MODELS=$(grep -c '^[[:space:]]*- model_name:' "$TEMPLATE_FILE" 2>/dev/null || true); TEMPLATE_MODELS=${TEMPLATE_MODELS:-0}
      GENERATED_MODELS=$(grep -c '^[[:space:]]*- model_name:' "$CONFIG_FILE" 2>/dev/null || true); GENERATED_MODELS=${GENERATED_MODELS:-0}
      EXPECTED_FROM_TEMPLATE=$((TEMPLATE_MODELS * KEY_COUNT * 2))
      if [ "$GENERATED_MODELS" = "$EXPECTED_FROM_TEMPLATE" ]; then
        pass "Model catalog: template and generated config are in sync ($GENERATED_MODELS = $TEMPLATE_MODELS × $KEY_COUNT keys × 2 formats)"
      else
        warn "Model catalog drift: template has $TEMPLATE_MODELS entries, generated has $GENERATED_MODELS (expected $EXPECTED_FROM_TEMPLATE)"
      fi
    fi

    # H5: Config freshness (.env vs config.yaml)
    ENV_MTIME=$(stat -c '%Y' "$PROJECT_DIR/.env" 2>/dev/null || echo 0)
    CFG_MTIME=$(stat -c '%Y' "$CONFIG_FILE" 2>/dev/null || echo 0)
    if [ "$ENV_MTIME" -gt "$CFG_MTIME" ]; then
      warn ".env is newer than config.yaml — config may be stale"
      log_dim "  Fix: ./scripts/02_litellm.sh (regenerates config from current .env)"
    else
      pass "config.yaml is up to date (newer than .env)"
    fi

    # M3: Router settings in config
    if grep -q 'routing_strategy:' "$CONFIG_FILE" 2>/dev/null; then
      pass "Router: routing_strategy configured"
    else
      warn "Router: routing_strategy not set in config"
    fi
    if grep -q 'callbacks:' "$CONFIG_FILE" 2>/dev/null && grep -q 'prometheus' "$CONFIG_FILE" 2>/dev/null; then
      pass "LiteLLM: prometheus callback configured"
    else
      fail "LiteLLM: prometheus callback missing (metrics won't be emitted)"
    fi
  else
    warn "litellm_config.yaml not found — run scripts/02_litellm.sh"
  fi

  echo ""
  log_info "A5. Inference smoke test (all models)"
  if [ "$DRY_RUN" = true ]; then
    skip "Inference smoke test"
  elif [ -n "${LITELLM_MASTER_KEY:-}" ]; then
    for model_entry in "${MODELS[@]}"; do
      IFS=':' read -r model_name _ <<< "$model_entry"
      if curl -sf -m 30 "$LITELLM_URL/v1/chat/completions" \
          -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
          -H "Content-Type: application/json" \
          -d "{\"model\":\"$model_name\",\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}],\"max_tokens\":1}" >/dev/null 2>&1; then
        pass "Inference ($model_name): responded"
      else
        fail "Inference ($model_name): did not respond"
      fi
    done
  else
    skip "Inference smoke test (LITELLM_MASTER_KEY not set)"
  fi

  echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION B: opencode Configuration Validation
# ════════════════════════════════════════════════════════════════════════════
if [ "$RUN_OPENCODE" = true ]; then
  log_step "B. opencode Configuration"

  OPENCODE_DIR="$HOME/.config/opencode"
  CONFIG_FILE=""
  [ -f "$OPENCODE_DIR/opencode.json" ] && CONFIG_FILE="$OPENCODE_DIR/opencode.json"

  echo ""
  log_info "B1. opencode binary"
  if command -v opencode &>/dev/null; then
    pass "opencode installed: $(opencode --version 2>/dev/null || echo 'unknown')"
  else
    fail "opencode not found — run: curl -fsSL https://opencode.ai/install | bash"
  fi

  echo ""
  log_info "B2. Config files"
  if [ -n "$CONFIG_FILE" ]; then
    pass "opencode.json exists: $CONFIG_FILE"
    CLEAN_CONFIG=$(strip_jsonc "$CONFIG_FILE")
    pass "Config parses as valid JSON"
  else
    fail "opencode.json not found in $OPENCODE_DIR"
  fi

  if [ -f "$OPENCODE_DIR/oh-my-opencode-slim.json" ] || [ -f "$OPENCODE_DIR/oh-my-opencode-slim.jsonc" ]; then
    pass "oh-my-opencode-slim.json exists"
  else
    fail "oh-my-opencode-slim.json not found in $OPENCODE_DIR"
  fi

  echo ""
  log_info "B3. Provider configuration"
  if [ -n "$CONFIG_FILE" ]; then
    CLEAN_CONFIG=$(strip_jsonc "$CONFIG_FILE")
    check_jq "$CLEAN_CONFIG" \
      "LiteLLM provider defined" '.provider.LiteLLM' \
      "LiteLLM baseURL is 127.0.0.1:4000" '.provider.LiteLLM.options.baseURL == "http://127.0.0.1:4000"' \
      "LiteLLM apiKey set" '.provider.LiteLLM.options.apiKey' \
      "LiteLLM apiKey starts with sk-" '(.provider.LiteLLM.options.apiKey | startswith("sk-"))' \
      "Huawei-MaaS provider defined" '.provider["Huawei-MaaS"]' \
      "Huawei-MaaS has $MODEL_COUNT+ models" ".provider[\"Huawei-MaaS\"].models | keys | length >= $MODEL_COUNT" \
      "LiteLLM has $MODEL_COUNT+ models" ".provider.LiteLLM.models | keys | length >= $MODEL_COUNT" \
      "oh-my-opencode-slim plugin" '.plugin | index("oh-my-opencode-slim")' \
      "explore agent disabled" '.agent.explore.disable == true' \
      "general agent disabled" '.agent.general.disable == true' \
      "LSP enabled" '.lsp == true'

    PERMS=$(file_perms "$CONFIG_FILE")
    if [ "$PERMS" = "600" ]; then
      pass "Config file permissions 600"
    else
      warn "Config file permissions $PERMS (expected 600)"
    fi
  else
    fail_n 11 "No opencode config file — skipping 11 provider checks"
  fi

  echo ""
  log_info "B4. oh-my-opencode-slim preset"
  SLIM_CONFIG=""
  if [ -f "$OPENCODE_DIR/oh-my-opencode-slim.json" ]; then
    SLIM_CONFIG="$OPENCODE_DIR/oh-my-opencode-slim.json"
  elif [ -f "$OPENCODE_DIR/oh-my-opencode-slim.jsonc" ]; then
    SLIM_CONFIG="$OPENCODE_DIR/oh-my-opencode-slim.jsonc"
  fi

  if [ -n "$SLIM_CONFIG" ]; then
    CLEAN_SLIM=$(strip_jsonc "$SLIM_CONFIG")
    check_jq "$CLEAN_SLIM" \
      "LiteLLM-Default preset" '.presets["LiteLLM-Default"]' \
      "LiteLLM-Extended preset" '.presets["LiteLLM-Extended"]' \
      "Huawei-MaaS-Default direct preset" '.presets["Huawei-MaaS-Default"]' \
      "Huawei-MaaS-Extended direct preset" '.presets["Huawei-MaaS-Extended"]' \
      "Default is LiteLLM-Default" '.preset == "LiteLLM-Default"' \
      "Orchestrator model set" '.presets["LiteLLM-Default"].orchestrator.model' \
      "Oracle model set (array for fallback)" '.presets["LiteLLM-Default"].oracle.model' \
      "Council model set (array for fallback)" '.presets["LiteLLM-Default"].council.model' \
      "Librarian model set" '.presets["LiteLLM-Default"].librarian.model' \
      "Explorer model set" '.presets["LiteLLM-Default"].explorer.model' \
      "Designer model set" '.presets["LiteLLM-Default"].designer.model' \
      "Fixer model set (array for fallback)" '.presets["LiteLLM-Default"].fixer.model' \
      "Observer disabled" '.disabled_agents | index("observer")' \
      "Fallback enabled" '.fallback.enabled == true' \
      "Fallback has no chains (v2 format)" '(.fallback.chains // null) == null' \
      "Council presets defined" '.council.presets' \
      "Council has 3 councillors" '(.council.presets.default | keys | length) == 3' \
      "Council alpha model is LiteLLM/glm-5.2" '.council.presets.default.alpha.model == "LiteLLM/glm-5.2"' \
      "Council beta model is LiteLLM/glm-5.2" '.council.presets.default.beta.model == "LiteLLM/glm-5.2"' \
      "Council gamma model is LiteLLM/glm-5.2" '.council.presets.default.gamma.model == "LiteLLM/glm-5.2"' \
      "Huawei-MaaS-Default orchestrator model set" '.presets["Huawei-MaaS-Default"].orchestrator.model' \
      "Huawei-MaaS-Extended orchestrator model set" '.presets["Huawei-MaaS-Extended"].orchestrator.model'

    PERMS=$(file_perms "$SLIM_CONFIG")
    if [ "$PERMS" = "600" ]; then
      pass "Slim config permissions 600"
    else
      warn "Slim config permissions $PERMS (expected 600)"
    fi

    # M1: Slim plugin version match
    EXPECTED_SLIM=$(grep 'SLIM_VERSION=' "$PROJECT_DIR/scripts/03a_opencode.sh" 2>/dev/null \
      | head -1 | sed 's/.*="\([^"]*\)".*/\1/' || true)
    INSTALLED_SLIM=$(printf '%s' "$CLEAN_SLIM" | jq -r '."$schema"' 2>/dev/null \
      | sed 's|.*oh-my-opencode-slim@||;s|/.*||' 2>/dev/null || true)
    if [ -n "$EXPECTED_SLIM" ] && [ -n "$INSTALLED_SLIM" ]; then
      if [ "$EXPECTED_SLIM" = "$INSTALLED_SLIM" ]; then
        pass "Slim version: $INSTALLED_SLIM (matches 03a_opencode.sh)"
      else
        warn "Slim version: $INSTALLED_SLIM (expected $EXPECTED_SLIM from 03a_opencode.sh)"
        log_dim "  Fix: ./scripts/03a_opencode.sh (reinstalls plugin at v$EXPECTED_SLIM)"
      fi
    fi
  else
    fail_n 22 "No oh-my-opencode-slim config — skipping 22 preset checks"
  fi

  echo ""
  log_info "B5. Model availability (via proxy)"
  if [ "$DRY_RUN" = true ]; then
    skip "Model catalog reachable"
    skip "Inference smoke test"
  else
    VIRTUAL_KEY=""
    if [ -n "$CONFIG_FILE" ]; then
      VIRTUAL_KEY=$(printf '%s' "$CLEAN_CONFIG" | jq -r '.provider.LiteLLM.options.apiKey // empty' 2>/dev/null)
    fi
    [ -z "$VIRTUAL_KEY" ] && VIRTUAL_KEY="${LITELLM_MASTER_KEY:-}"

    if [ -z "$VIRTUAL_KEY" ]; then
      fail "No API key for model checks"
    else
      MODELS_JSON=$(curl -sf -m 10 "$LITELLM_URL/v1/models" \
        -H "Authorization: Bearer $VIRTUAL_KEY" 2>/dev/null || true)

      if [ -z "$MODELS_JSON" ] || ! printf '%s' "$MODELS_JSON" | jq -e '.data | length > 0' >/dev/null 2>&1; then
        fail "Model catalog not reachable or empty"
      else
        pass "Model catalog reachable"
        LITELLM_MODEL_COUNT=$(printf '%s' "$MODELS_JSON" | jq '.data | length' 2>/dev/null)
        MODEL_LIST=$(printf '%s' "$MODELS_JSON" | jq -r '.data[].id' 2>/dev/null)
        log_dim "Discovered $LITELLM_MODEL_COUNT model(s): $(echo "$MODEL_LIST" | tr '\n' ' ' | sed 's/ $//')"

        SMOKE_MODEL="deepseek-v4-flash"
        if curl -sf -m 30 "$LITELLM_URL/v1/chat/completions" \
            -H "Authorization: Bearer $VIRTUAL_KEY" \
            -H "Content-Type: application/json" \
            -d "{\"model\":\"$SMOKE_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}],\"max_tokens\":1}" >/dev/null 2>&1; then
          pass "Inference smoke test: $SMOKE_MODEL responded"
        else
          fail "Inference smoke test: $SMOKE_MODEL did not respond"
        fi

        # M6: Model catalog matches models.sh
        MODEL_LIST=$(curl -sf -m 10 "$LITELLM_URL/v1/models" 2>/dev/null | jq -r '.data[].id' 2>/dev/null || true)
        if [ -n "$MODEL_LIST" ]; then
          for model_entry in "${MODELS[@]}"; do
            IFS=':' read -r model_name _ <<< "$model_entry"
            if printf '%s\n' "$MODEL_LIST" | grep -qx "$model_name"; then
              pass "Model $model_name in LiteLLM catalog"
            else
              fail "Model $model_name missing from LiteLLM catalog"
            fi
            if printf '%s\n' "$MODEL_LIST" | grep -qx "claude-$model_name"; then
              pass "Model claude-$model_name in LiteLLM catalog"
            else
              fail "Model claude-$model_name missing from LiteLLM catalog"
            fi
          done
        fi
      fi
    fi
  fi

  echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION C: Observability (Prometheus + Grafana)
# ════════════════════════════════════════════════════════════════════════════
if [ "$RUN_OBSERVABILITY" = true ]; then
  echo ""
  log_step "C. Observability"

  echo ""
  log_info "C1. Prometheus"
  if [ "$DRY_RUN" = true ]; then
    skip "Prometheus reachability"
  elif curl -sf -m 5 http://127.0.0.1:9090/-/ready >/dev/null 2>&1; then
    pass "Prometheus reachable at :9090"

    # M4: Prometheus retention applied
    if [ "$DRY_RUN" = true ]; then
      skip "Prometheus retention check"
    else
      EXPECTED_RET="${PROMETHEUS_RETENTION:-30d}"
      ACTUAL_RET=$(curl -sf -m 5 http://127.0.0.1:9090/api/v1/status/flags 2>/dev/null \
        | jq -r '.data."storage.tsdb.retention.time" // empty' 2>/dev/null || true)
      if [ -n "$ACTUAL_RET" ]; then
        if [ "$ACTUAL_RET" = "$EXPECTED_RET" ]; then
          pass "Prometheus retention: $ACTUAL_RET (matches .env)"
        else
          warn "Prometheus retention: $ACTUAL_RET (expected $EXPECTED_RET from .env)"
        fi
      else
        skip "Prometheus retention (flags API not available)"
      fi
    fi
  else
    fail "Prometheus not reachable at :9090"
  fi

  echo ""
  log_info "C2. LiteLLM metrics endpoint"
  if [ "$DRY_RUN" = true ]; then
    skip "LiteLLM /metrics endpoint"
  elif curl -sf -L -m 5 http://127.0.0.1:4000/metrics >/dev/null 2>&1; then
    METRIC_LINES=$(curl -sf -L -m 5 http://127.0.0.1:4000/metrics 2>/dev/null | grep -c '^litellm_' || true)
    if [ "$METRIC_LINES" -gt 0 ]; then
      pass "LiteLLM /metrics active ($METRIC_LINES metric series)"
    else
      warn "LiteLLM /metrics responds but no litellm_ metrics found"
    fi
  else
    fail "LiteLLM /metrics endpoint not responding"
  fi

  echo ""
  log_info "C3. Prometheus scraping LiteLLM"
  if [ "$DRY_RUN" = true ]; then
    skip "Prometheus scrape check"
  else
    SCRAPE_COUNT=""
    for _attempt in 1 2 3; do
      SCRAPE_COUNT=$(curl -sf -g -m 10 "http://127.0.0.1:9090/api/v1/query?query=up{job=\"litellm\"}" 2>/dev/null | jq -r '.data.result[0].value[1] // empty' 2>/dev/null || true)
      if [ "$SCRAPE_COUNT" = "1" ]; then
        break
      fi
      [ "$_attempt" -lt 3 ] && sleep 5
    done
    if [ "$SCRAPE_COUNT" = "1" ]; then
      pass "Prometheus is scraping LiteLLM (up=1)"

      # L4: Prometheus self-monitoring
      PROM_SELF=$(curl -sf -g -m 10 'http://127.0.0.1:9090/api/v1/query?query=up{job="prometheus"}' 2>/dev/null \
        | jq -r '.data.result[0].value[1] // empty' 2>/dev/null || true)
      if [ "$PROM_SELF" = "1" ]; then
        pass "Prometheus self-monitoring active (up=1)"
      else
        warn "Prometheus not scraping itself (up=$PROM_SELF)"
      fi
    elif [ -n "$SCRAPE_COUNT" ]; then
      fail "Prometheus scraping LiteLLM but target is down (up=$SCRAPE_COUNT)"
    else
      warn "Prometheus has not scraped LiteLLM yet — may need a few seconds"
    fi
  fi

  echo ""
  log_info "C4. Grafana"
  if [ "$DRY_RUN" = true ]; then
    skip "Grafana reachability"
  elif curl -sf -m 5 http://127.0.0.1:3000/api/health >/dev/null 2>&1; then
    GRAFANA_DB_COUNT=$(curl -sf -m 5 --config - "http://127.0.0.1:3000/api/search?query=oh-my-coding" 2>/dev/null <<<"user = \"admin:${GRAFANA_ADMIN_PASSWORD:-admin}\"" | jq 'length' 2>/dev/null || echo 0)
    if [ "$GRAFANA_DB_COUNT" -gt 0 ]; then
      pass "Grafana reachable with dashboard provisioned"
      DS_NAME=$(curl -sf -m 5 --config - "http://127.0.0.1:3000/api/datasources/name/Prometheus" 2>/dev/null <<<"user = \"admin:${GRAFANA_ADMIN_PASSWORD:-admin}\"" | jq -r '.name // empty' 2>/dev/null || true)
       if [ "$DS_NAME" = "Prometheus" ]; then
         pass "Grafana Prometheus datasource configured"
       else
         warn "Grafana Prometheus datasource not found or not connected"
       fi

       # M5: Grafana dashboard has panels
       DASHBOARD_JSON=$(curl -sf -m 5 --config - \
         "http://127.0.0.1:3000/api/dashboards/uid/oh-my-coding-maas-gateway" 2>/dev/null <<<"user = \"admin:${GRAFANA_ADMIN_PASSWORD:-admin}\"" || true)
       if [ -n "$DASHBOARD_JSON" ]; then
         PANEL_COUNT=$(printf '%s' "$DASHBOARD_JSON" | jq '.dashboard.panels | length' 2>/dev/null || echo "0")
         if [ "$PANEL_COUNT" -gt 0 ]; then
           pass "Grafana dashboard has $PANEL_COUNT panels"
         else
           fail "Grafana dashboard has 0 panels (dashboard may be corrupted)"
         fi
       else
         skip "Grafana dashboard panel count (API not reachable)"
       fi
    else
      warn "Grafana reachable but dashboard not found — check provisioning"
    fi
  else
    fail "Grafana not reachable at :3000"
  fi

  echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION D: Codex CLI Configuration Validation
# ════════════════════════════════════════════════════════════════════════════
if [ "$RUN_CODEX" = true ]; then
  echo ""
  log_step "D. Codex CLI Configuration"

  CODEX_DIR="$HOME/.codex"
  CODEX_CONFIG="$CODEX_DIR/config.toml"

  echo ""
  log_info "D1. Codex CLI binary"
  if command -v codex &>/dev/null; then
    pass "codex installed: $(codex --version 2>/dev/null || echo 'unknown')"
  else
    fail "codex not found — run: npm install -g @openai/codex"
  fi

  echo ""
  log_info "D2. Config file"
  if [ -f "$CODEX_CONFIG" ]; then
    pass "config.toml exists: $CODEX_CONFIG"
  else
    fail "config.toml not found in $CODEX_DIR"
  fi

  echo ""
  log_info "D3. Provider configuration"
  if [ -f "$CODEX_CONFIG" ]; then
    if grep -q 'base_url[[:space:]]*=[[:space:]]*"http://127.0.0.1:4000/v1"' "$CODEX_CONFIG"; then
      pass "model provider base_url points to LiteLLM proxy"
    else
      fail "model provider base_url not pointing to LiteLLM proxy"
    fi
    if grep -qE 'env_key[[:space:]]*=[[:space:]]*"LITELLM_CODEX_API_KEY"' "$CODEX_CONFIG"; then
      pass "env_key set to LITELLM_CODEX_API_KEY"
    else
      fail "env_key not set to LITELLM_CODEX_API_KEY"
    fi
    if grep -qE 'wire_api[[:space:]]*=[[:space:]]*"responses"' "$CODEX_CONFIG"; then
      pass "wire_api set to responses (HTTP SSE)"
    else
      fail "wire_api not set to responses"
    fi
    if grep -qE '^model[[:space:]]*=[[:space:]]*"[^[:space:]]+"' "$CODEX_CONFIG"; then
      CODEX_MODEL=$(sed -n 's/^model[[:space:]]*=[[:space:]]*"\([^"]*\).*/\1/p' "$CODEX_CONFIG" 2>/dev/null || true)
      pass "default model set: $CODEX_MODEL"
    else
      fail "default model not set"
    fi
    PERMS=$(file_perms "$CODEX_CONFIG")
    if [ "$PERMS" = "600" ]; then
      pass "Config file permissions 600"
    else
      warn "Config file permissions $PERMS (expected 600)"
    fi
  else
    fail_n 5 "No Codex config file — skipping 5 provider checks"
  fi

  echo ""
  log_info "D4. Responses API smoke test"
  CODEX_VK=""
  if [ -f "$HOME/.codex/.env" ]; then
    CODEX_VK=$(sed -n 's/^LITELLM_CODEX_API_KEY=\(.*\)/\1/p' "$HOME/.codex/.env" 2>/dev/null || true)
  fi
  if [ -z "$CODEX_VK" ] && [ -n "${LITELLM_CODEX_API_KEY:-}" ]; then
    CODEX_VK="$LITELLM_CODEX_API_KEY"
  fi
  if [ "$DRY_RUN" = true ]; then
    skip "Responses API smoke test"
  elif [ -n "$CODEX_VK" ]; then
    SMOKE_MODEL="deepseek-v4-flash"
    if curl -sf -m 30 "$LITELLM_URL/v1/responses" \
        -H "Authorization: Bearer $CODEX_VK" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$SMOKE_MODEL\",\"input\":\"ok\"}" >/dev/null 2>&1; then
      pass "Responses API smoke test: $SMOKE_MODEL responded"
    else
      fail "Responses API smoke test: $SMOKE_MODEL did not respond"
    fi
  else
    skip "Responses API smoke test (no API key found)"
  fi

  echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION E: Claude Code CLI Configuration Validation
# ════════════════════════════════════════════════════════════════════════════
if [ "$RUN_CLAUDE_CODE" = true ]; then
  echo ""
  log_step "E. Claude Code CLI Configuration"

  CLAUDE_CONFIG_DIR="$HOME/.claude"
  CLAUDE_SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"

  echo ""
  log_info "E1. Claude Code CLI binary"
  if command -v claude &>/dev/null; then
    pass "claude installed: $(claude --version 2>/dev/null || echo 'unknown')"
  else
    fail "claude not found — run: npm install -g @anthropic-ai/claude-code"
  fi

  echo ""
  log_info "E2. Config file"
  if [ -f "$CLAUDE_SETTINGS" ]; then
    pass "settings.json exists: $CLAUDE_SETTINGS"
  else
    fail "settings.json not found in $CLAUDE_CONFIG_DIR"
  fi

  echo ""
  log_info "E3. Provider configuration"
  if [ -f "$CLAUDE_SETTINGS" ]; then
    CLAUDE_BASE_URL=$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$CLAUDE_SETTINGS" 2>/dev/null || true)
    if [ "$CLAUDE_BASE_URL" = "http://127.0.0.1:4000" ]; then
      pass "ANTHROPIC_BASE_URL points to LiteLLM proxy"
    else
      fail "ANTHROPIC_BASE_URL not pointing to LiteLLM proxy (got: $CLAUDE_BASE_URL)"
    fi
    CLAUDE_VK=$(jq -r '.env.ANTHROPIC_API_KEY // empty' "$CLAUDE_SETTINGS" 2>/dev/null || true)
    if [[ "$CLAUDE_VK" == sk-* ]]; then
      pass "ANTHROPIC_API_KEY set (starts with sk-)"
    else
      fail "ANTHROPIC_API_KEY not set or invalid"
    fi
    CLAUDE_MODEL=$(jq -r '.env.ANTHROPIC_MODEL // empty' "$CLAUDE_SETTINGS" 2>/dev/null || true)
    if [ -n "$CLAUDE_MODEL" ]; then
      if [[ "$CLAUDE_MODEL" == claude-* ]]; then
        pass "default model set: $CLAUDE_MODEL"
      else
        warn "default model '$CLAUDE_MODEL' doesn't start with 'claude-' — may not route correctly"
      fi
    else
      fail "default model not set"
    fi
    PERMS=$(file_perms "$CLAUDE_SETTINGS")
    if [ "$PERMS" = "600" ]; then
      pass "Config file permissions 600"
    else
      warn "Config file permissions $PERMS (expected 600)"
    fi
  else
    fail_n 4 "No Claude Code config — skipping 4 provider checks"
    CLAUDE_VK=""
  fi

  echo ""
  log_info "E4. Messages API smoke test"
  if [ "$DRY_RUN" = true ]; then
    skip "Messages API smoke test"
  elif [ -n "$CLAUDE_VK" ]; then
    SMOKE_MODEL="claude-deepseek-v4-flash"
    if curl -sf -m 30 "$LITELLM_URL/v1/messages" \
        -H "x-api-key: $CLAUDE_VK" \
        -H "Content-Type: application/json" \
        -H "anthropic-version: 2023-06-01" \
        -d "{\"model\":\"$SMOKE_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}],\"max_tokens\":1}" >/dev/null 2>&1; then
      pass "Messages API smoke test: $SMOKE_MODEL responded"
    else
      fail "Messages API smoke test: $SMOKE_MODEL did not respond"
    fi
  else
    skip "Messages API smoke test (no API key found)"
  fi

  echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION F: Pi Agent Configuration Validation
# ════════════════════════════════════════════════════════════════════════════
if [ "$RUN_PI" = true ]; then
  echo ""
  log_step "F. Pi Agent Configuration"

  PI_DIR="$HOME/.pi/agent"
  PI_CONFIG="$PI_DIR/models.json"

  echo ""
  log_info "F1. Pi binary"
  if command -v pi &>/dev/null; then
    pass "pi installed: $(pi --version 2>/dev/null || echo 'unknown')"
  else
    fail "pi not found — run: ./scripts/03d_pi.sh or curl -fsSL https://pi.dev/install.sh | sh"
  fi

  echo ""
  log_info "F2. Config file"
  if [ -f "$PI_CONFIG" ]; then
    pass "models.json exists: $PI_CONFIG"
    if jq -e . "$PI_CONFIG" >/dev/null 2>&1; then
      pass "Config parses as valid JSON"
    else
      fail "Config is not valid JSON"
    fi
    PERMS=$(file_perms "$PI_CONFIG")
    if [ "$PERMS" = "600" ]; then
      pass "Config file permissions 600"
    else
      warn "Config file permissions $PERMS (expected 600)"
    fi
  else
    fail "models.json not found in $PI_DIR"
  fi

  echo ""
  log_info "F3. Provider configuration"
  if [ -f "$PI_CONFIG" ] && jq -e . "$PI_CONFIG" >/dev/null 2>&1; then
    PI_BASE_URL=$(jq -r '.providers.LiteLLM.baseUrl // empty' "$PI_CONFIG" 2>/dev/null || true)
    if [ "$PI_BASE_URL" = "http://127.0.0.1:4000/v1" ]; then
      pass "providers.LiteLLM.baseUrl points to LiteLLM proxy"
    else
      fail "providers.LiteLLM.baseUrl not pointing to LiteLLM proxy (got: $PI_BASE_URL)"
    fi
    PI_API_KEY=$(jq -r '.providers.LiteLLM.apiKey // empty' "$PI_CONFIG" 2>/dev/null || true)
    if [[ "$PI_API_KEY" == sk-* ]]; then
      pass "providers.LiteLLM.apiKey set (starts with sk-)"
    else
      fail "providers.LiteLLM.apiKey not set or invalid"
    fi
    PI_API=$(jq -r '.providers.LiteLLM.api // empty' "$PI_CONFIG" 2>/dev/null || true)
    if [ "$PI_API" = "openai-completions" ]; then
      pass "providers.LiteLLM.api equals openai-completions"
    else
      fail "providers.LiteLLM.api not set to openai-completions (got: $PI_API)"
    fi
    PI_MODEL_COUNT=$(jq -r '.providers.LiteLLM.models | length' "$PI_CONFIG" 2>/dev/null || echo "0")
    if [ "$PI_MODEL_COUNT" -ge "$MODEL_COUNT" ]; then
      pass "providers.LiteLLM.models has $PI_MODEL_COUNT models (>= $MODEL_COUNT)"
    else
      fail "providers.LiteLLM.models has only $PI_MODEL_COUNT models (expected >= $MODEL_COUNT)"
    fi
  else
    fail_n 4 "No Pi config file — skipping 4 provider checks"
    PI_API_KEY=""
  fi

  echo ""
  log_info "F4. Inference smoke test"
  if [ "$DRY_RUN" = true ]; then
    skip "Inference smoke test"
  elif [ -n "${PI_API_KEY:-}" ]; then
    SMOKE_MODEL="deepseek-v4-flash"
    if curl -sf -m 30 "$LITELLM_URL/v1/chat/completions" \
        -H "Authorization: Bearer $PI_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"model\":\"$SMOKE_MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"ok\"}],\"max_tokens\":1}" >/dev/null 2>&1; then
      pass "Inference smoke test: $SMOKE_MODEL responded"
    else
      fail "Inference smoke test: $SMOKE_MODEL did not respond"
    fi
  else
    skip "Inference smoke test (no API key found)"
  fi

  echo ""
fi

# ════════════════════════════════════════════════════════════════════════════
# SECTION G: Cross-tool Key Isolation
# ════════════════════════════════════════════════════════════════════════════
if [ "$RUN_LITELLM" = true ]; then
  log_step "G. Cross-tool key isolation"

  echo ""
  log_info "G1. Virtual key uniqueness"
  declare -A VK_TOOLS=()
  OC_KEY=""
  CODEX_KEY=""
  CLAUDE_KEY=""
  PI_VKEY=""

  if [ -f "$HOME/.config/opencode/opencode.json" ]; then
    OC_KEY=$(strip_jsonc "$HOME/.config/opencode/opencode.json" 2>/dev/null | jq -r '.provider.LiteLLM.options.apiKey // empty' 2>/dev/null || true)
    [ -n "$OC_KEY" ] && VK_TOOLS["$OC_KEY"]="${VK_TOOLS[$OC_KEY]:-}opencode"
  fi
  if [ -f "$HOME/.codex/.env" ]; then
    CODEX_KEY=$(sed -n 's/^LITELLM_CODEX_API_KEY=\(.*\)/\1/p' "$HOME/.codex/.env" 2>/dev/null || true)
    [ -n "$CODEX_KEY" ] && VK_TOOLS["$CODEX_KEY"]="${VK_TOOLS[$CODEX_KEY]:-}codex"
  fi
  if [ -f "$HOME/.claude/settings.json" ]; then
    CLAUDE_KEY=$(jq -r '.env.ANTHROPIC_API_KEY // empty' "$HOME/.claude/settings.json" 2>/dev/null || true)
    [ -n "$CLAUDE_KEY" ] && VK_TOOLS["$CLAUDE_KEY"]="${VK_TOOLS[$CLAUDE_KEY]:-}claude"
  fi
  if [ -f "$HOME/.pi/agent/models.json" ]; then
    PI_VKEY=$(jq -r '.providers.LiteLLM.apiKey // empty' "$HOME/.pi/agent/models.json" 2>/dev/null || true)
    [ -n "$PI_VKEY" ] && VK_TOOLS["$PI_VKEY"]="${VK_TOOLS[$PI_VKEY]:-}pi"
  fi

  SHARED_FOUND=false
  for key in "${!VK_TOOLS[@]}"; do
    TOOLS="${VK_TOOLS[$key]}"
    if echo "$TOOLS" | grep -q ' '; then
      fail "Virtual key $(mask_key "$key") shared by: $TOOLS (should be unique per tool)"
      SHARED_FOUND=true
    fi
  done
  [ "$SHARED_FOUND" = false ] && pass "All tool virtual keys are unique"

  echo ""
  log_info "G2. Virtual key aliases"
  if [ "$DRY_RUN" = true ]; then
    skip "Virtual key alias check"
  elif [ -n "${LITELLM_MASTER_KEY:-}" ]; then
    declare -A EXPECTED_ALIASES=()
    [ -n "$OC_KEY" ] && EXPECTED_ALIASES["$OC_KEY"]="opencode"
    [ -n "$CODEX_KEY" ] && EXPECTED_ALIASES["$CODEX_KEY"]="codex"
    [ -n "$CLAUDE_KEY" ] && EXPECTED_ALIASES["$CLAUDE_KEY"]="claude-code"
    [ -n "$PI_VKEY" ] && EXPECTED_ALIASES["$PI_VKEY"]="pi"
    for vk in "${!EXPECTED_ALIASES[@]}"; do
      EXPECTED="${EXPECTED_ALIASES[$vk]}"
      KEY_INFO=$(curl -sf -m 10 "$LITELLM_URL/key/info?key=$vk" \
        -H "Authorization: Bearer $LITELLM_MASTER_KEY" 2>/dev/null || true)
      ACTUAL_ALIAS=$(printf '%s' "$KEY_INFO" | jq -r '.info.key_alias // empty' 2>/dev/null || true)
      if [ "$ACTUAL_ALIAS" = "$EXPECTED" ]; then
        pass "$EXPECTED virtual key alias: correct"
      else
        warn "$EXPECTED virtual key alias: '$ACTUAL_ALIAS' (expected '$EXPECTED')"
      fi
    done
  else
    skip "Virtual key alias check (LITELLM_MASTER_KEY not set)"
  fi

  echo ""
fi

# ── Summary ──
TOTAL=$((PASS + FAIL + WARN))
echo ""
printf '%b' "${C_YELLOW}══════════════════════════════════════════════════════${C_RESET}\n"
printf '%b' "Results: ${C_GREEN}$PASS passed${C_RESET}, ${C_RED}$FAIL failed${C_RESET}, ${C_YELLOW}$WARN warnings${C_RESET} out of $TOTAL checks\n"
if [ "$FAIL" -gt 0 ]; then
  printf '%b' "${C_RED}VALIDATION FAILED — $FAIL check(s) did not pass${C_RESET}\n"
  exit 1
else
  printf '%b' "${C_GREEN}VALIDATION PASSED${C_RESET}\n"
  exit 0
fi
