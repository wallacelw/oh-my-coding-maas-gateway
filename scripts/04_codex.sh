#!/usr/bin/env bash
set -euo pipefail

# ─── 04_codex.sh — Codex CLI tool (pipeline step 04, optional) ────────────────
#
# Domain:        Codex CLI
# Order:         04 (after LiteLLM proxy is live)
# Optional:      yes (runs only if codex is in the selection)
# Description:   Install the OpenAI Codex CLI, mint a LiteLLM virtual key
#                (alias "codex"), and write ~/.codex/config.toml (custom
#                litellm_proxy provider, wire_api=responses) + model_catalog.json
#                + .env with the API key. Codex uses the Responses API, bridged
#                to Chat Completions by LiteLLM.
# Inputs:        .env (LITELLM_MASTER_KEY), --virtual-key, --dry-run
# Outputs:       ~/.codex/config.toml, ~/.codex/model_catalog.json, ~/.codex/.env
# Standalone:    yes — ./scripts/04_codex.sh
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CODEX_DIR="$HOME/.codex"
CODEX_CONFIG="$CODEX_DIR/config.toml"
LITELLM_URL="http://127.0.0.1:4000"
CURL_TIMEOUT=15

source "$SCRIPT_DIR/helpers/prereqs.sh"
source "$SCRIPT_DIR/helpers/common.sh"
source "$SCRIPT_DIR/helpers/keys.sh"
source_env "$PROJECT_DIR"

# ── Parse args ──
VIRTUAL_KEY=""
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --virtual-key=*) VIRTUAL_KEY="${arg#--virtual-key=}" ;;
    --dry-run)       DRY_RUN=true ;;
  esac
done

echo "=== Step 04 — Codex CLI ==="
[ "$DRY_RUN" = true ] && echo "   (DRY RUN — no changes will be made)"
echo ""

# ── 1. Check prerequisites ──
echo "1. Checking prerequisites..."
prereq_ensure_apt "curl" curl curl
prereq_ensure_npm
prereq_ensure_apt "jq" jq jq
prereq_ensure_apt "bubblewrap" bwrap bubblewrap

if curl -sf -m $CURL_TIMEOUT "$LITELLM_URL/health/liveliness" &>/dev/null; then
  echo "   LiteLLM proxy: reachable"
else
  echo "ERROR: LiteLLM proxy not reachable at $LITELLM_URL. Start it first." >&2
  exit 1
fi
echo ""

# ── 2. Install Codex CLI ──
echo "2. Installing Codex CLI..."
if ! command -v codex &>/dev/null; then
  if [ "$DRY_RUN" = true ]; then
    echo "   Would run: npm install -g @openai/codex"
  else
    npm install -g @openai/codex
    echo "   Installed: $(codex --version 2>/dev/null || echo 'unknown')"
  fi
else
  echo "   Already installed: $(codex --version 2>/dev/null || echo 'unknown')"
fi
echo ""

# ── 3. Acquire virtual key (idempotent) ──
echo "3. Configuring LiteLLM virtual key..."

if [ -z "$VIRTUAL_KEY" ] && [ -f "$CODEX_DIR/.env" ]; then
  EXISTING_KEY=$(grep -oP '^LITELLM_CODEX_API_KEY=\K.*' "$CODEX_DIR/.env" 2>/dev/null || true)
  if [ -n "$EXISTING_KEY" ] && [[ "$EXISTING_KEY" == sk-* ]]; then
    if [ "$DRY_RUN" = true ]; then
      VIRTUAL_KEY="$EXISTING_KEY"
    elif retry_curl -sf -m $CURL_TIMEOUT "$LITELLM_URL/v1/responses" \
         -H "Authorization: Bearer $EXISTING_KEY" \
         -H "Content-Type: application/json" \
         -d '{"model":"deepseek-v3.2","input":"ok"}'; then
      echo "   Existing virtual key is valid. Reusing: $(mask_key "$EXISTING_KEY")"
      VIRTUAL_KEY="$EXISTING_KEY"
    else
      echo "   Existing virtual key is invalid. Minting new key."
    fi
  fi
fi

if [ -z "$VIRTUAL_KEY" ]; then
  if [ "$DRY_RUN" = true ]; then
    echo "   Would mint key (alias=codex, unlimited budget)"
    VIRTUAL_KEY="sk-dryrun-placeholder"
  else
    resolve_master_key "$PROJECT_DIR" || exit 1
    VIRTUAL_KEY=$(mint_or_reuse_key "codex" --no-budget)
    if [ -z "$VIRTUAL_KEY" ] || [[ "$VIRTUAL_KEY" != sk-* ]]; then
      echo "ERROR: Failed to mint virtual key." >&2
      exit 1
    fi
    echo "   Virtual key: $(mask_key "$VIRTUAL_KEY")"
  fi
fi
echo ""

# ── 4. Write config.toml + model_catalog ──
echo "4. Writing Codex CLI config..."
if [ "$DRY_RUN" = true ]; then
  echo "   Would write: $CODEX_CONFIG, $CODEX_DIR/model_catalog.json, $CODEX_DIR/.env"
  echo ""
  echo "=== Dry run complete — no changes made ==="
  exit 0
fi

mkdir -p "$CODEX_DIR"
cp "$PROJECT_DIR/configs/codex/model_catalog.json" "$CODEX_DIR/model_catalog.json"
echo "   Written: $CODEX_DIR/model_catalog.json"

TEMPLATE="$PROJECT_DIR/configs/codex/config.toml.template"
NEW_CONFIG=$(sed "s|<CODEX_HOME>|$CODEX_DIR|g" "$TEMPLATE")

if [ -f "$CODEX_CONFIG" ]; then
  if [ "$NEW_CONFIG" = "$(cat "$CODEX_CONFIG")" ]; then
    echo "   Config unchanged — skipping write"
  else
    cp "$CODEX_CONFIG" "$CODEX_CONFIG.bak.$(date +%Y%m%d%H%M%S)"
    echo "$NEW_CONFIG" > "$CODEX_CONFIG"
    chmod 600 "$CODEX_CONFIG"
    echo "   Updated: $CODEX_CONFIG (backup saved)"
  fi
else
  echo "$NEW_CONFIG" > "$CODEX_CONFIG"
  chmod 600 "$CODEX_CONFIG"
  echo "   Written: $CODEX_CONFIG"
fi
echo ""

# ── 5. Write API key to ~/.codex/.env ──
echo "5. Writing API key to $CODEX_DIR/.env..."
ENV_FILE="$CODEX_DIR/.env"
NEW_ENV="LITELLM_CODEX_API_KEY=$VIRTUAL_KEY"

if [ -f "$ENV_FILE" ]; then
  if [ "$NEW_ENV" = "$(cat "$ENV_FILE")" ]; then
    echo "   .env unchanged — skipping write"
  else
    echo "$NEW_ENV" > "$ENV_FILE"
    chmod 600 "$ENV_FILE"
    echo "   Updated: $ENV_FILE (chmod 600)"
  fi
else
  echo "$NEW_ENV" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "   Written: $ENV_FILE (chmod 600)"
fi
echo ""

echo "=== Codex CLI installation complete ==="
echo "  Default model: glm-5.2"
echo "  Run: codex"
