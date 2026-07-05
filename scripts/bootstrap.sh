#!/usr/bin/env bash
set -euo pipefail

# ─── bootstrap.sh — Install orchestrator (entry point) ────────────────────────
#
# Domain:        Orchestration
# Description:   Thin sequencer. Prompts for install location (default /home),
#                resolves the tool selection (interactive menu or --tool=),
#                ensures core prerequisites, runs the numbered pipeline steps
#                (01_env → 02_litellm → 03a/03b/03c/03d tools → 04_validate → 05_skill), and
#                prints a colored summary. This is the only script a human
#                needs to run. Each step is independently runnable too.
#
# Usage:
#   ./bootstrap.sh                          # interactive — prompts + tool menu
#   ./bootstrap.sh --tool=all               # install all (default)
#   ./bootstrap.sh --tool=litellm           # LiteLLM proxy only
#   ./bootstrap.sh --tool=opencode,codex    # custom combo
#   ./bootstrap.sh --virtual-key=sk-...     # reuse existing opencode virtual key
#   ./bootstrap.sh --dry-run                # preview without changes
#
# Non-interactive (CI / agent):
#   HUAWEI_MAAS_API_KEY=$KEY ./bootstrap.sh --tool=opencode
# ──────────────────────────────────────────────────────────────────────────────

REPO_URL="https://github.com/wallacelw/oh-my-coding-maas-gateway"
REPO_NAME="oh-my-coding-maas-gateway"

SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo ".")"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ── Parse args (early — needed before standalone check) ──
VIRTUAL_KEY=""
DRY_RUN=false
TOOL_SPECIFIED=false
TOOL_SELECTION=""
NO_SKILL=false
for arg in "$@"; do
  case "$arg" in
    --virtual-key=*) VIRTUAL_KEY="${arg#--virtual-key=}" ;;
    --dry-run)       DRY_RUN=true ;;
    --tool=*)        TOOL_SPECIFIED=true; TOOL_SELECTION="${arg#--tool=}" ;;
    --no-skill)      NO_SKILL=true ;;
    *)
      echo "Usage: $0 [--tool=all|litellm|opencode|codex|claude|pi|opencode,codex,...] [--virtual-key=sk-...] [--dry-run] [--no-skill]"
      exit 1
      ;;
  esac
done

# ── Version ──
PROJECT_VERSION="unknown"
if [ -f "$SCRIPT_DIR/../VERSION" ]; then
  PROJECT_VERSION=$(cat "$SCRIPT_DIR/../VERSION" | tr -d '[:space:]')
elif [ -f "$SCRIPT_DIR/VERSION" ]; then
  PROJECT_VERSION=$(cat "$SCRIPT_DIR/VERSION" | tr -d '[:space:]')
fi

# Compare versions: returns 0 if equal, 1 if v1 < v2, 2 if v1 > v2
version_compare() {
  local v1="$1" v2="$2"
  if [ "$v1" = "$v2" ]; then return 0; fi
  local IFS=.
  local i a1 a2
  read -ra a1 <<< "$v1"
  read -ra a2 <<< "$v2"
  for ((i = 0; i < ${#a1[@]} || i < ${#a2[@]}; i++)); do
    local n1=${a1[i]:-0} n2=${a2[i]:-0}
    if (( n1 < n2 )); then return 1; fi
    if (( n1 > n2 )); then return 2; fi
  done
  return 0
}

# Show version info for an existing install
show_version_info() {
  local existing_dir="$1"
  local existing_version="unknown"
  if [ -f "$existing_dir/VERSION" ]; then
    existing_version=$(cat "$existing_dir/VERSION" | tr -d '[:space:]')
  fi
  if [ "$existing_version" = "unknown" ]; then
    echo -e "  ${C_DIM}Existing version: unknown (pre-v1.0.0)${C_RESET}"
  elif [ "$existing_version" = "$PROJECT_VERSION" ]; then
    echo -e "  ${C_DIM}Version: $existing_version (up to date)${C_RESET}"
  else
    version_compare "$existing_version" "$PROJECT_VERSION" && rc=0 || rc=$?
    case $rc in
      1) echo -e "  ${C_GREEN}Update available: $existing_version → $PROJECT_VERSION${C_RESET}" ;;
      2) echo -e "  ${C_YELLOW}Local version $PROJECT_VERSION is newer than existing $existing_version${C_RESET}" ;;
    esac
  fi
}

# ── Standalone detection ──
# If helpers/common.sh doesn't exist, we're running outside the repo
# (e.g., curl | bash). Prompt for install dir, clone, and re-exec.
# is_interactive checks /dev/tty (not stdin) so it works under curl|bash.
is_interactive() { [ -c /dev/tty ] 2>/dev/null; }
# Minimal color setup (common.sh not sourced yet in standalone mode)
if [ -t 1 ]; then
  C_RESET="\033[0m"  C_BOLD="\033[1m"  C_DIM="\033[2m"
  C_RED="\033[31m"   C_GREEN="\033[32m" C_YELLOW="\033[33m"
  C_BLUE="\033[34m"  C_CYAN="\033[36m"
else
  C_RESET="" C_BOLD="" C_DIM=""
  C_RED="" C_GREEN="" C_YELLOW="" C_BLUE="" C_CYAN=""
fi
if [ ! -f "$SCRIPT_DIR/helpers/common.sh" ]; then
  echo ""
  echo "=== $REPO_NAME — Standalone bootstrap ==="
  echo ""
  default_parent="/home"
  if is_interactive; then
    echo -n "  Where to install? [$default_parent]: "
    read -r install_parent < /dev/tty || install_parent="$default_parent"
    install_parent="${install_parent:-$default_parent}"
  else
    install_parent="$default_parent"
  fi
  target_dir="$install_parent/$REPO_NAME"
  if [ -d "$target_dir/.git" ]; then
    echo "  Existing install found at $target_dir"
    show_version_info "$target_dir"
    if is_interactive; then
      echo ""
      echo -e "  ${C_BOLD}1)${C_RESET} Pull updates (preserve existing config & data) ${C_DIM}[default]${C_RESET}"
      echo -e "  ${C_BOLD}2)${C_RESET} Fresh install (uninstall old, remove all configs & Docker data)"
      echo -ne "  ${C_BOLD}Choice${C_RESET} ${C_DIM}[1]${C_RESET}: "
      read -r existing_choice < /dev/tty || existing_choice="1"
      echo ""
      case "${existing_choice:-1}" in
        2)
          echo "  Uninstalling old installation..."
          cd "$target_dir"
          # Remove Docker stack + tool configs (not the repo yet)
          ./scripts/uninstall.sh --tool=all --docker --yes || true
          cd "$install_parent"
          rm -rf "$target_dir"
          echo "  Old installation removed."
          echo "  Cloning fresh..."
          git clone "$REPO_URL" "$target_dir"
          cd "$target_dir"
          ;;
        *)
          echo "  Pulling updates..."
          cd "$target_dir"
          if ! git pull --ff-only; then
            echo ""
            echo -e "  ${C_YELLOW}⚠ git pull failed.${C_RESET} Reset to origin/main? ${C_DIM}[y/N]${C_RESET}: "
            read -r reset_choice < /dev/tty || reset_choice="n"
            case "$reset_choice" in
              y|Y|yes|YES)
                echo "  Resetting to origin/main..."
                git reset --hard origin/main
                ;;
              *)
                echo "  Aborting. Please resolve git conflicts manually."
                exit 1
                ;;
            esac
          fi
          ;;
      esac
    else
      echo "  Pulling updates..."
      cd "$target_dir"
      git pull --ff-only || git reset --hard origin/main
    fi
  else
    echo "  Cloning to $target_dir..."
    git clone "$REPO_URL" "$target_dir"
    cd "$target_dir"
  fi
  BOOTSTRAP_STANDALONE=1 exec ./scripts/bootstrap.sh "$@"
fi

# ── Now in the repo — source helpers ──
LITELLM_URL="http://127.0.0.1:4000"
source "$SCRIPT_DIR/helpers/prereqs.sh"
source "$SCRIPT_DIR/helpers/common.sh"
LOG_TAG="bootstrap"

# ── Refresh PATH for binaries installed by 03x scripts ──
# Installers add to .bashrc, but that only takes effect on shell restart.
# This makes opencode, bun, pi etc. findable in the current process.
refresh_path() {
  for dir in \
    "$HOME/.opencode/bin" \
    "$HOME/.bun/bin" \
    "$HOME/.local/bin" \
    "$HOME/.npm-global/bin" \
    "$HOME/.local/share/pi-node/current/bin" \
    /usr/local/bin; do
    if [ -d "$dir" ] && [[ ":$PATH:" != *":$dir:"* ]]; then
      export PATH="$dir:$PATH"
    fi
  done
  # nvm: pick the default Node version if installed
  if [ -d "$HOME/.nvm/versions/node" ]; then
    local nvm_dir
    nvm_dir=$(ls -d "$HOME/.nvm/versions/node"/*/bin 2>/dev/null | tail -1 || true)
    if [ -n "$nvm_dir" ] && [[ ":$PATH:" != *":$nvm_dir:"* ]]; then
      export PATH="$nvm_dir:$PATH"
    fi
  fi
  # pi-node: versioned dirs
  for dir in $(ls -d "$HOME/.local/share/pi-node"/*/bin 2>/dev/null || true); do
    if [[ ":$PATH:" != *":$dir:"* ]]; then
      export PATH="$dir:$PATH"
    fi
  done
  hash -r 2>/dev/null || true
}
refresh_path

# ── Track whether keys came from env vars (vs interactive prompts) ──
# Used to decide if the security disclaimer is shown at the end.
KEYS_FROM_ENV=false
if [ -n "${HUAWEI_MAAS_API_KEY:-}" ] \
   || [ -n "${HUAWEI_MAAS_API_KEY_COUNT:-}" ] \
   || [ -n "${LITELLM_MASTER_KEY:-}" ] \
   || [ -n "${VIRTUAL_KEY:-}" ]; then
  KEYS_FROM_ENV=true
fi
# Also check for HUAWEI_MAAS_API_KEY_1..N
for _v in "${!HUAWEI_MAAS_API_KEY_@}"; do
  [ -n "${!_v}" ] && KEYS_FROM_ENV=true
done

# ── Prevent concurrent runs (flock) ──
exec 9>"$PROJECT_DIR/.bootstrap.lock"
if ! flock -n 9; then
  log_error "Another bootstrap is already running in $PROJECT_DIR."
  log_dim "If this is stale, remove $PROJECT_DIR/.bootstrap.lock and retry."
  exit 1
fi

# ── Defaults ──
INSTALL_OPENCODE=true
INSTALL_CODEX=true
INSTALL_CLAUDE_CODE=true
INSTALL_PI=true

# ── Parse --tool= into INSTALL_* flags ──
if [ "$TOOL_SPECIFIED" = true ]; then
  INSTALL_OPENCODE=false
  INSTALL_CODEX=false
  INSTALL_CLAUDE_CODE=false
  INSTALL_PI=false
  IFS=',' read -ra TOOL_PARTS <<< "$TOOL_SELECTION"
  for part in "${TOOL_PARTS[@]}"; do
    case "$part" in
      all)       INSTALL_OPENCODE=true; INSTALL_CODEX=true; INSTALL_CLAUDE_CODE=true; INSTALL_PI=true ;;
      litellm)   ;;
      opencode)  INSTALL_OPENCODE=true ;;
      codex)     INSTALL_CODEX=true ;;
      claude)    INSTALL_CLAUDE_CODE=true ;;
      pi)        INSTALL_PI=true ;;
      *)
        log_error "Unknown tool '$part' in --tool=$TOOL_SELECTION"
        log_dim "Valid values: all, litellm, opencode, codex, claude, pi (or comma-separated combo)"
        exit 1
        ;;
    esac
  done
fi

# ── Banner ──
_banner_text="oh-my-coding-maas-gateway — Bootstrap v${PROJECT_VERSION}"
_banner_width=$(( ${#_banner_text} + 4 ))
_banner_border=""
for _i in $(seq 1 $_banner_width); do _banner_border+="═"; done
echo ""
echo -e "${C_BOLD}${C_CYAN}╔${_banner_border}╗${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}║  ${_banner_text}  ║${C_RESET}"
echo -e "${C_BOLD}${C_CYAN}╚${_banner_border}╝${C_RESET}"
echo ""

# ── Install directory prompt ──
current_parent="$(dirname "$PROJECT_DIR")"
if [ "${BOOTSTRAP_STANDALONE:-}" = "1" ]; then
  # Skip prompt — already determined during standalone bootstrap
  install_parent="$current_parent"
elif is_interactive; then
  install_parent=$(prompt_input "Install directory (project will be in \$INSTALL_DIR/$REPO_NAME)" "$current_parent")
else
  install_parent="$current_parent"
fi
target_dir="$install_parent/$REPO_NAME"

if [ "$target_dir" != "$PROJECT_DIR" ]; then
  if [ -d "$target_dir/.git" ]; then
    log_info "Project already exists at $target_dir"
    show_version_info "$target_dir"
    echo ""
    echo -e "  ${C_BOLD}1)${C_RESET} Switch to existing (pull updates) ${C_DIM}[default]${C_RESET}"
    echo -e "  ${C_BOLD}2)${C_RESET} Fresh install (uninstall old, remove all configs & Docker data)"
    if is_interactive; then
      echo -ne "  ${C_BOLD}Choice${C_RESET} ${C_DIM}[1]${C_RESET}: "
      read -r existing_choice < /dev/tty || existing_choice="1"
    else
      existing_choice="1"
    fi
    echo ""
    case "${existing_choice:-1}" in
      2)
        log_info "Uninstalling old installation..."
        cd "$target_dir"
        ./scripts/uninstall.sh --tool=all --docker --yes || true
        cd "$install_parent"
        rm -rf "$target_dir"
        log_ok "Old installation removed."
        log_info "Cloning fresh..."
        git clone "$REPO_URL" "$target_dir"
        cd "$target_dir"
        exec ./scripts/bootstrap.sh "$@"
        ;;
      *)
        cd "$target_dir"
        exec ./scripts/bootstrap.sh "$@"
        ;;
    esac
  elif [ "$DRY_RUN" = true ]; then
    log_dim "Would clone: $REPO_URL → $target_dir"
  else
    log_info "Cloning project to $target_dir..."
    git clone "$REPO_URL" "$target_dir"
    cd "$target_dir"
    exec ./scripts/bootstrap.sh "$@"
  fi
fi

log_info "Project dir: $PROJECT_DIR"
[ "$DRY_RUN" = true ] && log_warn "DRY RUN — no changes will be made"

# ── Core prerequisites ──
log_step "Core prerequisites"
prereq_ensure_apt "git"     git     git     "git is needed to clone this repository and pull updates"
prereq_ensure_apt "python3" python3 python3 "python3 is needed for config generation and validation scripts"
prereq_ensure_apt "curl"    curl    curl    "curl is needed to download install scripts and make API calls"
prereq_ensure_apt "jq"      jq      jq      "jq is needed to parse JSON from MaaS API and LiteLLM responses"

# ── Tool selection (menu if --tool= not given) ──
if [ "$TOOL_SPECIFIED" = false ] && is_interactive; then
  while true; do
    log_step "Select installation scope"
    echo -e "  ${C_BOLD}1)${C_RESET} Default — LiteLLM + all coding tools"
    echo -e "  ${C_BOLD}2)${C_RESET} LiteLLM only"
    echo -e "  ${C_BOLD}3)${C_RESET} LiteLLM + opencode"
    echo -e "  ${C_BOLD}4)${C_RESET} LiteLLM + Codex"
    echo -e "  ${C_BOLD}5)${C_RESET} LiteLLM + Claude Code"
    echo -e "  ${C_BOLD}6)${C_RESET} LiteLLM + Pi"
    echo -e "  ${C_BOLD}7)${C_RESET} Custom — toggle each component"
    echo -ne "  ${C_BOLD}Choice${C_RESET} ${C_DIM}[1]${C_RESET}: "
    choice=""
    read -r choice < /dev/tty || choice="1"
    case "${choice:-1}" in
      1) INSTALL_OPENCODE=true;  INSTALL_CODEX=true;  INSTALL_CLAUDE_CODE=true;  INSTALL_PI=true ;;
      2) INSTALL_OPENCODE=false; INSTALL_CODEX=false; INSTALL_CLAUDE_CODE=false; INSTALL_PI=false ;;
      3) INSTALL_OPENCODE=true;  INSTALL_CODEX=false; INSTALL_CLAUDE_CODE=false; INSTALL_PI=false ;;
      4) INSTALL_OPENCODE=false; INSTALL_CODEX=true;  INSTALL_CLAUDE_CODE=false; INSTALL_PI=false ;;
      5) INSTALL_OPENCODE=false; INSTALL_CODEX=false; INSTALL_CLAUDE_CODE=true;  INSTALL_PI=false ;;
      6) INSTALL_OPENCODE=false; INSTALL_CODEX=false; INSTALL_CLAUDE_CODE=false; INSTALL_PI=true ;;
      7)
        log_dim "Custom selection (LiteLLM is always installed):"
        if prompt_yesno "Install opencode?" y; then INSTALL_OPENCODE=true; else INSTALL_OPENCODE=false; fi
        if prompt_yesno "Install Codex?" y; then INSTALL_CODEX=true; else INSTALL_CODEX=false; fi
        if prompt_yesno "Install Claude Code?" y; then INSTALL_CLAUDE_CODE=true; else INSTALL_CLAUDE_CODE=false; fi
        if prompt_yesno "Install Pi?" y; then INSTALL_PI=true; else INSTALL_PI=false; fi
        ;;
      *)
        log_warn "Invalid choice. Defaulting to all."
        INSTALL_OPENCODE=true; INSTALL_CODEX=true; INSTALL_CLAUDE_CODE=true; INSTALL_PI=true
        ;;
    esac

    # ── Show selected scope ──
    echo ""
    log_info "Installation scope:"
    _yes() { echo -e "${C_GREEN}yes${C_RESET}"; }
    _no()  { echo -e "${C_DIM}no${C_RESET}"; }
    printf "    ${C_DIM}%-14s${C_RESET} %s\n" "LiteLLM:"      "yes (always)"
    printf "    ${C_DIM}%-14s${C_RESET} %s\n" "opencode:"     "$([ "$INSTALL_OPENCODE" = true ] && _yes || _no)"
    printf "    ${C_DIM}%-14s${C_RESET} %s\n" "Codex:"        "$([ "$INSTALL_CODEX" = true ] && _yes || _no)"
    printf "    ${C_DIM}%-14s${C_RESET} %s\n" "Claude Code:"  "$([ "$INSTALL_CLAUDE_CODE" = true ] && _yes || _no)"
    printf "    ${C_DIM}%-14s${C_RESET} %s\n" "Pi:"           "$([ "$INSTALL_PI" = true ] && _yes || _no)"

    # ── Selection-driven prerequisite summary (prereq → needed by) ──
    log_dim "Prerequisites to install (as needed):"
    echo ""

    CURL_TOOLS="bootstrap, litellm, validate"
    JQ_TOOLS="bootstrap, validate"
    [ "$INSTALL_OPENCODE" = true ]   && CURL_TOOLS+=", opencode"  && JQ_TOOLS+=", opencode"
    [ "$INSTALL_CODEX" = true ]      && CURL_TOOLS+=", codex"     && JQ_TOOLS+=", codex"
    [ "$INSTALL_CLAUDE_CODE" = true ] && CURL_TOOLS+=", claude"   && JQ_TOOLS+=", claude"
    [ "$INSTALL_PI" = true ]         && CURL_TOOLS+=", pi"        && JQ_TOOLS+=", pi"

    NPM_TOOLS=""
    [ "$INSTALL_CODEX" = true ]       && NPM_TOOLS="codex"
    [ "$INSTALL_CLAUDE_CODE" = true ] && NPM_TOOLS="${NPM_TOOLS:+$NPM_TOOLS, }claude"

    printf "    ${C_DIM}%-14s %s${C_RESET}\n" "git"          "— bootstrap, env"
    printf "    ${C_DIM}%-14s %s${C_RESET}\n" "python3"      "— bootstrap, env"
    printf "    ${C_DIM}%-14s %s${C_RESET}\n" "curl"         "— $CURL_TOOLS"
    printf "    ${C_DIM}%-14s %s${C_RESET}\n" "jq"           "— $JQ_TOOLS"
    printf "    ${C_DIM}%-14s %s${C_RESET}\n" "docker"       "— litellm"
    [ "$INSTALL_OPENCODE" = true ]    && printf "    ${C_DIM}%-14s %s${C_RESET}\n" "bun"        "— opencode"
    [ -n "$NPM_TOOLS" ]               && printf "    ${C_DIM}%-14s %s${C_RESET}\n" "npm/node"   "— $NPM_TOOLS"
    [ "$INSTALL_CODEX" = true ]       && printf "    ${C_DIM}%-14s %s${C_RESET}\n" "bubblewrap" "— codex"

    # ── Confirm selection before proceeding ──
    echo ""
    if prompt_yesno "Proceed with this selection?" y; then
      break
    fi
    log_info "Let's try again."
  done
fi

# ── Show scope for non-interactive mode (--tool= given) ──
if [ "$TOOL_SPECIFIED" = true ] || ! is_interactive; then
  echo ""
  log_info "Installation scope:"
  _yes() { echo -e "${C_GREEN}yes${C_RESET}"; }
  _no()  { echo -e "${C_DIM}no${C_RESET}"; }
  printf "    ${C_DIM}%-14s${C_RESET} %s\n" "LiteLLM:"      "yes (always)"
  printf "    ${C_DIM}%-14s${C_RESET} %s\n" "opencode:"     "$([ "$INSTALL_OPENCODE" = true ] && _yes || _no)"
  printf "    ${C_DIM}%-14s${C_RESET} %s\n" "Codex:"        "$([ "$INSTALL_CODEX" = true ] && _yes || _no)"
  printf "    ${C_DIM}%-14s${C_RESET} %s\n" "Claude Code:"  "$([ "$INSTALL_CLAUDE_CODE" = true ] && _yes || _no)"
  printf "    ${C_DIM}%-14s${C_RESET} %s\n" "Pi:"           "$([ "$INSTALL_PI" = true ] && _yes || _no)"
fi
echo ""

# ── Step 01: Environment & secrets ──
if [ "$DRY_RUN" = true ]; then
  log_step "Step 01: Environment & secrets"
  log_dim "Would run: scripts/01_env.sh"
else
  log_desc "Setting up environment variables, secrets, and .env file"
  "$SCRIPT_DIR/01_env.sh"
  log_done "Environment configured — .env written with MaaS key and secrets"
fi

# ── Step 02: LiteLLM proxy + observability ──
if [ "$DRY_RUN" = true ]; then
  log_step "Step 02: LiteLLM proxy + observability"
  log_dim "Would run: scripts/02_litellm.sh --dry-run"
else
  log_desc "Deploying LiteLLM proxy, Docker containers, and observability stack"
  "$SCRIPT_DIR/02_litellm.sh"
  log_done "LiteLLM proxy running — 6 models, Grafana + Prometheus active"
fi

# ── Step 03a: opencode (optional) ──
if [ "$INSTALL_OPENCODE" = true ]; then
  OPENCODE_ARGS=()
  [ -n "$VIRTUAL_KEY" ] && OPENCODE_ARGS+=("--virtual-key=$VIRTUAL_KEY")
  [ "$DRY_RUN" = true ] && OPENCODE_ARGS+=("--dry-run")
  if [ "$DRY_RUN" = true ]; then
    log_step "Step 03a: opencode"
    log_dim "Would run: scripts/03a_opencode.sh ${OPENCODE_ARGS[*]}"
  else
    log_desc "Installing opencode + oh-my-opencode-slim plugin"
    "$SCRIPT_DIR/03a_opencode.sh" "${OPENCODE_ARGS[@]}"
    log_done "opencode configured — LiteLLM provider, 4 presets, 7 agents"
    refresh_path
  fi
else
  log_dim "(skipping opencode)"
fi

# ── Step 03b: Codex CLI (optional) ──
if [ "$INSTALL_CODEX" = true ]; then
  CODEX_ARGS=()
  [ "$DRY_RUN" = true ] && CODEX_ARGS+=("--dry-run")
  if [ "$DRY_RUN" = true ]; then
    log_step "Step 03b: Codex CLI"
    log_dim "Would run: scripts/03b_codex.sh ${CODEX_ARGS[*]}"
  else
    log_desc "Installing Codex CLI and configuring LiteLLM virtual key"
    "$SCRIPT_DIR/03b_codex.sh" "${CODEX_ARGS[@]}"
    log_done "Codex CLI configured — LiteLLM virtual key minted"
  fi
else
  log_dim "(skipping Codex CLI)"
fi

# ── Step 03c: Claude Code CLI (optional) ──
if [ "$INSTALL_CLAUDE_CODE" = true ]; then
  CLAUDE_ARGS=()
  [ "$DRY_RUN" = true ] && CLAUDE_ARGS+=("--dry-run")
  if [ "$DRY_RUN" = true ]; then
    log_step "Step 03c: Claude Code CLI"
    log_dim "Would run: scripts/03c_claude_code.sh ${CLAUDE_ARGS[*]}"
  else
    log_desc "Installing Claude Code CLI and configuring LiteLLM virtual key"
    "$SCRIPT_DIR/03c_claude_code.sh" "${CLAUDE_ARGS[@]}"
    log_done "Claude Code CLI configured — LiteLLM virtual key minted"
  fi
else
  log_dim "(skipping Claude Code CLI)"
fi

# ── Step 03d: Pi agent (optional) ──
if [ "$INSTALL_PI" = true ]; then
  PI_ARGS=()
  [ "$DRY_RUN" = true ] && PI_ARGS+=("--dry-run")
  if [ "$DRY_RUN" = true ]; then
    log_step "Step 03d: Pi agent"
    log_dim "Would run: scripts/03d_pi.sh ${PI_ARGS[*]}"
  else
    log_desc "Installing Pi coding agent and configuring LiteLLM virtual key"
    "$SCRIPT_DIR/03d_pi.sh" "${PI_ARGS[@]}"
    log_done "Pi agent configured — LiteLLM virtual key minted"
    refresh_path
  fi
else
  log_dim "(skipping Pi agent)"
fi

# ── Step 04: Validate ──
VALIDATE_ARGS=()
[ "$DRY_RUN" = true ] && VALIDATE_ARGS+=("--dry-run")
[ "$INSTALL_OPENCODE" = false ] && VALIDATE_ARGS+=("--skip-opencode")
[ "$INSTALL_CODEX" = false ] && VALIDATE_ARGS+=("--skip-codex")
[ "$INSTALL_CLAUDE_CODE" = false ] && VALIDATE_ARGS+=("--skip-claude-code")
[ "$INSTALL_PI" = false ] && VALIDATE_ARGS+=("--skip-pi")
if [ "$DRY_RUN" = true ]; then
  log_step "Step 04: Validate"
  log_dim "Would run: scripts/04_validate.sh ${VALIDATE_ARGS[*]}"
  VALIDATE_RC=0
else
  log_desc "Running end-to-end validation of all components"
  set +e
  "$SCRIPT_DIR/04_validate.sh" "${VALIDATE_ARGS[@]}"
  VALIDATE_RC=$?
  set -e
  if [ "$VALIDATE_RC" -eq 0 ]; then
    log_done "Validation passed — all components verified"
  else
    log_warn "Validation completed with failures"
  fi
fi

# ── Step 05: Companion skill ──
SKILL_ARGS=()
[ "$DRY_RUN" = true ] && SKILL_ARGS+=("--dry-run")
[ "$NO_SKILL" = true ] && SKILL_ARGS+=("--no-skill")
if [ "$NO_SKILL" = true ]; then
  log_dim "(skipping companion skill)"
elif [ "$DRY_RUN" = true ]; then
  log_step "Step 05: Companion skill"
  log_dim "Would run: scripts/05_skill.sh ${SKILL_ARGS[*]}"
else
  log_desc "Installing companion skill into coding agents"
  set +e
  "$SCRIPT_DIR/05_skill.sh" "${SKILL_ARGS[@]}"
  set -e
fi

# ── Summary ──
echo ""
if [ "$VALIDATE_RC" -eq 0 ]; then
  echo -e "${C_BOLD}${C_GREEN}  ✓ Bootstrap complete${C_RESET}"
else
  echo -e "${C_BOLD}${C_YELLOW}  ⚠ Bootstrap completed with validation failures${C_RESET}"
fi
echo ""
printf "  ${C_DIM}%-20s${C_RESET} %s\n" "Version:"           "v${PROJECT_VERSION}"
printf "  ${C_DIM}%-20s${C_RESET} %s\n" "Project dir:"       "$PROJECT_DIR"
printf "  ${C_DIM}%-20s${C_RESET} %s\n" "LiteLLM proxy:"     "$LITELLM_URL"
printf "  ${C_DIM}%-20s${C_RESET} %s\n" "LiteLLM Admin UI:"  "${LITELLM_URL}/ui"
printf "  ${C_DIM}%-20s${C_RESET} %s\n" "Grafana:"           "http://127.0.0.1:3000 (anonymous)"
printf "  ${C_DIM}%-20s${C_RESET} %s\n" "Prometheus:"        "http://127.0.0.1:9090"

if [ "$INSTALL_OPENCODE" = true ] && [ -f "$HOME/.config/opencode/opencode.json" ]; then
  printf "  ${C_DIM}%-20s${C_RESET} %s\n" "opencode config:"   "~/.config/opencode/opencode.json"
  FINAL_VK=$(strip_jsonc "$HOME/.config/opencode/opencode.json" 2>/dev/null \
    | jq -r '.provider.LiteLLM.options.apiKey // empty' 2>/dev/null || true)
  [ -n "$FINAL_VK" ] && printf "  ${C_DIM}%-20s${C_RESET} %s\n" "opencode key:"      "$(mask_key "$FINAL_VK")"
fi
if [ "$INSTALL_CODEX" = true ] && [ -f "$HOME/.codex/.env" ]; then
  printf "  ${C_DIM}%-20s${C_RESET} %s\n" "Codex CLI config:"   "~/.codex/config.toml"
  CODEX_VK=$(grep -oP '^LITELLM_CODEX_API_KEY=\K.*' "$HOME/.codex/.env" 2>/dev/null || true)
  [ -n "$CODEX_VK" ] && printf "  ${C_DIM}%-20s${C_RESET} %s\n" "Codex CLI key:"      "$(mask_key "$CODEX_VK")"
fi
if [ "$INSTALL_CLAUDE_CODE" = true ] && [ -f "$HOME/.claude/settings.json" ]; then
  printf "  ${C_DIM}%-20s${C_RESET} %s\n" "Claude Code config:" "~/.claude/settings.json"
  CLAUDE_VK=$(jq -r '.env.ANTHROPIC_API_KEY // empty' "$HOME/.claude/settings.json" 2>/dev/null || true)
  [ -n "$CLAUDE_VK" ] && printf "  ${C_DIM}%-20s${C_RESET} %s\n" "Claude Code key:"    "$(mask_key "$CLAUDE_VK")"
fi
if [ "$INSTALL_PI" = true ] && [ -f "$HOME/.pi/agent/models.json" ]; then
  printf "  ${C_DIM}%-20s${C_RESET} %s\n" "Pi config:"         "~/.pi/agent/models.json"
  PI_VK=$(jq -r '.providers.LiteLLM.apiKey // empty' "$HOME/.pi/agent/models.json" 2>/dev/null || true)
  [ -n "$PI_VK" ] && printf "  ${C_DIM}%-20s${C_RESET} %s\n" "Pi key:"              "$(mask_key "$PI_VK")"
fi

echo ""
echo -e "  ${C_BOLD}Next steps:${C_RESET}"
echo -e "  ${C_DIM}Restart your terminal (or run: exec \"\$SHELL\") for newly installed tools to appear on PATH.${C_RESET}"
echo ""
[ "$INSTALL_OPENCODE" = true ] && printf "    ${C_DIM}%-12s${C_RESET} %b\n" "opencode:"  "${C_CYAN}opencode${C_RESET}"
[ "$INSTALL_CODEX" = true ] && printf "    ${C_DIM}%-12s${C_RESET} %b\n" "Codex:"     "${C_CYAN}codex${C_RESET}"
[ "$INSTALL_CLAUDE_CODE" = true ] && printf "    ${C_DIM}%-12s${C_RESET} %b\n" "Claude:"    "${C_CYAN}claude --bare${C_RESET}"
[ "$INSTALL_PI" = true ] && printf "    ${C_DIM}%-12s${C_RESET} %b\n" "Pi:"        "${C_CYAN}pi${C_RESET}"
echo ""

if [ "$KEYS_FROM_ENV" = true ]; then
  echo -e "  ${C_YELLOW}⚠ Security:${C_RESET} API keys were shared via environment variables and command line."
  echo -e "    ${C_DIM}Rotate your MaaS keys to prevent unauthorized use:${C_RESET}"
  echo -e "      ${C_DIM}1. Get new key(s) from https://console.huaweicloud.com/modelarts/${C_RESET}"
  echo -e "      ${C_DIM}2. Edit .env: replace HUAWEI_MAAS_API_KEY and HUAWEI_MAAS_API_KEY_1..N${C_RESET}"
  echo -e "      ${C_DIM}3. Regenerate config: ./scripts/02_litellm.sh${C_RESET}"
  echo -e "      ${C_DIM}4. Restart LiteLLM:  docker compose restart litellm${C_RESET}"
  echo -e "      ${C_DIM}5. Re-validate:      ./scripts/04_validate.sh${C_RESET}"
  echo ""
  echo -e "  ${C_BOLD}Restart your shell${C_RESET} (or open a new terminal) to clear exported environment"
  echo -e "  variables and apply all changes:"
  echo -e "    ${C_CYAN}exec \"\$SHELL\"${C_RESET}    ${C_DIM}# or close and reopen your terminal${C_RESET}"
fi

exit "$VALIDATE_RC"
