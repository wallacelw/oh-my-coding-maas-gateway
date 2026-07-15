#!/usr/bin/env bash
# prereqs.sh — Shared prerequisite installation helpers
#
# Source from any script:
#   source "$(dirname "${BASH_SOURCE[0]}")/helpers/prereqs.sh"
#
# Mode is controlled by $PREREQ_MODE:
#   prompt — ask y/n before installing (default; interactive)
#   auto   — install without prompting (CI / explicit override)
#
# When stdin is not a TTY (e.g. agent piping answers, CI), prompts are
# auto-confirmed so installation proceeds without blocking.
#
# All functions are idempotent: safe to call multiple times.

# Ensure logging helpers are available
if ! declare -F log_error >/dev/null 2>&1; then
  source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
fi

# ---------------------------------------------------------------------------
# Sudo availability guard (checked once at source time)
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ] && ! command -v sudo &>/dev/null; then
  log_error "sudo is required when not running as root. Install it or run as root."
  exit 1
fi

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Run with sudo if not root, directly if root
_prereq_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}
export -f _prereq_sudo

# Run apt-get update once per process
declare -g _PREREQ_APT_UPDATED=false
_prereq_apt_update_once() {
  if [ "$_PREREQ_APT_UPDATED" = true ]; then
    return 0
  fi
  _prereq_sudo apt-get update -qq
  _PREREQ_APT_UPDATED=true
}

# Exit 1 with an install hint
_prereq_fail() {
  local name="$1"
  log_error "Required prerequisite '$name' is not available and could not be installed."
  log_dim "Install it manually or check your package manager."
  exit 1
}

# Prompt user y/n (only in prompt mode); returns 0 for yes, 1 for no.
# Non-interactive shells (piped stdin / CI) auto-confirm.
# Uses prompt_yesno from common.sh for reliable /dev/tty handling.
_prereq_prompt() {
  local question="$1"
  if [ "${PREREQ_MODE:-prompt}" = "auto" ]; then
    return 0
  fi
  # Non-interactive shell → auto-install
  if ! is_interactive; then
    return 0
  fi
  prompt_yesno "$question" y
}

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

# Ensure a command is on PATH; install via apt-get if missing.
#   prereq_ensure_apt <display_name> <command> <apt_package> <reason>
prereq_ensure_apt() {
  local display_name="$1"
  local cmd="$2"
  local pkg="$3"
  local reason="$4"

  if command -v "$cmd" &>/dev/null; then
    return 0
  fi

  log_info "$reason"
  if ! _prereq_prompt "  Install $display_name?"; then
    _prereq_fail "$display_name"
  fi

  _prereq_apt_update_once
  if ! run_with_spinner "Installing $display_name" _prereq_sudo apt-get install -y -qq "$pkg"; then
    _prereq_fail "$display_name"
  fi
  export _PREREQ_APT_UPDATED=true

  if ! command -v "$cmd" &>/dev/null; then
    _prereq_fail "$display_name"
  fi
  log_ok "$display_name installed"
}

# Ensure bun is available (special: needs PATH sourcing after install)
#   prereq_ensure_bun <reason>
prereq_ensure_bun() {
  local reason="$1"

  if command -v bun &>/dev/null; then
    return 0
  fi

  log_info "$reason"
  if ! _prereq_prompt "  Install bun?"; then
    _prereq_fail "bun"
  fi

  # bun installer (bun.sh/install) requires unzip to extract the binary
  if ! command -v unzip &>/dev/null; then
    prereq_ensure_apt "unzip" "unzip" "unzip" "unzip is required to install bun"
  fi

  if ! run_with_spinner "Installing bun" bash -c 'curl -fsSL --max-time 60 https://bun.sh/install | bash'; then
    _prereq_fail "bun"
  fi
  export BUN_INSTALL="${BUN_INSTALL:-$HOME/.bun}"
  export PATH="$BUN_INSTALL/bin:$PATH"

  if ! command -v bun &>/dev/null; then
    _prereq_fail "bun"
  fi
  log_ok "bun installed"
}

# Ensure node + npm are available
#   prereq_ensure_npm <reason>
prereq_ensure_npm() {
  local reason="$1"

  if command -v npm &>/dev/null && command -v node &>/dev/null; then
    return 0
  fi

  log_info "$reason"
  if ! _prereq_prompt "  Install Node.js + npm?"; then
    _prereq_fail "npm/node"
  fi

  _prereq_apt_update_once
  if ! run_with_spinner "Installing Node.js + npm" _prereq_sudo apt-get install -y -qq nodejs npm; then
    _prereq_fail "npm/node"
  fi

  if ! command -v npm &>/dev/null; then
    _prereq_fail "npm"
  fi
  log_ok "Node.js + npm installed"
}

# Ensure docker + compose plugin + daemon are running
#   prereq_ensure_docker <reason>
prereq_ensure_docker() {
  local reason="$1"

  # Install docker engine if missing
  if ! command -v docker &>/dev/null; then
    log_info "$reason"
    if ! _prereq_prompt "  Install Docker?"; then
      _prereq_fail "docker"
    fi
    if ! run_with_spinner "Installing Docker Engine" bash -c 'curl -fsSL --max-time 120 https://get.docker.com | _prereq_sudo sh'; then
      _prereq_fail "docker"
    fi
    # Refresh PATH — get.docker.com installs to /usr/bin which should exist
    hash -r 2>/dev/null || true
  fi

  # Verify docker is now available
  if ! command -v docker &>/dev/null; then
    _prereq_fail "docker"
  fi

  # Ensure compose plugin
  if ! docker compose version &>/dev/null; then
    log_info "Docker Compose plugin is needed to orchestrate multi-container stacks"
    _prereq_apt_update_once
    if ! run_with_spinner "Installing Docker Compose plugin" _prereq_sudo apt-get install -y -qq docker-compose-v2; then
      _prereq_fail "docker-compose-v2"
    fi
  fi

  # Start daemon if not running
  if ! docker info &>/dev/null; then
    log_info "Starting Docker daemon — containers cannot run without it"
    if command -v systemctl &>/dev/null; then
      _prereq_sudo systemctl start docker
    elif command -v service &>/dev/null; then
      _prereq_sudo service docker start
    else
      _prereq_sudo dockerd &>/dev/null &
    fi
    sleep 3
  fi

  # Final check
  if ! docker info &>/dev/null; then
    _prereq_fail "docker daemon"
  fi
  log_ok "Docker ready"
}
