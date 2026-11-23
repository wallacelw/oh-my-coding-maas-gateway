#!/usr/bin/env bash
set -euo pipefail
umask 077  # written configs hold API keys — deny group/world access

# ─── 03d_pi.sh — Pi coding agent (pipeline step 03d, optional) ──────────────────
#
# Domain:        @earendil-works/pi-coding-agent
# Order:         03d (after LiteLLM proxy is live)
# Optional:      yes (runs only if pi is in the selection)
# Description:   Install the pi binary via npm (Node >= NODE_MCP_MIN_VERSION
#                ensured first; NodeSource if missing), falling back to the
#                pi.dev installer (run so it can never auto-start pi) only when
#                npm-direct fails or Node was declined interactively. Never
#                launches pi. Mints a LiteLLM virtual key (alias "pi") and writes
#                models.json pointing to the LiteLLM proxy with all available
#                models.
# Inputs:        .env (LITELLM_MASTER_KEY, HUAWEI_MAAS_API_KEY), --virtual-key, --dry-run
# Outputs:       ~/.pi/agent/models.json
# Standalone:    yes — ./scripts/03d_pi.sh
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PI_DIR="$HOME/.pi/agent"
PI_CONFIG="$PI_DIR/models.json"

PI_INSTALL_URL="https://pi.dev/install.sh"
CURL_TIMEOUT=15

source "$SCRIPT_DIR/helpers/prereqs.sh"
source "$SCRIPT_DIR/helpers/common.sh"
source "$SCRIPT_DIR/helpers/keys.sh"
source "$SCRIPT_DIR/helpers/models.sh"
source "$SCRIPT_DIR/helpers/versions.sh"
source_env "$PROJECT_DIR"

# ── Parse args ──
DRY_RUN=false
VIRTUAL_KEY=""
for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=true ;;
    --virtual-key=*) VIRTUAL_KEY="${arg#--virtual-key=}" ;;
    *) log_error "Unknown flag: $arg"; exit 1 ;;
  esac
done

log_step "Step 03d — Pi coding agent"
[ "$DRY_RUN" = true ] && log_warn "DRY RUN — no changes will be made"

# ── 1. Check prerequisites ──
log_info "Checking prerequisites..."
if [ "$DRY_RUN" = true ]; then
  log_dim "Dry-run: skipping prerequisite installs"
else
  prereq_ensure_apt "curl" curl curl "curl is needed to download the Pi agent installer"
  prereq_ensure_apt "jq"   jq   jq   "jq is needed to parse Pi config JSON"
fi

if [ "$DRY_RUN" = true ]; then
  log_dim "Dry-run: skipping LiteLLM proxy check"
elif curl -sf -m $CURL_TIMEOUT "http://127.0.0.1:4000/health/liveliness" &>/dev/null; then
  log_ok "LiteLLM proxy: reachable"
else
  log_error "LiteLLM proxy not reachable at http://127.0.0.1:4000. Start it first."
  exit 1
fi

# ── 2. Install pi ──
log_info "Installing pi..."
if ! command -v pi &>/dev/null; then
  if [ "$DRY_RUN" = true ]; then
    log_info "Would ensure Node >= $NODE_MCP_MIN_VERSION (NodeSource 22.x if missing)"
    log_info "Would run: npm install -g --ignore-scripts --min-release-age=0 @earendil-works/pi-coding-agent"
  else
    # 2a. Ensure Node — single repo-wide floor (approved decision)
    if prereq_ensure_node_mcp "Node.js is required to install the Pi agent"; then
      export PATH="${NODE_MCP_BIN_DIR}:$PATH"
      hash -r 2>/dev/null || true
      NODE_OK=true
    else
      NODE_OK=false
      if [ "${AUTO_YES:-false}" = true ]; then
        log_error "Node.js >= $NODE_MCP_MIN_VERSION is required and could not be ensured."
        log_dim "  Install Node 22.x (e.g. https://deb.nodesource.com/setup_22.x) and re-run, or run this script interactively."
        exit 1
      fi
      # interactive + node ensure declined → the pi.dev installer can install
      # its own standalone Node without sudo; fall through to it below.
    fi

    # 2b. npm-direct (primary path, all modes)
    PI_INSTALLED=false
    if [ "$NODE_OK" = true ]; then
      if ! command -v npm &>/dev/null; then
        log_dim "npm not found — using the pi.dev installer"
      else
        log_dim "Node.js $(node --version 2>/dev/null || echo '?') — installing Pi via npm"
        if npm_install_global "@earendil-works/pi-coding-agent" --ignore-scripts --min-release-age=0; then
          PI_INSTALLED=true
        else
          log_warn "npm install of Pi failed — falling back to the pi.dev installer"
        fi
      fi
    fi

    # 2c. pi.dev installer fallback (npm-direct failed, or node ensure declined interactively)
    if [ "$PI_INSTALLED" = false ]; then
      log_info "Using the pi.dev installer (fallback)..."
      PI_INSTALLER_TMP=$(mktemp)
      if ! curl -fsSL --max-time 60 "$PI_INSTALL_URL" -o "$PI_INSTALLER_TMP"; then
        log_error "Failed to download Pi installer."; rm -f "$PI_INSTALLER_TMP"; exit 1
      fi
      log_dim "Pi installer downloaded ($(wc -c < "$PI_INSTALLER_TMP") bytes)"
      # Clean up temp files on Ctrl-C / SIGTERM. The detached installer is NOT
      # killed — it completes headless and cannot launch pi without a tty (benign).
      trap 'rm -f "$PI_INSTALLER_TMP" "${PI_LOG:-}" 2>/dev/null; exit 130' INT TERM
      if [ "${AUTO_YES:-false}" = true ] || ! is_interactive; then
        # Non-interactive / no controlling terminal (AUTO_YES, CI, ssh without
        # -t): the installer auto-defaults its menu and its start-pi prompt
        # self-disables. setsid detaches the session's tty; -w waits for
        # completion. (flock already requires util-linux.)
        if ! command -v setsid &>/dev/null; then
          log_error "setsid (util-linux) is required for the non-interactive Pi installer fallback."
          rm -f "$PI_INSTALLER_TMP"; exit 1
        fi
        PI_LOG=$(mktemp)
        setsid -w sh "$PI_INSTALLER_TMP" </dev/null >"$PI_LOG" 2>&1 && _pi_rc=0 || _pi_rc=$?
        while IFS= read -r line; do log_dim "$line"; done < "$PI_LOG"
        rm -f "$PI_LOG"
      else
        # Interactive (controlling terminal): pipe stdout through tee so the
        # installer's stdout is NOT a tty — its "Start pi now? [Y/n]" prompt
        # self-disables (the action menu still shows via /dev/tty). Pi must
        # never auto-start mid-pipeline.
        sh "$PI_INSTALLER_TMP" 2>&1 | tee /dev/tty && _pi_rc=0 || _pi_rc=$?
      fi
      trap - INT TERM
      rm -f "$PI_INSTALLER_TMP"
    else
      _pi_rc=0
    fi

    # 2d. PATH refresh + verification
    # Refresh PATH — installer may have added ~/.local/bin or updated nvm
    hash -r 2>/dev/null || true
    # Also check common install locations
    for _dir in \
      "$HOME/.local/bin" \
      "$HOME/.npm-global/bin" \
      "$HOME/.pi/agent/bin" \
      "/usr/local/bin"; do
      [ -x "$_dir/pi" ] && export PATH="$_dir:$PATH"
    done
    # Check nvm Node versions
    for _dir in $(ls -d "$HOME/.nvm/versions/node"/*/bin 2>/dev/null || true); do
      [ -x "$_dir/pi" ] && export PATH="$_dir:$PATH"
    done
    # Check pi-node versioned dirs — add when they hold pi OR node
    # (the ~/.pi/agent/bin wrapper execs a managed binary whose shebang
    # resolves node via PATH, so the managed node dir must be on PATH)
    for _dir in $(ls -d "$HOME/.local/share/pi-node"/*/bin 2>/dev/null || true); do
      if [ -x "$_dir/pi" ] || [ -x "$_dir/node" ]; then
        export PATH="$_dir:$PATH"
      fi
    done
    if ! command -v pi &>/dev/null; then
      log_error "pi binary not found after install."
      log_dim "  The installer may have added a PATH entry to ~/.bashrc."
      log_dim "  Run: exec \"\$SHELL\"  then re-run this script."
      exit 1
    fi
    if [ "$_pi_rc" -ne 0 ]; then
      log_error "Pi install reported an error (exit code $_pi_rc) — see the output above."
      exit 1
    fi
    log_ok "Installed: $(pi --version 2>/dev/null || echo 'unknown')"
  fi
else
  _pi_cur=$(pi --version 2>/dev/null || echo "unknown")
  log_ok "Already installed: $_pi_cur"
  # Surface version drift — 03d installs, it does not update (update.sh owns that)
  if command -v npm &>/dev/null; then
    _pi_latest=$(timeout 15 npm view @earendil-works/pi-coding-agent version 2>/dev/null || true)
    if [ -n "$_pi_latest" ] && [ "$_pi_cur" != "$_pi_latest" ]; then
      log_dim "  Update available: $_pi_cur → $_pi_latest — run: ./scripts/update.sh"
    fi
  fi
fi

# ── 3. Acquire virtual key (idempotent) ──
log_info "Configuring LiteLLM virtual key..."

# If --virtual-key= was provided, use it directly
if [ -n "$VIRTUAL_KEY" ]; then
  log_ok "Using provided virtual key: $(mask_key "$VIRTUAL_KEY")"
# Try to reuse existing key from current pi config (fast, local)
elif [ -f "$PI_CONFIG" ]; then
  EXISTING_KEY=$(jq -r '.providers.LiteLLM.apiKey // empty' "$PI_CONFIG" 2>/dev/null || true)
  if [ -n "$EXISTING_KEY" ] && [[ "$EXISTING_KEY" == sk-* ]]; then
    if [ "$DRY_RUN" = true ]; then
      VIRTUAL_KEY="$EXISTING_KEY"
    elif retry_curl -sf -m $CURL_TIMEOUT "http://127.0.0.1:4000/v1/chat/completions" \
         --config - \
         -H "Content-Type: application/json" \
         -d '{"model":"deepseek-v4.1-flash-1017","messages":[{"role":"user","content":"ok"}],"max_tokens":1}' <<CURLCFG; then
header = "Authorization: Bearer $EXISTING_KEY"
CURLCFG
      log_ok "Existing virtual key is valid. Reusing: $(mask_key "$EXISTING_KEY")"
      VIRTUAL_KEY="$EXISTING_KEY"
    else
      log_warn "Existing virtual key is invalid or expired. Minting new key."
    fi
  fi
fi

if [ -z "$VIRTUAL_KEY" ]; then
  if [ "$DRY_RUN" = true ]; then
    log_info "Would mint key (alias=pi, unlimited budget)"
    VIRTUAL_KEY="sk-dryrun-placeholder"
  else
    resolve_master_key "$PROJECT_DIR" || exit 1
    VIRTUAL_KEY=$(mint_or_reuse_key "pi" --no-budget)
    if [ -z "$VIRTUAL_KEY" ] || [[ "$VIRTUAL_KEY" != sk-* ]]; then
      log_error "Failed to mint virtual key."
      exit 1
    fi
    log_ok "Virtual key: $(mask_key "$VIRTUAL_KEY")"
  fi
fi

# ── 4. Generate models.json ──
log_info "Generating models.json..."

if [ "$DRY_RUN" = true ]; then
  log_info "Would write: $PI_CONFIG"
  echo ""
  log_info "Dry run complete — no changes made"
  exit 0
fi

mkdir -p "$PI_DIR"

# Build models array from MODELS
# Format: model_name:tpm:rpm:max_tokens:max_input:max_output:input_cost:output_cost:cache_read_cost:cache_creation_cost
MODELS_JSON="[]"
for model_entry in "${MODELS[@]}"; do
  IFS=':' read -r model_name tpm rpm max_tokens max_input max_output input_cost output_cost cache_read_cost cache_creation_cost <<< "$model_entry"

  # Use max_tokens as contextWindow (total context), max_output as maxTokens (output limit)
  MODELS_JSON=$(echo "$MODELS_JSON" | jq --arg id "$model_name" \
                                    --arg name "$model_name" \
                                    --argjson cw "$max_tokens" \
                                    --argjson mt "$max_output" \
    '. + [{"id": $id, "name": $name, "contextWindow": $cw, "maxTokens": $mt}]')
done

# Build the full config
NEW_CONFIG=$(jq -n \
  --arg vk "$VIRTUAL_KEY" \
  --argjson models "$MODELS_JSON" \
  '{
    "providers": {
      "LiteLLM": {
        "baseUrl": "http://127.0.0.1:4000/v1",
        "api": "openai-completions",
        "apiKey": $vk,
        "models": $models
      }
    }
  }')

if [ -z "$NEW_CONFIG" ] || ! echo "$NEW_CONFIG" | jq -e . >/dev/null 2>&1; then
  log_error "Failed to generate pi config."
  exit 1
fi

# ── Merge-preserve: keep user-added providers/fields in an existing models.json ──
# Only the generated LiteLLM provider block is replaced (mirrors 03a/03b/03c).
# A non-JSON existing file falls back to the full rewrite below (backup+replace).
if [ -f "$PI_CONFIG" ] && jq -e . "$PI_CONFIG" >/dev/null 2>&1; then
  MERGED=$(jq --argjson new "$NEW_CONFIG" '.providers.LiteLLM = $new.providers.LiteLLM' "$PI_CONFIG" 2>/dev/null) || MERGED=""
  if [ -n "$MERGED" ] && echo "$MERGED" | jq -e . >/dev/null 2>&1; then
    NEW_CONFIG="$MERGED"
  fi
fi

# ── 5. Write models.json ──
if [ -f "$PI_CONFIG" ]; then
  if [ "$NEW_CONFIG" = "$(cat "$PI_CONFIG")" ]; then
    log_info "Config unchanged — skipping write"
  else
    backup_with_prune "$PI_CONFIG" >/dev/null
    echo "$NEW_CONFIG" > "$PI_CONFIG"
    chmod 600 "$PI_CONFIG"
    log_ok "Updated: $PI_CONFIG (backup saved)"
  fi
else
  echo "$NEW_CONFIG" > "$PI_CONFIG"
  chmod 600 "$PI_CONFIG"
  log_ok "Written: $PI_CONFIG"
fi

echo ""
log_ok "Pi agent installation complete"
log_info "Provider: LiteLLM — ${#MODELS[@]} models available"
log_info "Run: pi"
