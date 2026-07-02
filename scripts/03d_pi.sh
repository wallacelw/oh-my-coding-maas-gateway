#!/usr/bin/env bash
set -euo pipefail

# ─── 03d_pi.sh — Pi coding agent (pipeline step 03d, optional) ──────────────────
#
# Domain:        @earendil-works/pi-coding-agent
# Order:         03d (after LiteLLM proxy is live)
# Optional:      yes (runs only if pi is in the selection)
# Description:   Install the pi binary via curl|sh from pi.dev, mint a LiteLLM virtual key
#                (alias "pi"), and write models.json pointing to the LiteLLM
#                proxy with all available models.
# Inputs:        .env (LITELLM_MASTER_KEY, HUAWEI_MAAS_API_KEY), --dry-run
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
source_env "$PROJECT_DIR"

LOG_TAG="pi"

# ── Parse args ──
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --dry-run)       DRY_RUN=true ;;
    *) log_error "Unknown flag: $arg"; exit 1 ;;
  esac
done

log_step "Step 03d — Pi coding agent"
[ "$DRY_RUN" = true ] && log_warn "DRY RUN — no changes will be made"

# ── 1. Check prerequisites ──
log_info "Checking prerequisites..."
prereq_ensure_apt "curl" curl curl
prereq_ensure_apt "jq"   jq   jq
prereq_ensure_npm "pi" npm

if curl -sf -m $CURL_TIMEOUT "http://127.0.0.1:4000/health/liveliness" &>/dev/null; then
  log_ok "LiteLLM proxy: reachable"
else
  log_error "LiteLLM proxy not reachable at http://127.0.0.1:4000. Start it first."
  exit 1
fi

# ── 2. Install pi ──
log_info "Installing pi..."
if ! command -v pi &>/dev/null; then
  if [ "$DRY_RUN" = true ]; then
    log_dim "Would run: curl -fsSL $PI_INSTALL_URL | sh"
  else
    run_filtered "pi" sh -c "curl -fsSL $PI_INSTALL_URL | sh"
    log_ok "Installed: $(pi --version 2>/dev/null || echo 'pi')"
  fi
else
  log_ok "Already installed: $(pi --version 2>/dev/null || echo 'pi')"
fi

# ── 3. Acquire virtual key (idempotent) ──
log_info "Configuring LiteLLM virtual key..."

VIRTUAL_KEY=""

# Try to reuse existing key from current pi config (fast, local)
if [ -f "$PI_CONFIG" ]; then
  EXISTING_KEY=$(jq -r '.providers.LiteLLM.apiKey // empty' "$PI_CONFIG" 2>/dev/null || true)
  if [ -n "$EXISTING_KEY" ] && [[ "$EXISTING_KEY" == sk-* ]]; then
    if [ "$DRY_RUN" = true ]; then
      VIRTUAL_KEY="$EXISTING_KEY"
    elif retry_curl -sf -m $CURL_TIMEOUT "http://127.0.0.1:4000/v1/chat/completions" \
         -H "Authorization: Bearer $EXISTING_KEY" \
         -H "Content-Type: application/json" \
         -d '{"model":"deepseek-v3.2","messages":[{"role":"user","content":"ok"}],"max_tokens":1}'; then
      log_ok "Existing virtual key is valid. Reusing: $(mask_key "$EXISTING_KEY")"
      VIRTUAL_KEY="$EXISTING_KEY"
    else
      log_warn "Existing virtual key is invalid or expired. Minting new key."
    fi
  fi
fi

if [ -z "$VIRTUAL_KEY" ]; then
  if [ "$DRY_RUN" = true ]; then
    log_dim "Would mint key (alias=pi, unlimited budget)"
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
  log_dim "Would write: $PI_CONFIG"
  log_step "Dry run complete — no changes made"
  exit 0
fi

mkdir -p "$PI_DIR"

# Build models array from MODELS
# Format: model_name:tpm:rpm:max_tokens:max_input:max_output:input_cost:output_cost
MODELS_JSON="[]"
for model_entry in "${MODELS[@]}"; do
  IFS=':' read -r model_name tpm rpm max_tokens max_input max_output input_cost output_cost <<< "$model_entry"
  
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

# ── 5. Write models.json ──
if [ -f "$PI_CONFIG" ]; then
  if [ "$NEW_CONFIG" = "$(cat "$PI_CONFIG")" ]; then
    log_dim "Config unchanged — skipping write"
  else
    cp "$PI_CONFIG" "$PI_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    echo "$NEW_CONFIG" > "$PI_CONFIG"
    chmod 600 "$PI_CONFIG"
    log_ok "Updated: $PI_CONFIG (backup saved)"
  fi
else
  echo "$NEW_CONFIG" > "$PI_CONFIG"
  chmod 600 "$PI_CONFIG"
  log_ok "Written: $PI_CONFIG"
fi

log_step "Pi installation complete"
log_dim "Provider: LiteLLM — ${#MODELS[@]} models available"
log_dim "Config: $PI_CONFIG"
