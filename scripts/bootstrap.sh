#!/usr/bin/env bash
set -euo pipefail

# ─── bootstrap.sh — Install orchestrator (entry point) ────────────────────────
#
# Domain:        Orchestration
# Description:   Thin sequencer. Resolves the tool selection (interactive menu
#                or --tool=), ensures core prerequisites, runs the numbered
#                pipeline steps (01_env → 02_litellm → 03/04/05 tools →
#                06_validate), and prints a summary. This is the only script a
#                human needs to run. Each step is independently runnable too.
#
# Usage:
#   ./bootstrap.sh                          # interactive — shows tool selection menu
#   ./bootstrap.sh --tool=all               # install all (default)
#   ./bootstrap.sh --tool=litellm           # LiteLLM proxy only
#   ./bootstrap.sh --tool=opencode,codex    # custom combo
#   ./bootstrap.sh --virtual-key=sk-...     # reuse existing opencode virtual key
#   ./bootstrap.sh --dry-run                # preview without changes
#
# Non-interactive (CI / agent):
#   HUAWEI_MAAS_API_KEY=$KEY ./bootstrap.sh --tool=opencode
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LITELLM_URL="http://127.0.0.1:4000"

source "$SCRIPT_DIR/helpers/prereqs.sh"
source "$SCRIPT_DIR/helpers/common.sh"

# ── Defaults ──
VIRTUAL_KEY=""
DRY_RUN=false
TOOL_SPECIFIED=false
TOOL_SELECTION=""
INSTALL_OPENCODE=true
INSTALL_CODEX=true
INSTALL_CLAUDE_CODE=true

# ── Parse args ──
for arg in "$@"; do
  case "$arg" in
    --virtual-key=*) VIRTUAL_KEY="${arg#--virtual-key=}" ;;
    --dry-run)       DRY_RUN=true ;;
    --tool=*)        TOOL_SPECIFIED=true; TOOL_SELECTION="${arg#--tool=}" ;;
    *)
      echo "Usage: $0 [--tool=all|litellm|opencode|codex|claude|opencode,codex,...] [--virtual-key=sk-...] [--dry-run]"
      exit 1
      ;;
  esac
done

# ── Parse --tool= into INSTALL_* flags ──
if [ "$TOOL_SPECIFIED" = true ]; then
  INSTALL_OPENCODE=false
  INSTALL_CODEX=false
  INSTALL_CLAUDE_CODE=false
  IFS=',' read -ra TOOL_PARTS <<< "$TOOL_SELECTION"
  for part in "${TOOL_PARTS[@]}"; do
    case "$part" in
      all)       INSTALL_OPENCODE=true; INSTALL_CODEX=true; INSTALL_CLAUDE_CODE=true ;;
      litellm)   ;;
      opencode)  INSTALL_OPENCODE=true ;;
      codex)     INSTALL_CODEX=true ;;
      claude)    INSTALL_CLAUDE_CODE=true ;;
      *)
        echo "ERROR: Unknown tool '$part' in --tool=$TOOL_SELECTION"
        echo "Valid values: all, litellm, opencode, codex, claude (or comma-separated combo)"
        exit 1
        ;;
    esac
  done
fi

# ── Banner ──
echo ""
echo "=== oh-my-coding-maas-gateway Bootstrap ==="
echo "   Project dir: $PROJECT_DIR"
[ "$DRY_RUN" = true ] && echo "   (DRY RUN — no changes will be made)"
echo ""

# ── Core prerequisites ──
echo "─── Core prerequisites ───"
prereq_ensure_apt "git"     git     git
prereq_ensure_apt "python3" python3 python3
prereq_ensure_apt "curl"    curl    curl
prereq_ensure_apt "jq"      jq      jq
echo ""

# ── Tool selection (menu if --tool= not given) ──
if [ "$TOOL_SPECIFIED" = false ]; then
  echo "Select installation scope:"
  echo "  1) Default — LiteLLM + opencode + Codex + Claude Code"
  echo "  2) LiteLLM only"
  echo "  3) LiteLLM + opencode"
  echo "  4) LiteLLM + Codex"
  echo "  5) LiteLLM + Claude Code"
  echo "  6) Custom — toggle each component"
  echo -n "Enter choice [1]: "
  choice=""
  read -r choice < /dev/tty || choice="1"
  case "${choice:-1}" in
    1) INSTALL_OPENCODE=true;  INSTALL_CODEX=true;  INSTALL_CLAUDE_CODE=true ;;
    2) INSTALL_OPENCODE=false; INSTALL_CODEX=false; INSTALL_CLAUDE_CODE=false ;;
    3) INSTALL_OPENCODE=true;  INSTALL_CODEX=false; INSTALL_CLAUDE_CODE=false ;;
    4) INSTALL_OPENCODE=false; INSTALL_CODEX=true;  INSTALL_CLAUDE_CODE=false ;;
    5) INSTALL_OPENCODE=false; INSTALL_CODEX=false; INSTALL_CLAUDE_CODE=true ;;
    6)
      echo ""
      echo "Custom selection (LiteLLM is always installed):"
      yn=""
      echo -n "  Install opencode? [y/N]: ";    read -r yn < /dev/tty || yn="n"
      INSTALL_OPENCODE=false; [[ "$yn" =~ ^[Yy] ]] && INSTALL_OPENCODE=true
      echo -n "  Install Codex? [y/N]: ";       read -r yn < /dev/tty || yn="n"
      INSTALL_CODEX=false;    [[ "$yn" =~ ^[Yy] ]] && INSTALL_CODEX=true
      echo -n "  Install Claude Code? [y/N]: "; read -r yn < /dev/tty || yn="n"
      INSTALL_CLAUDE_CODE=false; [[ "$yn" =~ ^[Yy] ]] && INSTALL_CLAUDE_CODE=true
      ;;
    *)
      echo "Invalid choice. Defaulting to all."
      INSTALL_OPENCODE=true; INSTALL_CODEX=true; INSTALL_CLAUDE_CODE=true
      ;;
  esac
  echo ""
fi

# ── Show selected scope ──
echo "  Installation scope:"
echo "    LiteLLM:      yes (always)"
echo "    opencode:     $( [ "$INSTALL_OPENCODE" = true ] && echo "yes" || echo "no" )"
echo "    Codex:        $( [ "$INSTALL_CODEX" = true ] && echo "yes" || echo "no" )"
echo "    Claude Code:  $( [ "$INSTALL_CLAUDE_CODE" = true ] && echo "yes" || echo "no" )"
echo ""

# ── Selection-driven prerequisite summary ──
echo "  Prerequisites to install (as needed):"
echo "    core: git, python3, curl, jq, docker"
[ "$INSTALL_OPENCODE" = true ] && echo "    opencode: bun"
[ "$INSTALL_CODEX" = true ] && echo "    codex: npm/node, bubblewrap"
[ "$INSTALL_CLAUDE_CODE" = true ] && echo "    claude: npm/node"
echo ""

# ── Helper to run a step ──
run_step() {
  local step_name="$1"; shift
  echo ""
  echo "─── $step_name ───"
  if [ "$DRY_RUN" = true ]; then
    echo "  Would run: $*"
  else
    "$@"
  fi
}

# ── Step 01: Environment & secrets ──
if [ "$DRY_RUN" = true ]; then
  echo ""
  echo "─── Step 01: Environment & secrets ───"
  echo "  Would run: scripts/01_env.sh"
else
  "$SCRIPT_DIR/01_env.sh"
fi

# ── Step 02: LiteLLM proxy + observability ──
run_step "Step 02: LiteLLM proxy + observability" \
  "$SCRIPT_DIR/02_litellm.sh" $([ "$DRY_RUN" = true ] && echo "--dry-run")

# ── Step 03: opencode (optional) ──
if [ "$INSTALL_OPENCODE" = true ]; then
  OPENCODE_ARGS=()
  [ -n "$VIRTUAL_KEY" ] && OPENCODE_ARGS+=("--virtual-key=$VIRTUAL_KEY")
  [ "$DRY_RUN" = true ] && OPENCODE_ARGS+=("--dry-run")
  run_step "Step 03: opencode" "$SCRIPT_DIR/03_opencode.sh" "${OPENCODE_ARGS[@]}"
else
  echo "  (skipping opencode)"
fi

# ── Step 04: Codex CLI (optional) ──
if [ "$INSTALL_CODEX" = true ]; then
  CODEX_ARGS=()
  [ "$DRY_RUN" = true ] && CODEX_ARGS+=("--dry-run")
  run_step "Step 04: Codex CLI" "$SCRIPT_DIR/04_codex.sh" "${CODEX_ARGS[@]}"
else
  echo "  (skipping Codex CLI)"
fi

# ── Step 05: Claude Code CLI (optional) ──
if [ "$INSTALL_CLAUDE_CODE" = true ]; then
  CLAUDE_ARGS=()
  [ "$DRY_RUN" = true ] && CLAUDE_ARGS+=("--dry-run")
  run_step "Step 05: Claude Code CLI" "$SCRIPT_DIR/05_claude_code.sh" "${CLAUDE_ARGS[@]}"
else
  echo "  (skipping Claude Code CLI)"
fi

# ── Step 06: Validate ──
VALIDATE_ARGS=()
[ "$DRY_RUN" = true ] && VALIDATE_ARGS+=("--dry-run")
[ "$INSTALL_OPENCODE" = false ] && VALIDATE_ARGS+=("--skip-opencode")
[ "$INSTALL_CODEX" = false ] && VALIDATE_ARGS+=("--skip-codex")
[ "$INSTALL_CLAUDE_CODE" = false ] && VALIDATE_ARGS+=("--skip-claude-code")
run_step "Step 06: Validate" "$SCRIPT_DIR/06_validate.sh" "${VALIDATE_ARGS[@]}"
VALIDATE_RC=$?

# ── Summary ──
echo ""
echo "══════════════════════════════════════════════════════"
echo "  Bootstrap complete"
echo "══════════════════════════════════════════════════════"
echo ""
echo "Project dir:       $PROJECT_DIR"
echo "LiteLLM proxy:     $LITELLM_URL"
echo "LiteLLM Admin UI:  ${LITELLM_URL}/ui"
echo "Grafana:           http://127.0.0.1:3000 (anonymous, no login)"
echo "Prometheus:        http://127.0.0.1:9090"

if [ "$INSTALL_OPENCODE" = true ] && [ -f "$HOME/.config/opencode/opencode.json" ]; then
  echo "opencode config:   ~/.config/opencode/opencode.json"
  FINAL_VK=$(strip_jsonc "$HOME/.config/opencode/opencode.json" 2>/dev/null \
    | jq -r '.provider.LiteLLM.options.apiKey // empty' 2>/dev/null || true)
  [ -n "$FINAL_VK" ] && echo "opencode key:      $(mask_key "$FINAL_VK")"
fi
if [ "$INSTALL_CODEX" = true ] && [ -f "$HOME/.codex/.env" ]; then
  echo "Codex CLI config:   ~/.codex/config.toml"
  CODEX_VK=$(grep -oP '^LITELLM_CODEX_API_KEY=\K.*' "$HOME/.codex/.env" 2>/dev/null || true)
  [ -n "$CODEX_VK" ] && echo "Codex CLI key:      $(mask_key "$CODEX_VK")"
fi
if [ "$INSTALL_CLAUDE_CODE" = true ] && [ -f "$HOME/.claude/settings.json" ]; then
  echo "Claude Code config: ~/.claude/settings.json"
  CLAUDE_VK=$(jq -r '.env.ANTHROPIC_API_KEY // empty' "$HOME/.claude/settings.json" 2>/dev/null || true)
  [ -n "$CLAUDE_VK" ] && echo "Claude Code key:    $(mask_key "$CLAUDE_VK")"
fi

echo ""
echo "Next steps:"
[ "$INSTALL_OPENCODE" = true ] && echo "  - opencode:  exit any running session, then run: opencode"
[ "$INSTALL_CODEX" = true ] && echo "  - Codex:     codex"
[ "$INSTALL_CLAUDE_CODE" = true ] && echo "  - Claude:    claude --bare"
echo ""
echo "⚠️  Security: API keys were shared via environment variables and command line."
echo "   Rotate your MaaS keys to prevent unauthorized use:"
echo "     1. Get new key(s) from https://console.huaweicloud.com/modelarts/"
echo "     2. Edit .env: replace HUAWEI_MAAS_API_KEY and HUAWEI_MAAS_API_KEY_1..N"
echo "     3. Regenerate config: ./scripts/02_litellm.sh"
echo "     4. Restart LiteLLM:  docker compose restart litellm"
echo "     5. Re-validate:      ./scripts/06_validate.sh"
echo ""
echo "Restart your shell (or open a new terminal) to clear exported environment"
echo "variables and apply all changes:"
echo "  exec \"\$SHELL\"    # or close and reopen your terminal"

exit "$VALIDATE_RC"
