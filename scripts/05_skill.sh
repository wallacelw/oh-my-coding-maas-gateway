#!/usr/bin/env bash
set -euo pipefail

# ─── 05_skill.sh — Companion skill (pipeline step 05, optional) ────────────────
#
# Order:         05 (after validation)
# Optional:      yes (prompts user; skips if --no-skill or non-interactive)
# Description:   Installs SKILL.md as a skill/command into each installed
#                coding agent tool (opencode, codex, claude, pi).
# Inputs:        --dry-run, --no-skill, --yes
# Outputs:       ~/.config/opencode/skills/<name>/SKILL.md
#                ~/.codex/skills/<name>/SKILL.md
#                ~/.pi/agent/skills/<name>/SKILL.md
#                ~/.claude/commands/<name>.md
# Standalone:    yes — ./scripts/05_skill.sh
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers/common.sh"
source "$SCRIPT_DIR/helpers/skills.sh"
LOG_TAG="skill"

# ── Parse args ──
DRY_RUN=false
NO_SKILL=false
ASSUME_YES=false
for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=true ;;
    --no-skill)  NO_SKILL=true ;;
    --yes)       ASSUME_YES=true ;;
    *) log_error "Unknown flag: $arg"; exit 1 ;;
  esac
done

log_step "Step 05 — Companion skill"
[ "$DRY_RUN" = true ] && log_warn "DRY RUN — no changes will be made"

# ── Skip if --no-skill ──
if [ "$NO_SKILL" = true ]; then
  log_info "Skipping companion skill (--no-skill)"
  exit 0
fi

# ── Detect which tools are installed ──
INSTALLED_TOOLS=""
if command -v opencode &>/dev/null; then
  INSTALLED_TOOLS+="opencode "
fi
if command -v codex &>/dev/null; then
  INSTALLED_TOOLS+="codex "
fi
if command -v claude &>/dev/null; then
  INSTALLED_TOOLS+="claude "
fi
if command -v pi &>/dev/null; then
  INSTALLED_TOOLS+="pi "
fi

if [ -z "$INSTALLED_TOOLS" ]; then
  log_info "No coding agents detected — skipping companion skill"
  exit 0
fi

log_info "Detected coding agents: $(echo "$INSTALLED_TOOLS" | tr ' ' ',' | sed 's/,$//')"

# ── Check which tools already have the skill ──
EXISTING=""
NEW=""
for tool in $INSTALLED_TOOLS; do
  if "skill_exists_$tool" 2>/dev/null; then
    EXISTING+="$tool "
  else
    NEW+="$tool "
  fi
done

if [ -n "$EXISTING" ]; then
  log_dim "Already installed: $(echo "$EXISTING" | tr ' ' ',' | sed 's/,$//')"
fi

if [ -z "$NEW" ]; then
  log_ok "Companion skill already installed in all detected agents"
  exit 0
fi

# ── Prompt user ──
if [ "$ASSUME_YES" = false ] && is_interactive; then
  echo ""
  log_info "The companion skill provides operational guidance to your coding agents:"
  log_dim "  • Health diagnosis & recovery commands"
  log_dim "  • Key management (rotate, load-balance, mint virtual keys)"
  log_dim "  • Model management (add/remove via models.sh)"
  log_dim "  • Debug routing (401s, latency, smoke tests)"
  log_dim "  • Observability (Grafana + Prometheus queries)"
  echo ""
  log_info "Would install into: $(echo "$NEW" | tr ' ' ',' | sed 's/,$//')"
  echo ""

  if ! prompt_yesno "Install companion skill into these agents?" y; then
    log_info "Skipping companion skill installation"
    exit 0
  fi
fi

# ── Install ──
if [ "$DRY_RUN" = true ]; then
  for tool in $NEW; do
    case "$tool" in
      opencode) log_dim "  Would install: ~/.config/opencode/skills/$SKILL_NAME/SKILL.md" ;;
      codex)    log_dim "  Would install: ~/.codex/skills/$SKILL_NAME/SKILL.md" ;;
      pi)       log_dim "  Would install: ~/.pi/agent/skills/$SKILL_NAME/SKILL.md" ;;
      claude)   log_dim "  Would install: ~/.claude/commands/$CLAUDE_CMD_NAME.md" ;;
    esac
  done
  exit 0
fi

for tool in $NEW; do
  case "$tool" in
    opencode)
      dest=$(skill_install_opencode)
      log_ok "opencode: $dest"
      ;;
    codex)
      dest=$(skill_install_codex)
      log_ok "codex: $dest"
      ;;
    pi)
      dest=$(skill_install_pi)
      log_ok "pi: $dest"
      ;;
    claude)
      dest=$(skill_install_claude)
      log_ok "claude: $dest (slash command: /$CLAUDE_CMD_NAME)"
      ;;
  esac
done

echo ""
log_done "Companion skill installed — agents can now help operate the gateway"
