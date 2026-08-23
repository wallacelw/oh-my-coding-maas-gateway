#!/usr/bin/env bash
set -euo pipefail

# ════════════════════════════════════════════════════════════════════════════
# scripts/update.sh — Check and update installed components
# ════════════════════════════════════════════════════════════════════════════
#
# Usage:
#   ./scripts/update.sh              # interactive: show table, ask which to update
#   ./scripts/update.sh --all        # update all components with updates available
#   ./scripts/update.sh --check      # just check versions, don't update
#   ./scripts/update.sh --dry-run    # show what would be updated (no changes)
#
# Detects installed components, checks current vs latest versions, and
# offers selective updates. Does NOT touch passwords, API keys, or
# virtual keys — only updates binaries, npm packages, and Docker images.
#
# Standalone: yes — ./scripts/update.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/helpers/common.sh"

LOG_TAG="update"

# ── Flags ──
CHECK_ONLY=false
UPDATE_ALL=false
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --check)      CHECK_ONLY=true ;;
    --all)        UPDATE_ALL=true ;;
    --dry-run)    DRY_RUN=true ;;
    --help|-h)
      echo "Usage: ./scripts/update.sh [--check|--all|--dry-run]"
      echo ""
      echo "  (no flags)  Interactive: show versions, ask which to update"
      echo "  --check     Show version table only, don't update"
      echo "  --all       Update all components with updates available"
      echo "  --dry-run   Show what would be updated, make no changes"
      exit 0
      ;;
    *) log_error "Unknown flag: $arg"; exit 1 ;;
  esac
done

# ── Component arrays ──
# Each component: name | current_ver | latest_ver | update_method | category
# update_method: npm:<pkg> | curl:<url> | docker:<service>:<image>:<tag_prefix> | slim
# category: "tool" (coding tools) | "infra" (LiteLLM + observability)
COMPONENTS=()
CUR_VERSIONS=()
NEW_VERSIONS=()
UPDATE_METHODS=()
UPDATE_AVAILABLE=()
CATEGORIES=()

# ── Version check helpers ──

# Get latest version from GitHub releases API
github_latest() {
  local repo="$1"
  curl -sLf -m 10 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null \
    | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null
}

# Get latest version from npm
npm_latest() {
  local pkg="$1"
  timeout 15 npm view "$pkg" version 2>/dev/null
}

# Strip leading 'v' from version strings
strip_v() {
  echo "$1" | sed 's/^v//; s/^rust-v//'
}

# Compare versions: returns 0 if different (update available), 1 if same
version_differs() {
  local cur="$1" new="$2"
  [ -n "$cur" ] && [ -n "$new" ] && [ "$cur" != "$new" ]
}

# ── Check each component ──
check_components() {
  local name cur new method

  # ── Coding Tools ──

  # 1. opencode
  name="opencode"
  cur=$(opencode --version 2>/dev/null || echo "")
  new=$(strip_v "$(github_latest sst/opencode)")
  method="curl:https://opencode.ai/install"
  _store_component "$name" "$cur" "$new" "$method" "tool"

  # 2. oh-my-opencode-slim
  name="oh-my-opencode-slim"
  cur=$(grep 'SLIM_VERSION=' "$SCRIPT_DIR/03a_opencode.sh" 2>/dev/null | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
  new=$(npm_latest oh-my-opencode-slim)
  method="slim"
  _store_component "$name" "$cur" "$new" "$method" "tool"

  # 3. Codex CLI
  name="codex"
  cur=$(codex --version 2>/dev/null | sed 's/codex-cli //' || echo "")
  new=$(npm_latest @openai/codex)
  method="npm:@openai/codex"
  _store_component "$name" "$cur" "$new" "$method" "tool"

  # 4. Claude Code
  name="claude-code"
  cur=$(claude --version 2>/dev/null | sed 's/ (Claude Code)//' || echo "")
  new=$(npm_latest @anthropic-ai/claude-code)
  method="npm:@anthropic-ai/claude-code"
  _store_component "$name" "$cur" "$new" "$method" "tool"

  # 5. Pi agent
  name="pi"
  cur=$(pi --version 2>/dev/null || echo "")
  new=$(npm_latest @earendil-works/pi-coding-agent)
  method="npm:@earendil-works/pi-coding-agent"
  _store_component "$name" "$cur" "$new" "$method" "tool"

  # ── Infrastructure (LiteLLM + Observability) ──

  # 6. LiteLLM (Docker)
  name="litellm"
  cur=$(grep 'image:.*litellm:' docker-compose.yml 2>/dev/null | sed 's/.*:v//' | tr -d ' ')
  new=$(strip_v "$(github_latest BerriAI/litellm)")
  method="docker:litellm:ghcr.io/berriai/litellm:v"
  _store_component "$name" "$cur" "$new" "$method" "infra"

  # 7. Prometheus (Docker)
  name="prometheus"
  cur=$(grep 'image:.*prom/prometheus:' docker-compose.yml 2>/dev/null | sed 's/.*:v//' | tr -d ' ')
  new=$(strip_v "$(github_latest prometheus/prometheus)")
  method="docker:prometheus:prom/prometheus:v"
  _store_component "$name" "$cur" "$new" "$method" "infra"

  # 8. Grafana (Docker)
  name="grafana"
  cur=$(grep 'image:.*grafana/grafana:' docker-compose.yml 2>/dev/null | sed 's/.*grafana://' | tr -d ' ')
  new=$(strip_v "$(github_latest grafana/grafana)")
  method="docker:grafana:grafana/grafana:"
  _store_component "$name" "$cur" "$new" "$method" "infra"
}

# Store component info in arrays
_store_component() {
  local name="$1" cur="$2" new="$3" method="$4" cat="$5"
  COMPONENTS+=("$name")
  CUR_VERSIONS+=("$cur")
  NEW_VERSIONS+=("$new")
  UPDATE_METHODS+=("$method")
  CATEGORIES+=("$cat")
  if version_differs "$cur" "$new"; then
    UPDATE_AVAILABLE+=("yes")
  else
    UPDATE_AVAILABLE+=("no")
  fi
}

# ── Print a single component row ──
_print_row() {
  local i="$1"
  local name="${COMPONENTS[$i]}"
  local cur="${CUR_VERSIONS[$i]}"
  local new="${NEW_VERSIONS[$i]}"
  local avail="${UPDATE_AVAILABLE[$i]}"

  [ -z "$cur" ] && cur="${C_DIM}(not installed)${C_RESET}"
  [ -z "$new" ] && new="${C_DIM}(unknown)${C_RESET}"

  local status
  if [ "$avail" = "yes" ]; then
    status="${C_YELLOW}update available${C_RESET}"
  elif [ -z "${CUR_VERSIONS[$i]}" ]; then
    status="${C_DIM}—${C_RESET}"
  elif [ -z "${NEW_VERSIONS[$i]}" ]; then
    status="${C_DIM}unknown${C_RESET}"
  else
    status="${C_GREEN}up to date${C_RESET}"
  fi

  printf "  %-22s %-12s %-12s %b\n" "$name" "$cur" "$new" "$status"
}

# ── Display version table (grouped) ──
show_table() {
  local count=${#COMPONENTS[@]}
  local updates_found=0

  for ((i = 0; i < count; i++)); do
    [ "${UPDATE_AVAILABLE[$i]}" = "yes" ] && updates_found=$((updates_found + 1))
  done

  echo ""
  echo -e "  ${C_BOLD}Coding Tools${C_RESET}"
  printf "  ${C_DIM}%-22s %-12s %-12s %s${C_RESET}\n" "Component" "Current" "Latest" "Status"
  printf "  ${C_DIM}%-22s %-12s %-12s %s${C_RESET}\n" "──────────" "───────" "──────" "──────"
  for ((i = 0; i < count; i++)); do
    [ "${CATEGORIES[$i]}" = "tool" ] && _print_row "$i"
  done

  echo ""
  echo -e "  ${C_BOLD}Infrastructure (LiteLLM + Observability)${C_RESET}"
  printf "  ${C_DIM}%-22s %-12s %-12s %s${C_RESET}\n" "Component" "Current" "Latest" "Status"
  printf "  ${C_DIM}%-22s %-12s %-12s %s${C_RESET}\n" "──────────" "───────" "──────" "──────"
  for ((i = 0; i < count; i++)); do
    [ "${CATEGORIES[$i]}" = "infra" ] && _print_row "$i"
  done

  echo ""
  if [ $updates_found -gt 0 ]; then
    log_info "$updates_found component(s) with updates available"
  else
    log_ok "All components up to date"
  fi

  UPDATES_FOUND=$updates_found
}

# ── Interactive component selection (grouped) ──
select_components() {
  local count=${#COMPONENTS[@]}
  local updatable=()
  local idx=1

  # Build list of updatable components
  for ((i = 0; i < count; i++)); do
    if [ "${UPDATE_AVAILABLE[$i]}" = "yes" ]; then
      updatable+=("$i")
    fi
  done

  if [ ${#updatable[@]} -eq 0 ]; then
    return 0
  fi

  echo ""
  echo -e "  ${C_BOLD}Select components to update:${C_RESET}"

  # Coding Tools section
  local has_tools=false
  for u_idx in "${updatable[@]}"; do
    if [ "${CATEGORIES[$u_idx]}" = "tool" ]; then
      has_tools=true
      break
    fi
  done
  if [ "$has_tools" = true ]; then
    echo ""
    echo -e "  ${C_DIM}Coding Tools:${C_RESET}"
    for u_idx in "${updatable[@]}"; do
      if [ "${CATEGORIES[$u_idx]}" = "tool" ]; then
        local name="${COMPONENTS[$u_idx]}"
        local cur="${CUR_VERSIONS[$u_idx]}"
        local new="${NEW_VERSIONS[$u_idx]}"
        printf "    ${C_BOLD}%d)${C_RESET} %-20s ${C_DIM}%s → %s${C_RESET}\n" "$idx" "$name" "$cur" "$new"
        idx=$((idx + 1))
      fi
    done
  fi

  # Infrastructure section
  local has_infra=false
  for u_idx in "${updatable[@]}"; do
    if [ "${CATEGORIES[$u_idx]}" = "infra" ]; then
      has_infra=true
      break
    fi
  done
  if [ "$has_infra" = true ]; then
    echo ""
    echo -e "  ${C_DIM}Infrastructure:${C_RESET}"
    for u_idx in "${updatable[@]}"; do
      if [ "${CATEGORIES[$u_idx]}" = "infra" ]; then
        local name="${COMPONENTS[$u_idx]}"
        local cur="${CUR_VERSIONS[$u_idx]}"
        local new="${NEW_VERSIONS[$u_idx]}"
        printf "    ${C_BOLD}%d)${C_RESET} %-20s ${C_DIM}%s → %s${C_RESET}\n" "$idx" "$name" "$cur" "$new"
        idx=$((idx + 1))
      fi
    done
  fi

  echo ""
  echo -e "  ${C_DIM}Enter numbers (e.g. 1,3,5), 'all', or Enter to skip:${C_RESET}"
  echo -ne "  ${C_BOLD}Choice${C_RESET}: "
  local choice
  read -r choice < /dev/tty || choice=""

  SELECTED=()
  if [ -z "$choice" ] || [ "$choice" = "skip" ]; then
    return 0
  fi

  if [ "$choice" = "all" ]; then
    SELECTED=("${updatable[@]}")
    return 0
  fi

  # Parse comma-separated numbers
  IFS=',' read -ra nums <<< "$choice"
  for num in "${nums[@]}"; do
    if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#updatable[@]}" ]; then
      local array_idx=$((num - 1))
      SELECTED+=("${updatable[$array_idx]}")
    fi
  done
}

# ── Update a single component ──
update_component() {
  local idx="$1"
  local name="${COMPONENTS[$idx]}"
  local method="${UPDATE_METHODS[$idx]}"
  local new_ver="${NEW_VERSIONS[$idx]}"
  local cur_ver="${CUR_VERSIONS[$idx]}"

  echo ""
  log_info "Updating $name: $cur_ver → $new_ver"

  if [ "$DRY_RUN" = true ]; then
    log_dim "Would update $name using: $method"
    return 0
  fi

  case "$method" in
    npm:*)
      local pkg="${method#npm:}"
      run_filtered "npm" npm install -g "$pkg@latest" || { log_error "$name update failed"; return 1; }
      log_ok "$name updated to $(npm_latest "$pkg")"
      ;;

    curl:*)
      local url="${method#curl:}"
      local tmpfile
      tmpfile=$(mktemp /tmp/update_XXXXXX.sh)
      trap 'rm -f "$tmpfile"' RETURN
      if curl -fsSL --max-time 60 "$url" -o "$tmpfile"; then
        run_filtered "$name" bash "$tmpfile" || { log_error "$name update failed"; return 1; }
        hash -r 2>/dev/null || true
        log_ok "$name updated"
      else
        log_error "Failed to download $name update"
        return 1
      fi
      rm -f "$tmpfile"
      ;;

    slim)
      # Update slim plugin
      run_filtered "slim" bunx "oh-my-opencode-slim@latest" install --companion=no \
        || { log_error "oh-my-opencode-slim update failed"; return 1; }
      # Update SLIM_VERSION in 03a_opencode.sh (repo file mutation)
      if [ -z "$new_ver" ]; then
        log_error "Cannot update oh-my-opencode-slim: latest version unknown"
        return 1
      fi
      log_info "Updating SLIM_VERSION in scripts/03a_opencode.sh (repo file will be modified)"
      cp "$SCRIPT_DIR/03a_opencode.sh" "$SCRIPT_DIR/03a_opencode.sh.bak.$(date +%Y%m%d%H%M%S)"
      sed -i "s/SLIM_VERSION=\"[^\"]*\"/SLIM_VERSION=\"$new_ver\"/" "$SCRIPT_DIR/03a_opencode.sh"
      log_ok "oh-my-opencode-slim updated to $new_ver"
      ;;

    docker:*)
      # Parse: docker:<service>:<image_prefix>:<tag_prefix>
      local rest="${method#docker:}"
      local service="${rest%%:*}"
      rest="${rest#*:}"
      local image_prefix="${rest%%:*}"
      local tag_prefix="${rest#*:}"

      # Update image tag in docker-compose.yml (repo file mutation)
      log_info "Updating image tag in docker-compose.yml (repo file will be modified)"
      cp docker-compose.yml "docker-compose.yml.bak.$(date +%Y%m%d%H%M%S)"
      sed -i "s|image: ${image_prefix}:${tag_prefix}.*|image: ${image_prefix}:${tag_prefix}${new_ver}|" docker-compose.yml

      # Pull and restart
      run_filtered "docker" docker compose pull "$service" || { log_error "$name pull failed"; return 1; }
      run_filtered "docker" docker compose up -d "$service" || { log_error "$name restart failed"; return 1; }
      log_ok "$name updated to $new_ver"
      ;;
  esac
}

# ── Main ──
log_step "Component Update Check"

echo ""
echo -e "  ${C_DIM}Checks current vs latest versions for all installed components.${C_RESET}"
echo -e "  ${C_DIM}Updates binaries, npm packages, and Docker images only —${C_RESET}"
echo -e "  ${C_DIM}passwords, API keys, and virtual keys are never touched.${C_RESET}"

# Verify we're in the project directory
if [ ! -f "$PROJECT_DIR/docker-compose.yml" ]; then
  log_error "docker-compose.yml not found. Run from the project directory."
  exit 1
fi

echo ""
log_info "Checking versions..."
check_components

# Show the version table
show_table
updates_found=${UPDATES_FOUND:-0}

if [ $updates_found -eq 0 ]; then
  exit 0
fi

if [ "$CHECK_ONLY" = true ]; then
  exit 0
fi

# Determine which components to update
SELECTED=()

if [ "$UPDATE_ALL" = true ]; then
  # Select all updatable components
  for ((i = 0; i < ${#COMPONENTS[@]}; i++)); do
    if [ "${UPDATE_AVAILABLE[$i]}" = "yes" ]; then
      SELECTED+=("$i")
    fi
  done
elif is_interactive; then
  select_components
else
  # Non-interactive without --all: skip
  log_dim "Non-interactive mode — use --all to update"
  exit 0
fi

if [ ${#SELECTED[@]} -eq 0 ]; then
  log_info "No components selected"
  exit 0
fi

# Confirm
if is_interactive && [ "$DRY_RUN" = false ]; then
  echo ""
  echo -e "  ${C_BOLD}Will update:${C_RESET}"
  for idx in "${SELECTED[@]}"; do
    _name="${COMPONENTS[$idx]}"
    _cur="${CUR_VERSIONS[$idx]}"
    _new="${NEW_VERSIONS[$idx]}"
    echo -e "    ${C_DIM}$_name: $_cur → $_new${C_RESET}"
  done
  echo ""
  if ! prompt_yesno "Proceed with updates?" y; then
    log_info "Update cancelled"
    exit 0
  fi
fi

# Execute updates
echo ""
log_info "Updating ${#SELECTED[@]} component(s)..."

FAILED=0
for idx in "${SELECTED[@]}"; do
  update_component "$idx" || FAILED=$((FAILED + 1))
done

# Summary
echo ""
if [ $FAILED -gt 0 ]; then
  log_warn "Update complete with $FAILED failure(s)"
else
  log_ok "All updates complete"
fi

# Re-check versions
if [ "$DRY_RUN" = false ]; then
  echo ""
  log_info "Re-checking versions..."
  COMPONENTS=()
  CUR_VERSIONS=()
  NEW_VERSIONS=()
  UPDATE_METHODS=()
  UPDATE_AVAILABLE=()
  CATEGORIES=()
  check_components
  show_table
fi

# Offer to run validation
if [ "$DRY_RUN" = false ] && [ ${#SELECTED[@]} -gt 0 ] && [ $FAILED -eq 0 ]; then
  echo ""
  if prompt_yesno "Run validation?" y; then
    "$SCRIPT_DIR/04_validate.sh"
  fi
fi
