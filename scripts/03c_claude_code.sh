#!/usr/bin/env bash
set -euo pipefail
umask 077  # written configs hold API keys — deny group/world access

# ─── 03c_claude_code.sh — Claude Code CLI tool (pipeline step 03c, optional) ────
#
# Domain:        Claude Code CLI
# Order:         03c (after LiteLLM proxy is live)
# Optional:      yes (runs only if claude is in the selection)
# Description:   Install the Claude Code CLI, mint a LiteLLM virtual key
#                (alias "claude-code"), and write ~/.claude/settings.json
#                (env block pointing to the LiteLLM proxy via the Anthropic
#                Messages API). Adds modelOverrides + modelPicker + alias env
#                vars so Claude Code recognizes and offers the gateway's claude-*
#                model IDs (unknown claude-* IDs otherwise trigger the
#                unrecognized-model path). Disables the VSCode extension
#                auto-install.
# Inputs:        .env (LITELLM_MASTER_KEY), --virtual-key, --dry-run
# Outputs:       ~/.claude/settings.json, ~/.claude.json
# Standalone:    yes — ./scripts/03c_claude_code.sh
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAUDE_CONFIG_DIR="$HOME/.claude"
CLAUDE_SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"
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
    *) log_error "Unknown flag: $arg"; exit 1 ;;
  esac
done

log_step "Step 03c — Claude Code CLI"
[ "$DRY_RUN" = true ] && log_warn "DRY RUN — no changes will be made"

# ── 1. Check prerequisites ──
log_info "Checking prerequisites..."
if [ "$DRY_RUN" = true ]; then
  log_dim "Dry-run: skipping prerequisite installs"
else
  prereq_ensure_apt "curl" curl curl "curl is needed to download Claude Code CLI"
  prereq_ensure_npm "Node.js + npm are needed to install and run Claude Code CLI"
  prereq_ensure_apt "jq" jq jq "jq is needed to parse Claude Code config JSON"
fi

if [ "$DRY_RUN" = true ]; then
  log_dim "Dry-run: skipping LiteLLM proxy check"
elif curl -sf -m $CURL_TIMEOUT "$LITELLM_URL/health/liveliness" &>/dev/null; then
  log_ok "LiteLLM proxy: reachable"
else
  log_error "LiteLLM proxy not reachable at $LITELLM_URL. Start it first."
  exit 1
fi

# ── 2. Install Claude Code CLI ──
log_info "Installing Claude Code CLI..."
if ! command -v claude &>/dev/null; then
  if [ "$DRY_RUN" = true ]; then
    log_info "Would run: npm install -g @anthropic-ai/claude-code"
  else
    npm_install_global "@anthropic-ai/claude-code"
    log_ok "Installed: $(claude --version 2>/dev/null || echo 'unknown')"
  fi
else
  log_ok "Already installed: $(claude --version 2>/dev/null || echo 'unknown')"
fi

# ── 3. Acquire virtual key (idempotent) ──
log_info "Configuring LiteLLM virtual key..."

if [ -z "$VIRTUAL_KEY" ] && [ -f "$CLAUDE_SETTINGS" ]; then
  EXISTING_KEY=$(jq -r '.env.ANTHROPIC_API_KEY // empty' "$CLAUDE_SETTINGS" 2>/dev/null || true)
  if [ -n "$EXISTING_KEY" ] && [[ "$EXISTING_KEY" == sk-* ]]; then
    if [ "$DRY_RUN" = true ]; then
      VIRTUAL_KEY="$EXISTING_KEY"
    elif retry_curl -sf -m $CURL_TIMEOUT "$LITELLM_URL/v1/messages" \
         --config - \
         -H "Content-Type: application/json" \
         -H "anthropic-version: 2023-06-01" \
         -d '{"model":"claude-deepseek-v4.1-flash-1017","messages":[{"role":"user","content":"ok"}],"max_tokens":1}' <<CURLCFG; then
header = "x-api-key: $EXISTING_KEY"
CURLCFG
      log_ok "Existing virtual key is valid. Reusing: $(mask_key "$EXISTING_KEY")"
      VIRTUAL_KEY="$EXISTING_KEY"
    else
      log_warn "Existing virtual key is invalid. Minting new key."
    fi
  fi
fi

if [ -z "$VIRTUAL_KEY" ]; then
  if [ "$DRY_RUN" = true ]; then
    log_info "Would mint key (alias=claude-code, unlimited budget)"
    VIRTUAL_KEY="sk-dryrun-placeholder"
  else
    resolve_master_key "$PROJECT_DIR" || exit 1
    VIRTUAL_KEY=$(mint_or_reuse_key "claude-code" --no-budget)
    if [ -z "$VIRTUAL_KEY" ] || [[ "$VIRTUAL_KEY" != sk-* ]]; then
      log_error "Failed to mint virtual key."
      exit 1
    fi
    log_ok "Virtual key: $(mask_key "$VIRTUAL_KEY")"
  fi
fi

# ── 4. Write settings.json ──
log_info "Writing Claude Code CLI config..."
if [ "$DRY_RUN" = true ]; then
  log_info "Would write: $CLAUDE_SETTINGS, ~/.claude.json"
  echo ""
  log_info "Dry run complete — no changes made"
  exit 0
fi

mkdir -p "$CLAUDE_CONFIG_DIR"

# Claude Code only recognizes model IDs it knows, or IDs that appear as VALUES
# in modelOverrides. Unknown claude-* IDs hit the unrecognized-model path
# (warnings, version-dependent refusals). Anchoring each gateway ID to a
# [1m]-suffixed known Anthropic ID makes it recognized while every request
# still carries our model name. The picker rows give the models their own
# labels; the alias vars repoint opus/sonnet/haiku at our models.
NEW_SETTINGS_BLOCK=$(jq -n \
  --arg base_url "http://127.0.0.1:4000" \
  --arg api_key "$VIRTUAL_KEY" \
  --arg model "claude-glm-5.3" \
  --arg fast_model "claude-deepseek-v4.1-flash-1017" \
  --arg sonnet_anchor "claude-sonnet-4-5[1m]" \
  --arg haiku_anchor "claude-haiku-4-5[1m]" \
  '{
    env: {
      ANTHROPIC_BASE_URL: $base_url,
      ANTHROPIC_API_KEY: $api_key,
      ANTHROPIC_MODEL: $model,
      ANTHROPIC_SMALL_FAST_MODEL: $fast_model,
      ANTHROPIC_DEFAULT_OPUS_MODEL: $model,
      ANTHROPIC_DEFAULT_SONNET_MODEL: $model,
      ANTHROPIC_DEFAULT_HAIKU_MODEL: $fast_model,
      CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY: "1",
      CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL: "1"
    },
    modelOverrides: {($sonnet_anchor): $model, ($haiku_anchor): $fast_model},
    modelPicker: {options: [
      {model: $model, label: "GLM 5.3 (LiteLLM)", description: "Flagship reasoning model via the LiteLLM gateway", behavesAs: $sonnet_anchor},
      {model: $fast_model, label: "DeepSeek Flash (LiteLLM)", description: "Fast model via the LiteLLM gateway", behavesAs: $haiku_anchor}
    ]}
  }')

if [ -f "$CLAUDE_SETTINGS" ]; then
  EXISTING_SETTINGS=$(cat "$CLAUDE_SETTINGS")
  if echo "$EXISTING_SETTINGS" | jq -e 'type == "object"' >/dev/null 2>&1; then
    # jq '*' deep-merges objects (env/modelOverrides keep user keys) but
    # REPLACES arrays — so rebuild modelPicker.options as our rows first, then
    # any pre-existing user rows whose model isn't one of ours (dedupe by .model).
    # replaceBuiltInOptions survives the deep merge untouched. Read the existing
    # file via --slurpfile (an --argjson approach would hit the execve
    # argument limit on >128KB files).
    MERGED_SETTINGS=$(jq -n \
      --slurpfile old "$CLAUDE_SETTINGS" \
      --argjson new "$NEW_SETTINGS_BLOCK" '
      ($old[0] // {}) * ($new // {})
      | .modelPicker.options = (
          ($new.modelPicker.options // []) + (
            ($old[0].modelPicker.options // [])
            | map(select(.model as $m | ($new.modelPicker.options // []) | map(.model) | index($m) | not))
          )
        )')
    if [ "$MERGED_SETTINGS" = "$EXISTING_SETTINGS" ]; then
      # Content identical — still enforce 600 (external tools may relax it).
      if [ "$(stat -c '%a' "$CLAUDE_SETTINGS" 2>/dev/null)" != "600" ]; then
        chmod 600 "$CLAUDE_SETTINGS" 2>/dev/null || true
      fi
      log_info "settings.json unchanged — skipping write"
    else
      EXISTING_KEYS=$(echo "$EXISTING_SETTINGS" | jq -r 'keys | .[]' 2>/dev/null | sort -u)
      NON_ENV_KEYS=$(echo "$EXISTING_KEYS" | grep -v '^env$' || true)
      if [ -n "$NON_ENV_KEYS" ]; then
        log_info "Merging settings (preserving existing keys: $(echo "$NON_ENV_KEYS" | tr '\n' ' '))"
      fi
      backup_with_prune "$CLAUDE_SETTINGS" >/dev/null
      echo "$MERGED_SETTINGS" > "$CLAUDE_SETTINGS"
      chmod 600 "$CLAUDE_SETTINGS"
      log_ok "Updated: $CLAUDE_SETTINGS (backup saved, merged settings block)"
    fi
  else
    log_warn "Existing settings.json is invalid or non-object JSON — creating backup and overwriting"
    backup_with_prune "$CLAUDE_SETTINGS" >/dev/null
    echo "$NEW_SETTINGS_BLOCK" > "$CLAUDE_SETTINGS"
    chmod 600 "$CLAUDE_SETTINGS"
    log_ok "Written: $CLAUDE_SETTINGS (backup saved)"
  fi
else
  echo "$NEW_SETTINGS_BLOCK" > "$CLAUDE_SETTINGS"
  chmod 600 "$CLAUDE_SETTINGS"
  log_ok "Written: $CLAUDE_SETTINGS"
fi

# ── 5. Disable VSCode extension auto-install ──
log_info "Disabling VSCode extension auto-install..."
CLAUDE_JSON="$HOME/.claude.json"
if [ -f "$CLAUDE_JSON" ]; then
  CURRENT=$(jq '.autoInstallIdeExtension // empty' "$CLAUDE_JSON" 2>/dev/null || true)
  if [ "$CURRENT" = "false" ]; then
    log_info "autoInstallIdeExtension already false"
  else
    jq '.autoInstallIdeExtension = false' "$CLAUDE_JSON" > "$CLAUDE_JSON.tmp" && mv "$CLAUDE_JSON.tmp" "$CLAUDE_JSON" && rc=0 || rc=$?
    if [ "$rc" -eq 0 ]; then
      log_ok "Set autoInstallIdeExtension=false in ~/.claude.json"
    else
      rm -f "$CLAUDE_JSON.tmp"
      log_warn "Could not set autoInstallIdeExtension in ~/.claude.json (jq failed — file may be corrupt)"
    fi
  fi
else
  echo '{"autoInstallIdeExtension": false}' > "$CLAUDE_JSON"
  log_ok "Created ~/.claude.json with autoInstallIdeExtension=false"
fi

if command -v code &>/dev/null; then
  if code --list-extensions 2>/dev/null | grep -qi "anthropic.claude-code"; then
    code --uninstall-extension anthropic.claude-code 2>/dev/null && \
      log_ok "Uninstalled anthropic.claude-code VSCode extension" || \
      log_warn "could not uninstall VSCode extension"
  else
    log_info "VSCode extension not installed — nothing to remove"
  fi
else
  log_info "VSCode CLI (code) not found — skipping extension check"
fi

echo ""
log_ok "Claude Code CLI installation complete"
log_info "Default model: claude-glm-5.3"
log_info "Model anchors: sonnet→claude-glm-5.3, haiku→claude-deepseek-v4.1-flash-1017 (recognized via modelOverrides)"
log_info "Run: claude --bare"
