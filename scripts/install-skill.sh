#!/usr/bin/env bash
set -euo pipefail

# ─── install-skill.sh — Install a skill into all detected coding agents ───────
#
# Usage:
#   ./scripts/install-skill.sh --name=my-skill --source=./SKILL.md
#   ./scripts/install-skill.sh --name=my-skill --source=https://example.com/SKILL.md
#   ./scripts/install-skill.sh --name=my-skill --source=./SKILL.md --dry-run
#
# Installs a SKILL.md file (with frontmatter) into:
#   opencode: ~/.config/opencode/skills/<name>/SKILL.md
#   codex:    ~/.codex/skills/<name>/SKILL.md
#   pi:       ~/.pi/agent/skills/<name>/SKILL.md
#   claude:   ~/.claude/skills/<name>/SKILL.md
#
# Only installs into tools that are detected (binary on PATH).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers/common.sh"
LOG_TAG="skill-install"

# ── Parse args ──
SKILL_NAME=""
SKILL_SOURCE=""
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --name=*)    SKILL_NAME="${arg#--name=}" ;;
    --source=*)  SKILL_SOURCE="${arg#--source=}" ;;
    --dry-run)   DRY_RUN=true ;;
    *)
      echo "Usage: $0 --name=<name> --source=<path-or-url> [--dry-run]"
      exit 1
      ;;
  esac
done

if [ -z "$SKILL_NAME" ]; then
  log_error "Missing --name=<name>"
  exit 1
fi
if [ -z "$SKILL_SOURCE" ]; then
  log_error "Missing --source=<path-or-url>"
  exit 1
fi

log_step "Install skill: $SKILL_NAME"
[ "$DRY_RUN" = true ] && log_warn "DRY RUN — no changes will be made"

# ── Resolve source file ──
TMPFILE=""
cleanup() { [ -n "$TMPFILE" ] && rm -f "$TMPFILE" 2>/dev/null || true; }
trap cleanup EXIT

if [[ "$SKILL_SOURCE" == http* ]]; then
  log_info "Downloading from $SKILL_SOURCE..."
  TMPFILE=$(mktemp)
  if ! curl -fsSL --max-time 30 "$SKILL_SOURCE" -o "$TMPFILE"; then
    log_error "Failed to download from $SKILL_SOURCE"
    exit 1
  fi
  SRC_FILE="$TMPFILE"
else
  if [ ! -f "$SKILL_SOURCE" ]; then
    log_error "File not found: $SKILL_SOURCE"
    exit 1
  fi
  SRC_FILE="$SKILL_SOURCE"
fi

log_ok "Source: $SRC_FILE"

# ── Detect installed agents ──
INSTALLED_TOOLS=""
command -v opencode &>/dev/null && INSTALLED_TOOLS+="opencode "
command -v codex &>/dev/null    && INSTALLED_TOOLS+="codex "
command -v claude &>/dev/null   && INSTALLED_TOOLS+="claude "
command -v pi &>/dev/null       && INSTALLED_TOOLS+="pi "

if [ -z "$INSTALLED_TOOLS" ]; then
  log_error "No coding agents detected (opencode, codex, claude, pi)"
  exit 1
fi

log_info "Detected agents: $(echo "$INSTALLED_TOOLS" | tr ' ' ',' | sed 's/,$//')"

# ── Install into each ──
COUNT=0
for tool in $INSTALLED_TOOLS; do
  case "$tool" in
    opencode) dest_dir="$HOME/.config/opencode/skills/$SKILL_NAME" ;;
    codex)    dest_dir="$HOME/.codex/skills/$SKILL_NAME" ;;
    pi)       dest_dir="$HOME/.pi/agent/skills/$SKILL_NAME" ;;
    claude)   dest_dir="$HOME/.claude/skills/$SKILL_NAME" ;;
  esac

  if [ "$DRY_RUN" = true ]; then
    log_dim "  Would install: $dest_dir/SKILL.md"
  else
    mkdir -p "$dest_dir"
    cp "$SRC_FILE" "$dest_dir/SKILL.md"
    log_ok "$tool: $dest_dir/SKILL.md"
    COUNT=$((COUNT + 1))
  fi
done

echo ""
if [ "$DRY_RUN" = true ]; then
  log_info "Dry-run complete. Re-run without --dry-run to install."
else
  log_done "Skill '$SKILL_NAME' installed into $COUNT agent(s)"
fi
