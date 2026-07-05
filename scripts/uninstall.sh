#!/usr/bin/env bash
# uninstall.sh — Remove oh-my-coding-maas-gateway artifacts
#
# Callable from any directory (resolves paths via BASH_SOURCE).
# Usage:
#   /path/to/scripts/uninstall.sh              # interactive menu
#   /path/to/scripts/uninstall.sh --tool=opencode      # remove one agent
#   /path/to/scripts/uninstall.sh --tool=opencode,codex  # remove subset
#   /path/to/scripts/uninstall.sh --tool=all           # remove all agent configs
#   /path/to/scripts/uninstall.sh --docker             # remove Docker stack
#   /path/to/scripts/uninstall.sh --repo               # remove repo (incl. .env, configs)
#   /path/to/scripts/uninstall.sh --all                # everything
#   /path/to/scripts/uninstall.sh --dry-run            # show what would be removed
#   /path/to/scripts/uninstall.sh --yes                # skip confirmation
#
# Order: agents → Docker → repo (repo last, can't continue after self-delete).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers/common.sh"
LOG_TAG="uninstall"

# ── Defaults ──
REMOVE_OPENCODE=false
REMOVE_CODEX=false
REMOVE_CLAUDE=false
REMOVE_PI=false
REMOVE_DOCKER=false
REMOVE_REPO=false
DRY_RUN=false
SKIP_CONFIRM=false
TOOL_SPECIFIED=false

# ── Parse args ──
while [ $# -gt 0 ]; do
  case "$1" in
    --tool=*)
      TOOL_SPECIFIED=true
      val="${1#--tool=}"
      if [ "$val" = "all" ]; then
        REMOVE_OPENCODE=true; REMOVE_CODEX=true
        REMOVE_CLAUDE=true; REMOVE_PI=true
      else
        IFS=',' read -ra tools <<< "$val"
        for t in "${tools[@]}"; do
          case "$t" in
            opencode)  REMOVE_OPENCODE=true ;;
            codex)     REMOVE_CODEX=true ;;
            claude)    REMOVE_CLAUDE=true ;;
            pi)        REMOVE_PI=true ;;
            *) log_error "Unknown tool: $t"; exit 1 ;;
          esac
        done
      fi
      ;;
    --docker)    REMOVE_DOCKER=true ;;
    --repo)      REMOVE_REPO=true ;;
    --all)
      REMOVE_OPENCODE=true; REMOVE_CODEX=true
      REMOVE_CLAUDE=true; REMOVE_PI=true
      REMOVE_DOCKER=true; REMOVE_REPO=true
      ;;
    --dry-run)   DRY_RUN=true ;;
    --yes|-y)    SKIP_CONFIRM=true ;;
    --help|-h)
      sed -n '2,18p' "$0"
      exit 0
      ;;
    *) log_error "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

# ── Interactive menu (no flags) ──
if [ "$TOOL_SPECIFIED" = false ] \
   && [ "$REMOVE_DOCKER" = false ] \
   && [ "$REMOVE_REPO" = false ]; then
  if is_interactive; then
    echo ""
    log_step "Select what to uninstall"
    echo ""
    echo -e "  ${C_BOLD}1${C_RESET}  opencode"
    echo -e "  ${C_BOLD}2${C_RESET}  Codex CLI"
    echo -e "  ${C_BOLD}3${C_RESET}  Claude Code CLI"
    echo -e "  ${C_BOLD}4${C_RESET}  Pi agent"
    echo -e "  ${C_BOLD}5${C_RESET}  All coding agents (configs only)"
    echo -e "  ${C_BOLD}6${C_RESET}  Docker stack (containers + volumes + images)"
    echo -e "  ${C_BOLD}7${C_RESET}  Everything (agents + Docker + repo)"
    echo -e "  ${C_DIM}Or combine: 1,2,6 (opencode + codex + Docker)${C_RESET}"
    echo ""
    echo -n "  Choice: "
    read -r choice < /dev/tty || choice=""
    echo ""
    case "$choice" in
      1) REMOVE_OPENCODE=true ;;
      2) REMOVE_CODEX=true ;;
      3) REMOVE_CLAUDE=true ;;
      4) REMOVE_PI=true ;;
      5) REMOVE_OPENCODE=true; REMOVE_CODEX=true; REMOVE_CLAUDE=true; REMOVE_PI=true ;;
      6) REMOVE_DOCKER=true ;;
      7) REMOVE_OPENCODE=true; REMOVE_CODEX=true; REMOVE_CLAUDE=true; REMOVE_PI=true
         REMOVE_DOCKER=true; REMOVE_REPO=true ;;
      *)
        # Parse comma-separated numbers
        IFS=',' read -ra nums <<< "$choice"
        for n in "${nums[@]}"; do
          case "$n" in
            1) REMOVE_OPENCODE=true ;;
            2) REMOVE_CODEX=true ;;
            3) REMOVE_CLAUDE=true ;;
            4) REMOVE_PI=true ;;
            5) REMOVE_OPENCODE=true; REMOVE_CODEX=true; REMOVE_CLAUDE=true; REMOVE_PI=true ;;
            6) REMOVE_DOCKER=true ;;
            7) REMOVE_OPENCODE=true; REMOVE_CODEX=true; REMOVE_CLAUDE=true; REMOVE_PI=true
               REMOVE_DOCKER=true; REMOVE_REPO=true ;;
            *) log_warn "Ignoring invalid choice: $n" ;;
          esac
        done
        ;;
    esac
  else
    log_error "No flags given and not interactive. Use --tool=, --docker, --repo, or --all."
    exit 1
  fi
fi

# ── Check if anything selected ──
if [ "$REMOVE_OPENCODE" = false ] && [ "$REMOVE_CODEX" = false ] \
   && [ "$REMOVE_CLAUDE" = false ] && [ "$REMOVE_PI" = false ] \
   && [ "$REMOVE_DOCKER" = false ] && [ "$REMOVE_REPO" = false ]; then
  log_error "Nothing selected for uninstall."
  exit 1
fi

# ── Summary + confirmation ──
echo ""
log_step "Uninstall summary"
[ "$DRY_RUN" = true ] && log_dim "(dry-run — nothing will be deleted)"

remove_path() {
  local path="$1" label="$2"
  if [ -e "$path" ]; then
    if [ "$DRY_RUN" = true ]; then
      log_dim "  Would remove: $path"
    else
      rm -rf "$path"
      log_ok "Removed $label: $path"
    fi
  fi
}

remove_glob() {
  local pattern="$1" label="$2"
  local count
  count=$(ls -d $pattern 2>/dev/null | wc -l || true)
  if [ "$count" -gt 0 ]; then
    if [ "$DRY_RUN" = true ]; then
      for f in $pattern; do log_dim "  Would remove: $f"; done
    else
      rm -rf $pattern
      log_ok "Removed $count $label backup(s): $pattern"
    fi
  fi
}

# Build summary list
SUMMARY=""
add_summary() {
  if [ -n "$SUMMARY" ]; then
    SUMMARY="$SUMMARY, $1"
  else
    SUMMARY="$1"
  fi
}
[ "$REMOVE_OPENCODE" = true ] && add_summary "opencode config"
[ "$REMOVE_CODEX" = true ]    && add_summary "codex config"
[ "$REMOVE_CLAUDE" = true ]   && add_summary "claude config"
[ "$REMOVE_PI" = true ]       && add_summary "pi config"
[ "$REMOVE_DOCKER" = true ]   && add_summary "Docker stack"
[ "$REMOVE_REPO" = true ]     && add_summary "repository"

log_info "Will remove: $SUMMARY"

if [ "$SKIP_CONFIRM" = false ] && [ "$DRY_RUN" = false ]; then
  if is_interactive; then
    if ! prompt_yesno "Proceed with uninstall?" n; then
      log_info "Aborted."
      exit 0
    fi
  else
    log_error "Not interactive. Use --yes to skip confirmation."
    exit 1
  fi
fi

echo ""

# ── Remove opencode ──
if [ "$REMOVE_OPENCODE" = true ]; then
  log_step "Removing opencode configuration"
  remove_path "$HOME/.config/opencode/opencode.json" "opencode config"
  remove_path "$HOME/.config/opencode/oh-my-opencode-slim.json" "slim plugin config"
  remove_glob "$HOME/.config/opencode/opencode.json.bak.*" "opencode config"
  remove_glob "$HOME/.config/opencode/oh-my-opencode-slim.json.bak.*" "slim plugin config"
  log_dim "  opencode binary left in place (use your package manager to remove it)"
fi

# ── Remove codex ──
if [ "$REMOVE_CODEX" = true ]; then
  log_step "Removing Codex CLI configuration"
  remove_path "$HOME/.codex/config.toml" "codex config"
  remove_path "$HOME/.codex/model_catalog.json" "codex model catalog"
  remove_path "$HOME/.codex/.env" "codex env file"
  remove_glob "$HOME/.codex/config.toml.bak.*" "codex config"
  log_dim "  codex binary left in place (npm uninstall -g @openai/codex to remove)"
fi

# ── Remove claude ──
if [ "$REMOVE_CLAUDE" = true ]; then
  log_step "Removing Claude Code CLI configuration"
  remove_path "$HOME/.claude/settings.json" "claude settings"
  remove_path "$HOME/.claude.json" "claude global config"
  remove_glob "$HOME/.claude/settings.json.bak.*" "claude settings"
  log_dim "  claude binary left in place (npm uninstall -g @anthropic-ai/claude-code to remove)"
fi

# ── Remove pi ──
if [ "$REMOVE_PI" = true ]; then
  log_step "Removing Pi agent configuration"
  remove_path "$HOME/.pi/agent/models.json" "pi config"
  remove_glob "$HOME/.pi/agent/models.json.bak.*" "pi config"
  log_dim "  pi binary left in place (use pi.dev uninstall instructions to remove)"
fi

# ── Remove Docker stack ──
if [ "$REMOVE_DOCKER" = true ]; then
  log_step "Removing Docker stack"
  if command -v docker &>/dev/null; then
    if [ "$DRY_RUN" = true ]; then
      log_dim "  Would run: docker compose down -v --rmi all"
    else
      docker compose -f "$PROJECT_DIR/docker-compose.yml" down -v --rmi all 2>&1 \
        | run_filtered "docker" || true
      log_ok "Docker containers, volumes, and images removed"
    fi
  else
    log_warn "docker not found — skipping Docker cleanup"
  fi
fi

# ── Remove repository ──
if [ "$REMOVE_REPO" = true ]; then
  log_step "Removing repository"
  if [ "$DRY_RUN" = true ]; then
    log_dim "  Would remove: $PROJECT_DIR"
  else
    # Remove lock first (we hold the flock, but rm is fine)
    rm -f "$PROJECT_DIR/.bootstrap.lock" 2>/dev/null || true
    # Self-delete: can't rm the cwd, so cd home first
    cd "$HOME"
    rm -rf "$PROJECT_DIR"
    log_ok "Repository removed: $PROJECT_DIR"
  fi
fi

# ── Done ──
echo ""
if [ "$DRY_RUN" = true ]; then
  log_info "Dry-run complete. Re-run without --dry-run to actually remove."
else
  log_ok "Uninstall complete."
  if [ "$REMOVE_REPO" = true ]; then
    log_dim "Repository deleted. To reinstall:"
    log_dim "  curl -fsSL https://raw.githubusercontent.com/wallacelw/oh-my-coding-maas-gateway/main/scripts/bootstrap.sh | bash"
  else
    log_dim "To reinstall configs: re-run bootstrap.sh"
  fi
fi
