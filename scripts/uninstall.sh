#!/usr/bin/env bash
# uninstall.sh — Remove oh-my-coding-maas-gateway artifacts
#
# Usage:
#   ./scripts/uninstall.sh                      # interactive menu
#   ./scripts/uninstall.sh --tool=opencode      # remove one agent
#   ./scripts/uninstall.sh --tool=opencode,codex  # remove subset
#   ./scripts/uninstall.sh --tool=all           # remove all agent configs
#   ./scripts/uninstall.sh --docker             # remove Docker stack
#   ./scripts/uninstall.sh --repo               # remove repo (incl. .env, configs)
#   ./scripts/uninstall.sh --all                # everything
#   ./scripts/uninstall.sh --dry-run            # show what would be removed
#   ./scripts/uninstall.sh --yes                # skip confirmation
#
# Order: agents → Docker → repo (repo last, can't continue after self-delete).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers/common.sh"
source "$SCRIPT_DIR/helpers/skills.sh"
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
    echo -e "  ${C_BOLD}5${C_RESET}  All coding agents (binaries + configs)"
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
  local dir base count
  dir=$(dirname "$pattern")
  base=$(basename "$pattern")
  count=$(find "$dir" -maxdepth 1 -name "$base" 2>/dev/null | wc -l || true)
  if [ "$count" -gt 0 ]; then
    if [ "$DRY_RUN" = true ]; then
      find "$dir" -maxdepth 1 -name "$base" 2>/dev/null | while IFS= read -r f; do
        log_dim "  Would remove: $f"
      done
    else
      find "$dir" -maxdepth 1 -name "$base" -exec rm -rf {} + 2>/dev/null || true
      log_ok "Removed $count $label backup(s)"
    fi
  fi
}

# Remove lines from ~/.bashrc matching a pattern (or between marker pairs)
remove_bashrc_block() {
  local start_marker="$1" end_marker="${2:-}"
  local bashrc="$HOME/.bashrc"
  [ ! -f "$bashrc" ] && return 0
  if [ "$DRY_RUN" = true ]; then
    log_dim "  Would clean .bashrc: $start_marker"
    return 0
  fi
  local tmp
  tmp=$(mktemp)
  if [ -n "$end_marker" ]; then
    # Remove block between markers (inclusive)
    awk -v s="$start_marker" -v e="$end_marker" '
      $0 ~ s { skip=1; next }
      $0 ~ e { skip=0; next }
      !skip { print }
    ' "$bashrc" > "$tmp"
  else
    # Remove lines matching the pattern
    grep -v "$start_marker" "$bashrc" > "$tmp" || true
  fi
  { cat "$tmp" > "$bashrc" && rm "$tmp"; } || { rm -f "$tmp"; log_warn "Failed to update .bashrc"; }
}

# Remove a commented section from .bashrc (comment line + following lines until blank line)
remove_bashrc_section() {
  local comment_marker="$1"
  local bashrc="$HOME/.bashrc"
  [ ! -f "$bashrc" ] && return 0
  if [ "$DRY_RUN" = true ]; then
    log_dim "  Would clean .bashrc section: $comment_marker"
    return 0
  fi
  local tmp
  tmp=$(mktemp)
  awk -v m="$comment_marker" '
    $0 ~ m { skip=1; next }
    skip && /^$/ { skip=0; next }
    skip { next }
    { print }
  ' "$bashrc" > "$tmp"
  { cat "$tmp" > "$bashrc" && rm "$tmp"; } || { rm -f "$tmp"; log_warn "Failed to update .bashrc"; }
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
[ "$REMOVE_OPENCODE" = true ] && add_summary "opencode"
[ "$REMOVE_CODEX" = true ]    && add_summary "codex"
[ "$REMOVE_CLAUDE" = true ]   && add_summary "claude"
[ "$REMOVE_PI" = true ]       && add_summary "pi"
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
  log_step "Removing opencode"
  remove_path "$HOME/.config/opencode/opencode.json" "config"
  remove_path "$HOME/.config/opencode/oh-my-opencode-slim.json" "slim plugin config"
  remove_glob "$HOME/.config/opencode/opencode.json.bak.*" "config backup"
  remove_glob "$HOME/.config/opencode/oh-my-opencode-slim.json.bak.*" "slim config backup"
  if [ "$DRY_RUN" = true ]; then
    log_dim "  Would remove: $HOME/.opencode/ (binary)"
    log_dim "  Would remove: $HOME/.bun/ (runtime)"
  else
    [ -d "$HOME/.opencode" ] && rm -rf "$HOME/.opencode" && log_ok "Removed binary: $HOME/.opencode/"
    if [ -d "$HOME/.bun" ]; then
      if is_interactive && prompt_yesno "Remove bun runtime? (may break other bun projects)" n; then
        rm -rf "$HOME/.bun" && log_ok "Removed runtime: $HOME/.bun/"
      else
        log_dim "Keeping bun runtime: $HOME/.bun/ (may be used by other projects)"
      fi
    fi
    # Clean .bashrc entries
    remove_bashrc_section "^# bun$"
    remove_bashrc_section "^# opencode$"
    remove_bashrc_block "^# >>> oh-my-opencode-slim" "^# <<< oh-my-opencode-slim"
    [ -f "$HOME/.bashrc" ] && log_ok "Cleaned .bashrc entries"
  fi
fi

# ── Remove codex ──
if [ "$REMOVE_CODEX" = true ]; then
  log_step "Removing Codex CLI"
  remove_path "$HOME/.codex/config.toml" "config"
  remove_path "$HOME/.codex/model_catalog.json" "model catalog"
  remove_path "$HOME/.codex/.env" "env file"
  remove_glob "$HOME/.codex/config.toml.bak.*" "config backup"
  if [ "$DRY_RUN" = true ]; then
    log_dim "  Would run: npm uninstall -g @openai/codex"
  else
    # npm uninstall (may fail if registry out of sync — don't let set -e exit)
    set +e
    if command -v npm &>/dev/null; then
      npm uninstall -g @openai/codex 2>&1 | while IFS= read -r line; do log_dim "  $line"; done
    fi
    set -e
    # Force-remove binary and node_modules regardless of npm result
    rm -f /usr/local/bin/codex /usr/bin/codex /bin/codex 2>/dev/null || true
    rm -rf /usr/local/lib/node_modules/@openai/codex 2>/dev/null || true
    rm -rf /usr/lib/node_modules/@openai/codex 2>/dev/null || true
    hash -r 2>/dev/null || true
    if command -v codex &>/dev/null; then
      log_warn "codex binary still present at $(command -v codex)"
    else
      log_ok "Removed codex binary"
    fi
  fi
fi

# ── Remove claude ──
if [ "$REMOVE_CLAUDE" = true ]; then
  log_step "Removing Claude Code CLI"
  remove_path "$HOME/.claude/settings.json" "settings"
  remove_path "$HOME/.claude.json" "global config"
  remove_glob "$HOME/.claude/settings.json.bak.*" "settings backup"
  if [ "$DRY_RUN" = true ]; then
    log_dim "  Would run: npm uninstall -g @anthropic-ai/claude-code"
  else
    set +e
    if command -v npm &>/dev/null; then
      npm uninstall -g @anthropic-ai/claude-code 2>&1 | while IFS= read -r line; do log_dim "  $line"; done
    fi
    set -e
    rm -f /usr/local/bin/claude /usr/bin/claude /bin/claude 2>/dev/null || true
    rm -rf /usr/local/lib/node_modules/@anthropic-ai/claude-code 2>/dev/null || true
    rm -rf /usr/lib/node_modules/@anthropic-ai/claude-code 2>/dev/null || true
    hash -r 2>/dev/null || true
    if command -v claude &>/dev/null; then
      log_warn "claude binary still present at $(command -v claude)"
    else
      log_ok "Removed claude binary"
    fi
  fi
fi

# ── Remove pi ──
if [ "$REMOVE_PI" = true ]; then
  log_step "Removing Pi agent"
  remove_path "$HOME/.pi/agent/models.json" "config"
  remove_glob "$HOME/.pi/agent/models.json.bak.*" "config backup"
  if [ "$DRY_RUN" = true ]; then
    log_dim "  Would run: npm uninstall -g @earendil-works/pi-coding-agent"
  else
    set +e
    if command -v npm &>/dev/null; then
      npm uninstall -g @earendil-works/pi-coding-agent 2>&1 | while IFS= read -r line; do log_dim "  $line"; done
    fi
    set -e
    rm -f /usr/local/bin/pi /usr/bin/pi /bin/pi 2>/dev/null || true
    rm -rf /usr/local/lib/node_modules/@earendil-works/pi-coding-agent 2>/dev/null || true
    rm -rf /usr/lib/node_modules/@earendil-works/pi-coding-agent 2>/dev/null || true
    hash -r 2>/dev/null || true
    if command -v pi &>/dev/null; then
      log_warn "pi binary still present at $(command -v pi)"
    else
      log_ok "Removed pi binary"
    fi
  fi
  # Also remove pi-managed Node.js if present
  if [ "$DRY_RUN" != true ] && [ -d "$HOME/.local/share/pi-node" ]; then
    rm -rf "$HOME/.local/share/pi-node"
    log_ok "Removed pi-managed Node.js: $HOME/.local/share/pi-node/"
    # Clean .bashrc entries for pi-node
    remove_bashrc_block "pi-node"
  fi
fi

# ── Remove companion skill from uninstalled agents only ──
# Scope: only the agents being removed. Don't strip the skill from
# agents that stay installed — they still need it.
_skill_removed=false
REMOVE_TOOLS=""
[ "$REMOVE_OPENCODE" = true ] && REMOVE_TOOLS="$REMOVE_TOOLS opencode"
[ "$REMOVE_CODEX" = true ]    && REMOVE_TOOLS="$REMOVE_TOOLS codex"
[ "$REMOVE_CLAUDE" = true ]   && REMOVE_TOOLS="$REMOVE_TOOLS claude"
[ "$REMOVE_PI" = true ]       && REMOVE_TOOLS="$REMOVE_TOOLS pi"
for _tool in $REMOVE_TOOLS; do
  if "skill_exists_$_tool" 2>/dev/null; then
    if [ "$DRY_RUN" = true ]; then
      log_dim "  Would remove companion skill from $_tool"
    else
      "skill_uninstall_$_tool" 2>/dev/null || true
      log_ok "Removed companion skill from $_tool"
    fi
    _skill_removed=true
  fi
done
[ "$_skill_removed" = true ] && [ "$DRY_RUN" != true ] && log_dim "Companion skill removed from uninstalled agent(s)"

# ── Remove Docker stack ──
if [ "$REMOVE_DOCKER" = true ]; then
  log_step "Removing Docker stack"
  if command -v docker &>/dev/null; then
    if [ "$DRY_RUN" = true ]; then
      log_dim "  Would run: docker compose down -v --rmi all"
    else
      log_warn "Removing all containers, volumes (data, metrics, keys), and images — this is irreversible"
      compose_file="$PROJECT_DIR/docker-compose.yml"
      if [ -f "$compose_file" ]; then
        set +e
        docker compose -f "$compose_file" down -v --rmi all 2>&1 | while IFS= read -r line; do
          log_dim "  $line"
        done
        set -e
        log_ok "docker compose down completed"
      else
        log_warn "docker-compose.yml not found at $compose_file"
      fi
      # Fallback: stop/remove any lingering containers from this project
      # (covers cases where compose project name differs or compose file was missing)
      lingering=""
      lingering=$(docker ps -a --filter "name=litellm_" --format '{{.Names}}' 2>/dev/null || true)
      if [ -n "$lingering" ]; then
        log_warn "Found lingering containers: $lingering"
        echo "$lingering" | while IFS= read -r c; do
          docker rm -f "$c" 2>/dev/null || true
        done
        log_ok "Lingering containers removed"
      fi
      # Wait for ports to be freed (docker proxy can lag behind container removal)
      for port in 4000 5432 9090 3000; do
        for _ in $(seq 1 10); do
          if ! command -v ss >/dev/null 2>&1 || ! ss -tlnp 2>/dev/null | grep -qE ":${port}\b"; then
            break
          fi
          sleep 1
        done
      done
      log_ok "Docker stack removed"
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
