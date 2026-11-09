#!/usr/bin/env bash
set -euo pipefail
umask 077  # written configs/skills may hold secrets — deny group/world access

# ─── 04_skills_mcps.sh — Agent skills & MCP bundles (pipeline step 04) ─────────
#
# Domain:        Coding-agent skills + MCP servers
# Order:         04 (after the agent configs in 03a-03d, before 05_validate)
# Optional:      companions + bundles are individually skippable
# Description:   Installs the gateway operations companion skill and the two
#                optional-but-default-on agent tool bundles into each installed
#                coding agent (opencode, codex, claude, pi):
#                  1) Companion skill (gateway operations)      — default on
#                  2) REA bundle   (rea-agents MCP + skill)     — default on
#                  3) drawio bundle (@drawio/mcp MCP + skill)   — default on
#                Strictly local: the only data destination is the model via the
#                LiteLLM proxy. Bundles need Node >= NODE_MCP_MIN_VERSION.
# Inputs:        --yes, --dry-run, --no-skill, --no-rea, --no-drawio,
#                --refresh-only, --strict,
#                --skip-opencode/--skip-codex/--skip-claude-code/--skip-pi
# Outputs:       ~/.config/opencode/skills/<name>, ~/.codex/skills/<name>,
#                ~/.pi/agent/skills/<name>, ~/.claude/skills/<name>;
#                MCP registrations in each agent's config.
# Standalone:    yes — ./scripts/04_skills_mcps.sh
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

source "$SCRIPT_DIR/helpers/common.sh"
source "$SCRIPT_DIR/helpers/skills.sh"
source "$SCRIPT_DIR/helpers/mcp.sh"
source "$SCRIPT_DIR/helpers/prereqs.sh"
source "$SCRIPT_DIR/helpers/versions.sh"

# ── Parse args ──
DRY_RUN=false
ASSUME_YES=false
NO_SKILL=false
NO_REA=false
NO_DRAWIO=false
REFRESH_ONLY=false
STRICT=false
SKIP_OPENCODE=false
SKIP_CODEX=false
SKIP_CLAUDE_CODE=false
SKIP_PI=false

for arg in "$@"; do
  case "$arg" in
    --yes)              ASSUME_YES=true ;;
    --dry-run)          DRY_RUN=true ;;
    --no-skill)         NO_SKILL=true ;;
    --no-rea)           NO_REA=true ;;
    --no-drawio)        NO_DRAWIO=true ;;
    --refresh-only)     REFRESH_ONLY=true ;;
    --strict)           STRICT=true ;;
    --skip-opencode)    SKIP_OPENCODE=true ;;
    --skip-codex)       SKIP_CODEX=true ;;
    --skip-claude-code) SKIP_CLAUDE_CODE=true ;;
    --skip-pi)          SKIP_PI=true ;;
    *) log_error "Unknown flag: $arg"; exit 1 ;;
  esac
done
# Honor bootstrap's non-interactive AUTO_YES export.
[ "${AUTO_YES:-false}" = true ] && ASSUME_YES=true

# ── PATH refresh (mirror bootstrap essentials for standalone runs) ──
refresh_path() {
  local dir
  for dir in \
    "$HOME/.opencode/bin" \
    "$HOME/.bun/bin" \
    "$HOME/.local/bin" \
    "$HOME/.npm-global/bin" \
    "$HOME/.pi/agent/bin" \
    /usr/local/bin; do
    if [ -d "$dir" ] && [[ ":$PATH:" != *":$dir:"* ]]; then
      export PATH="$dir:$PATH"
    fi
  done
  # pi-node versioned dirs
  for dir in $(ls -d "$HOME/.local/share/pi-node"/*/bin 2>/dev/null || true); do
    if [[ ":$PATH:" != *":$dir:"* ]]; then
      export PATH="$dir:$PATH"
    fi
  done
  hash -r 2>/dev/null || true
}
refresh_path

log_step "Step 04 — Agent skills & MCP bundles"
[ "$DRY_RUN" = true ] && log_warn "DRY RUN — no changes will be made"

# ── Detect installed tools (minus --skip-* exclusions) ──
TOOLS=""
command -v opencode &>/dev/null && [ "$SKIP_OPENCODE" = false ]    && TOOLS+="opencode "
command -v codex &>/dev/null    && [ "$SKIP_CODEX" = false ]       && TOOLS+="codex "
command -v claude &>/dev/null   && [ "$SKIP_CLAUDE_CODE" = false ] && TOOLS+="claude "
command -v pi &>/dev/null       && [ "$SKIP_PI" = false ]          && TOOLS+="pi "

if [ -z "$TOOLS" ]; then
  log_info "No coding agents detected — skipping agent skills & bundles"
  exit 0
fi
log_info "Detected coding agents: $(echo "$TOOLS" | tr ' ' ',' | sed 's/,$//')"

# ── Result trackers ──
COMP_FAILED=0
REA_FAIL=0
DRAWIO_FAIL=0
REA_RESULTS=""
DRAWIO_RESULTS=""
REA_STATUS=""
DRAWIO_STATUS=""

# ── Helpers ──
rea_client_id() {
  case "$1" in
    opencode) echo opencode ;;
    codex)    echo codex ;;
    claude)   echo claude_code ;;
    pi)       echo pi ;;
    *)        return 1 ;;
  esac
}

# npm global install under the system prefix (reuse 03b's writable-or-sudo).
npm_install_global() {
  local spec="$1" prefix
  prefix=$(npm config get prefix 2>/dev/null || echo "")
  if [ -n "$prefix" ] && [ -w "$prefix/lib/node_modules" ] 2>/dev/null; then
    run_filtered "npm" npm install -g "$spec"
  else
    log_info "  npm global prefix not writable — using sudo"
    run_filtered "npm" sudo npm install -g "$spec"
  fi
}

# Ensure Node >= NODE_MCP_MIN_VERSION for the bundles. Returns 1 (soft) when
# unavailable so the caller can warn + skip both bundles.
setup_node_for_bundles() {
  if prereq_ensure_node_mcp "Node.js >= $NODE_MCP_MIN_VERSION is required for the REA + drawio bundles"; then
    export PATH="${NODE_MCP_BIN_DIR}:$PATH"
    hash -r 2>/dev/null || true
    local prefix
    prefix=$(npm config get prefix 2>/dev/null || true)
    if [ -n "$prefix" ] && [[ "$prefix" == *"pi-node"* ]]; then
      log_warn "npm global prefix resolves inside pi-node ($prefix) — bundles may misbehave"
    fi
    return 0
  fi
  return 1
}

# Ensure curl+jq for MCP bundle setup. Soft-fail: returns 1 when the user
# declines (or the install fails) so the caller can skip the bundles while the
# companion skill still installs. Never aborts the caller (the underlying
# prereq_ensure_apt calls _prereq_fail → exit, so each runs in a subshell).
ensure_bundle_prereqs() {
  local rc=0
  # One subshell for both ensures: it contains _prereq_fail's exit AND lets
  # _PREREQ_APT_UPDATED propagate between them (apt-get update runs once).
  ( prereq_ensure_apt "curl" curl curl "curl is needed for agent tool bundle setup"
    prereq_ensure_apt "jq"   jq   jq   "jq is needed to register MCP servers" ) || rc=$?
  [ "$rc" -eq 0 ]
}

# REA registration presence for a single tool (name "rea").
mcp_verify_rea_present() {
  local tool="$1"
  "mcp_verify_$tool" rea 2>/dev/null
}

# Tools where the REA bundle is already registered/installed (for --refresh-only).
rea_present_tools() {
  local out="" tool
  for tool in $TOOLS; do
    if mcp_verify_rea_present "$tool" || bundle_exists_one "$tool" reverse-engineer-anything; then
      out+="$tool "
    fi
  done
  printf '%s' "$out"
}

# Tools where a bundle <name> is already registered/installed.
bundle_present_tools() {
  local name="$1" out="" tool
  for tool in $TOOLS; do
    if "mcp_verify_$tool" "$name" 2>/dev/null || bundle_exists_one "$tool" "$name" 2>/dev/null; then
      out+="$tool "
    fi
  done
  printf '%s' "$out"
}

# ── Bundle ① — companion skill (returns status; no early exit) ──
companion_skill_run() {
  if [ "$NO_SKILL" = true ]; then
    log_info "Skipping companion skill (--no-skill)"
    return 0
  fi
  local NEW="" STALE="" CURRENT="" SKIPPED="" REFRESH_FAILED=0 tool dest
  for tool in $TOOLS; do
    if ! "skill_exists_$tool" 2>/dev/null; then
      # Refresh-only never adds the companion skill to a new agent.
      if [ "$REFRESH_ONLY" = true ]; then
        SKIPPED+="$tool "   # not installed, and refresh-only won't add it
      else
        NEW+="$tool "
      fi
    elif ! cmp -s "$(skill_source_path)" "$(skill_dest_path "$tool")"; then
      STALE+="$tool "
    else
      CURRENT+="$tool "
    fi
  done
  [ -n "$SKIPPED" ] && log_dim "Companion skill not installed (refresh-only never adds): $(echo "$SKIPPED" | tr ' ' ',' | sed 's/,$//')"
  [ -n "$CURRENT" ] && log_dim "Companion skill up to date: $(echo "$CURRENT" | tr ' ' ',' | sed 's/,$//')"

  if [ -n "$STALE" ]; then
    if [ "$DRY_RUN" = true ]; then
      log_info "Would refresh stale companion skill in: $(echo "$STALE" | tr ' ' ',' | sed 's/,$//')"
    else
      log_info "Refreshing stale companion skill in: $(echo "$STALE" | tr ' ' ',' | sed 's/,$//')"
      for tool in $STALE; do
        if dest=$("skill_install_$tool" 2>/dev/null) && cmp -s "$(skill_source_path)" "$(skill_dest_path "$tool")"; then
          log_ok "$tool: $dest"
        else
          log_error "$tool: companion skill refresh failed"
          REFRESH_FAILED=$((REFRESH_FAILED + 1))
        fi
      done
    fi
  fi

  if [ -z "$NEW" ]; then
    if [ "$DRY_RUN" = false ] && [ "$REFRESH_FAILED" -gt 0 ]; then
      log_error "Companion skill refresh completed with $REFRESH_FAILED failure(s)"
      return 1
    fi
    if [ "$DRY_RUN" = false ] && [ -n "$STALE" ]; then
      log_done "Companion skill refreshed"
    fi
    if [ -z "$STALE" ] && [ -z "$SKIPPED" ]; then
      log_ok "Companion skill already installed and up to date in all detected agents"
    fi
    return 0
  fi

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
      return 0
    fi
  fi

  if [ "$DRY_RUN" = true ]; then
    for tool in $NEW; do
      case "$tool" in
        opencode) log_dim "  Would install: ~/.config/opencode/skills/$SKILL_NAME/SKILL.md" ;;
        codex)    log_dim "  Would install: ~/.codex/skills/$SKILL_NAME/SKILL.md" ;;
        pi)       log_dim "  Would install: ~/.pi/agent/skills/$SKILL_NAME/SKILL.md" ;;
        claude)   log_dim "  Would install: ~/.claude/skills/$SKILL_NAME/SKILL.md" ;;
      esac
    done
    return 0
  fi

  for tool in $NEW; do
    case "$tool" in
      opencode) dest=$(skill_install_opencode); log_ok "opencode: $dest" ;;
      codex)    dest=$(skill_install_codex);    log_ok "codex: $dest" ;;
      pi)       dest=$(skill_install_pi);       log_ok "pi: $dest" ;;
      claude)   dest=$(skill_install_claude);   log_ok "claude: $dest" ;;
    esac
  done
  log_done "Companion skill installed — agents can now help operate the gateway"
  if [ "$REFRESH_FAILED" -gt 0 ]; then
    log_error "Companion skill refresh completed with $REFRESH_FAILED failure(s)"
    return 1
  fi
  return 0
}

# ── REA doctor: judge OUR clients' registrations; engines + overall warn-only ──
# `rea doctor --json` exits 1 whenever healthy:false — which is the NORMAL
# state on engine-less machines (Ghidra/IDA/JADX/Kuna are optional) and also
# flags unmanaged clients (vscode, copilot_cli). So: parse the JSON regardless
# of rc; only our installed clients' registration states matter.
rea_doctor_check() {
  command -v rea &>/dev/null || return 0
  local out rc client state bad
  out=$(timeout 120 rea doctor --json 2>/dev/null) && rc=0 || rc=$?
  if [ -z "$out" ] || ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    log_warn "  rea doctor did not return parseable diagnostics (rc=$rc)"
    return 0
  fi
  # Optional engines missing → warn only, never a failure.
  if printf '%s' "$out" | jq -r 'tostring' 2>/dev/null | grep -qiE '(ghidra|ida|jadx|kuna|missing_analysis_engine)'; then
    log_dim "  rea doctor: optional analysis engines not installed (normal — bring your own)"
  fi
  # Registration states for the clients we manage (detected tools → client ids).
  bad=""
  local client
  for tool in $TOOLS; do
    client=$(rea_client_id "$tool" 2>/dev/null) || continue
    state=$(printf '%s' "$out" | jq -r --arg c "$client" \
      '[.identity.registrations[]? | select(.client == $c)][0].state // "absent"' 2>/dev/null)
    if [ "$state" != "aligned" ]; then
      bad="$bad $client($state)"
    fi
  done
  if [ -n "$bad" ]; then
    log_warn "  rea doctor: registration not aligned:$bad"
    REA_FAIL=$((REA_FAIL + 1))
    return 0
  fi
  log_ok "  rea doctor: registrations aligned for: $(echo "$TOOLS" | tr ' ' ',' | sed 's/,$//')"
  return 0
}

# ── Bundle ② — REA (reverse-engineering MCP + skill) ──
bundle_rea_run() {
  local expected="$REA_AGENTS_VERSION"
  local rea_ver=""
  rea_ver=$(rea --version 2>/dev/null | sed 's/^v//' | tr -d '[:space:]' || true)

  if [ "$rea_ver" != "$expected" ]; then
    if [ "$DRY_RUN" = true ]; then
      log_info "  Would install: npm install -g rea-agents@$expected (current: ${rea_ver:-none})"
    else
      log_info "  Installing rea-agents@$expected ..."
      if npm_install_global "rea-agents@$expected"; then
        hash -r 2>/dev/null || true
        rea_ver=$(rea --version 2>/dev/null | sed 's/^v//' | tr -d '[:space:]' || true)
      else
        log_warn "  rea-agents install failed — skipping REA bundle"
        REA_FAIL=$((REA_FAIL + 1))
        REA_STATUS="install-failed"
        return 1
      fi
    fi
  else
    log_dim "  rea-agents $expected already installed"
  fi

  local tool cid
  for tool in $TOOLS; do
    cid=$(rea_client_id "$tool")
    # Gate the setup call: already registered + version pin matches → skip.
    # (Also in dry-run, so the printed plan matches what a real run would do.)
    if [ "$rea_ver" = "$expected" ] && mcp_verify_rea_present "$tool"; then
      log_dim "  REA: $tool already registered (current)"
      REA_RESULTS+="$tool=current "
      continue
    fi
    if [ "$DRY_RUN" = true ]; then
      log_dim "  Would run: rea setup --yes --client $cid --json  ($tool)"
      REA_RESULTS+="$tool=would-setup "
      continue
    fi
    # Re-assert forced PATH immediately before every rea setup call.
    export PATH="${NODE_MCP_BIN_DIR}:$PATH"
    hash -r 2>/dev/null || true
    if timeout 180 rea setup --yes --client "$cid" --json; then
      log_ok "  REA: registered for $tool"
      REA_RESULTS+="$tool=registered "
    else
      log_warn "  REA: setup failed for $tool"
      REA_FAIL=$((REA_FAIL + 1))
      REA_RESULTS+="$tool=failed "
    fi
  done

  [ "$DRY_RUN" = false ] && rea_doctor_check
  return 0
}

# ── Bundle ③ — drawio (@drawio/mcp MCP + vendored skill) ──
bundle_drawio_run() {
  local expected="$DRAWIO_MCP_VERSION"
  local prefix installed node_bin root entry tool oc_cmd
  prefix=$(npm config get prefix 2>/dev/null || true)

  installed=$(npm ls -g --depth=0 @drawio/mcp 2>/dev/null | sed -n 's/.*@drawio\/mcp@\([0-9.]*\).*/\1/p' | head -1 || true)
  if [ "$installed" != "$expected" ]; then
    if [ "$DRY_RUN" = true ]; then
      log_info "  Would install: npm install -g @drawio/mcp@$expected (current: ${installed:-none})"
    else
      log_info "  Installing @drawio/mcp@$expected ..."
      if ! npm_install_global "@drawio/mcp@$expected"; then
        log_warn "  @drawio/mcp install failed — skipping drawio bundle"
        DRAWIO_FAIL=$((DRAWIO_FAIL + 1))
        DRAWIO_STATUS="install-failed"
        return 1
      fi
      hash -r 2>/dev/null || true
    fi
  else
    log_dim "  @drawio/mcp $expected already installed"
  fi

  # Resolve absolute node + entry under the forced PATH. Registering
  # `command=<node> args=[<entry>]` (not npx) so the agent runtime doesn't
  # re-resolve node via PATH (which may be the too-old pi-node).
  node_bin=$(command -v node 2>/dev/null || true)
  # Dry-run never installs Node or forces PATH; still show the node a real
  # run would pin (system NodeSource node when it meets the floor).
  if [ "$DRY_RUN" = true ]; then
    if [ -n "${NODE_MCP_BIN_DIR:-}" ] && [ -x "$NODE_MCP_BIN_DIR/node" ]; then
      node_bin="$NODE_MCP_BIN_DIR/node"
    elif [ -x /usr/bin/node ] && version_ge "$(/usr/bin/node --version 2>/dev/null | sed 's/^v//' || true)" "$NODE_MCP_MIN_VERSION"; then
      node_bin="/usr/bin/node"
    fi
  fi
  # Resolve npm from the same bin dir as node_bin so the printed plan matches
  # what a real (PATH-forced) run registers. /usr/bin/npm is an `env node`
  # script — without forcing PATH for the subcommand it runs under a shadowing
  # node (e.g. pi-node) and reports that node's prefix as the global root.
  if [ -n "$node_bin" ] && [ -x "$(dirname "$node_bin")/npm" ]; then
    root=$(PATH="$(dirname "$node_bin"):$PATH" "$(dirname "$node_bin")/npm" root -g 2>/dev/null || true)
  else
    root=$(npm root -g 2>/dev/null || true)
  fi
  entry="${root}/@drawio/mcp/src/index.js"
  if [ "$DRY_RUN" = false ] && [ ! -f "$entry" ] && [ -n "$prefix" ]; then
    entry="$prefix/lib/node_modules/@drawio/mcp/src/index.js"
  fi
  # Fallback: derive from the package's declared bin if the layout differs.
  if [ "$DRY_RUN" = false ] && [ ! -f "$entry" ] && [ -n "$root" ] && [ -d "$root/@drawio/mcp" ]; then
    local binrel
    binrel=$(npm view @drawio/mcp bin --json 2>/dev/null | jq -r 'to_entries[0].value // empty' 2>/dev/null || true)
    [ -n "$binrel" ] && entry="$root/@drawio/mcp/$binrel"
  fi
  # Gate: never register a command/entry pair whose entry does not exist —
  # a present-but-dead registration is worse than none (H3 can't catch it).
  if [ "$DRY_RUN" = false ] && [ ! -f "$entry" ]; then
    log_warn "  drawio entry not found after install ($entry) — skipping drawio registration"
    DRAWIO_FAIL=$((DRAWIO_FAIL + 1))
    return 0
  fi

  for tool in $TOOLS; do
    if [ "$DRY_RUN" = true ]; then
      log_dim "  [$tool] would register MCP 'drawio': command=$node_bin entry=$entry"
      log_dim "  [$tool] would install skill → $(bundle_dest_dir "$tool" drawio)"
      DRAWIO_RESULTS+="$tool=would-register "
      continue
    fi
    case "$tool" in
      opencode)
        oc_cmd=$(jq -Rn --arg a "$node_bin" --arg b "$entry" '[$a,$b]')
        mcp_register_opencode drawio "$oc_cmd" || true
        ;;
      codex)    mcp_register_codex drawio "$node_bin" "$entry" || true ;;
      claude)   mcp_register_claude drawio "$node_bin" "$entry" || true ;;
      pi)       mcp_register_pi drawio "$node_bin" "$entry" || true ;;
    esac
    # Post-write verification.
    if "mcp_verify_$tool" drawio 2>/dev/null; then
      log_ok "  drawio: verified registration for $tool"
      DRAWIO_RESULTS+="$tool=registered "
    else
      log_warn "  drawio: registration missing after write for $tool"
      DRAWIO_FAIL=$((DRAWIO_FAIL + 1))
      DRAWIO_RESULTS+="$tool=verify-failed "
    fi
    # Vendored skill (per-file drift detection).
    if bundle_is_current "$tool" drawio "$PROJECT_DIR/skills/drawio"; then
      log_dim "  drawio skill: $tool current"
      DRAWIO_RESULTS+="$tool-skill=current "
    elif dest=$(bundle_install_one "$tool" drawio "$PROJECT_DIR/skills/drawio" 2>/dev/null) \
         && bundle_is_current "$tool" drawio "$PROJECT_DIR/skills/drawio"; then
      log_ok "  drawio skill: installed for $tool → $dest"
      DRAWIO_RESULTS+="$tool-skill=installed "
    else
      log_warn "  drawio skill: install failed for $tool"
      DRAWIO_FAIL=$((DRAWIO_FAIL + 1))
      DRAWIO_RESULTS+="$tool-skill=failed "
    fi
  done
  return 0
}

# ── Print the selected scope ──
print_scope() {
  local yes="${C_GREEN}yes${C_RESET}" no="${C_DIM}no${C_RESET}"
  log_info "Bundle scope:"
  printf "    ${C_DIM}%-28s${C_RESET} %s\n" "Companion skill:" "$([ "$DO_SKILL" = true ] && echo "$yes" || echo "$no")"
  printf "    ${C_DIM}%-28s${C_RESET} %s\n" "REA bundle (MCP + skill):" "$([ "$DO_REA" = true ] && echo "$yes" || echo "$no")"
  printf "    ${C_DIM}%-28s${C_RESET} %s\n" "drawio bundle (MCP + skill):" "$([ "$DO_DRAWIO" = true ] && echo "$yes" || echo "$no")"
  log_dim "  Tools: $(echo "$TOOLS" | tr ' ' ',' | sed 's/,$//')"
  if [ "$DO_REA" = true ] || [ "$DO_DRAWIO" = true ]; then
    log_dim "  Node >= $NODE_MCP_MIN_VERSION will be ensured (installs Node 22 if missing)"
  fi
}

# ── Interactive bundle menu (no --yes) ──
interactive_bundle_menu() {
  local choice defs="" d1 d2 d3 l1="" l2="" l3=""
  d1=$([ "$NO_SKILL" = false ] && echo 1 || echo 0)
  d2=$([ "$NO_REA" = false ] && echo 1 || echo 0)
  d3=$([ "$NO_DRAWIO" = false ] && echo 1 || echo 0)
  [ "$d1" = 1 ] && defs+="1,"; [ "$d2" = 1 ] && defs+="2,"; [ "$d3" = 1 ] && defs+="3,"
  defs="${defs%,}"
  # Flag-locked components cannot be enabled here — mark them unavailable.
  [ "$NO_SKILL" = true ]  && l1=" ${C_DIM}(disabled by --no-skill)${C_RESET}"
  [ "$NO_REA" = true ]    && l2=" ${C_DIM}(disabled by --no-rea)${C_RESET}"
  [ "$NO_DRAWIO" = true ] && l3=" ${C_DIM}(disabled by --no-drawio)${C_RESET}"
  echo ""
  echo -e "  ${C_BOLD}1)${C_RESET} Companion skill (gateway operations) ${C_DIM}[default]${C_RESET}${l1}"
  echo -e "  ${C_BOLD}2)${C_RESET} REA bundle — reverse-engineering MCP + skill ${C_DIM}[default]${C_RESET}${l2}"
  echo -e "  ${C_BOLD}3)${C_RESET} drawio bundle — diagramming MCP + skill ${C_DIM}[default]${C_RESET}${l3}"
  echo -e "  ${C_DIM}Or combine: 1,3${C_RESET}"
  echo -e "  ${C_DIM}Tools: $(echo "$TOOLS" | tr ' ' ',' | sed 's/,$//')${C_RESET}"
  echo -ne "  ${C_BOLD}Choice${C_RESET} ${C_DIM}[${defs:-none}]${C_RESET}: "
  read -r choice < /dev/tty || choice=""
  choice="${choice//[[:space:]]/}"
  [ -z "$choice" ] && choice="$defs"
  [ -z "$choice" ] && return 0   # Enter at [none] = decline all components (caller still shows scope + confirm)
  DO_SKILL=false; DO_REA=false; DO_DRAWIO=false
  local opt
  IFS=',' read -ra _opts <<< "$choice"
  for opt in "${_opts[@]}"; do
    case "$opt" in
      1) DO_SKILL=true ;;
      2) DO_REA=true ;;
      3) DO_DRAWIO=true ;;
      *) log_warn "Ignoring invalid bundle choice: $opt" ;;
    esac
  done
  # CLI flags win — a flag-locked component stays off even if selected above.
  [ "$NO_SKILL" = true ]  && DO_SKILL=false
  [ "$NO_REA" = true ]    && DO_REA=false
  [ "$NO_DRAWIO" = true ] && DO_DRAWIO=false
  # Return 0 explicitly — a short-circuited trailing test would otherwise
  # make the function return 1 and kill the script under `set -e`.
  return 0
}

# ════════════════════════════════════════════════════════════════
# Main flow
# ════════════════════════════════════════════════════════════════
if [ "$REFRESH_ONLY" = true ]; then
  # ── Refresh-only: touch only already-installed bundles, never add new ones ──
  log_info "Refresh-only mode: refreshing already-installed bundles (no new additions)"

  # Ensure curl+jq before the refresh work, symmetric with the normal path.
  # Soft-fail (declined/failed install) so the companion skill still runs.
  BUNDLE_PREREQS_OK=true
  if [ "$DRY_RUN" = true ]; then
    log_dim "Dry-run: would ensure curl/jq (no install)"
  elif ! ensure_bundle_prereqs; then
    log_warn "curl/jq unavailable — skipping bundle refresh"
    BUNDLE_PREREQS_OK=false
  fi

  companion_skill_run || COMP_FAILED=1

  if [ "$BUNDLE_PREREQS_OK" = true ]; then
    REA_TOOLS=$(rea_present_tools)
    DRAW_TOOLS=$(bundle_present_tools drawio)
    if [ -n "$REA_TOOLS" ] || [ -n "$DRAW_TOOLS" ]; then
      if [ "$DRY_RUN" = true ] || setup_node_for_bundles; then
        _saved_tools="$TOOLS"
        if [ -n "$REA_TOOLS" ]; then
          TOOLS="$REA_TOOLS"; bundle_rea_run || true
        fi
        if [ -n "$DRAW_TOOLS" ]; then
          TOOLS="$DRAW_TOOLS"; bundle_drawio_run || true
        fi
        TOOLS="$_saved_tools"
      else
        log_warn "Node >= $NODE_MCP_MIN_VERSION unavailable — skipping bundle refresh"
      fi
    else
      log_dim "No agent bundles installed yet — nothing to refresh"
    fi
  fi
else
  # ── Normal mode: menu (interactive) or defaults (--yes/non-interactive) ──
  DO_SKILL=true; DO_REA=true; DO_DRAWIO=true
  BUNDLES_SOFT_FAILED=false
  [ "$NO_SKILL" = true ]  && DO_SKILL=false
  [ "$NO_REA" = true ]    && DO_REA=false
  [ "$NO_DRAWIO" = true ] && DO_DRAWIO=false

  if [ "$ASSUME_YES" = false ] && is_interactive; then
    while true; do
      interactive_bundle_menu
      echo ""
      print_scope
      echo ""
      if prompt_yesno "Proceed with this selection?" y; then
        break
      fi
      log_info "Let's try again."
    done
  else
    echo ""
    print_scope
  fi

  # CLI flags always win — re-apply after any interactive menu selection.
  [ "$NO_SKILL" = true ]  && DO_SKILL=false
  [ "$NO_REA" = true ]    && DO_REA=false
  [ "$NO_DRAWIO" = true ] && DO_DRAWIO=false

  # Node handling: only when a bundle will run. Soft-fail skips both bundles.
  if [ "$DO_REA" = true ] || [ "$DO_DRAWIO" = true ]; then
    if [ "$DRY_RUN" = true ]; then
      log_dim "Dry-run: would ensure curl/jq + Node >= $NODE_MCP_MIN_VERSION (no install)"
    elif ! ensure_bundle_prereqs; then
      # Declined/failed curl+jq install — soft-fail the bundles (companion still installs).
      log_warn "curl/jq unavailable — skipping REA + drawio bundles"
      DO_REA=false
      DO_DRAWIO=false
      BUNDLES_SOFT_FAILED=true
    elif ! setup_node_for_bundles; then
      log_warn "Node >= $NODE_MCP_MIN_VERSION unavailable — skipping REA + drawio bundles"
      DO_REA=false
      DO_DRAWIO=false
      BUNDLES_SOFT_FAILED=true
    fi
  fi

  # Companion skill failure = hard fail (status quo).
  if [ "$DO_SKILL" = true ]; then
    companion_skill_run || COMP_FAILED=1
  elif [ "$NO_SKILL" = true ]; then
    log_info "Skipping companion skill (--no-skill)"
  else
    log_info "Skipping companion skill (deselected in menu)"
  fi

  # Bundle order invariant: REA first (writes shared configs like pi mcp.json),
  # then drawio (merges into the same files).
  if [ "$DO_REA" = true ]; then
    bundle_rea_run || true
  elif [ "$NO_REA" = true ]; then
    log_info "Skipping REA bundle (--no-rea)"
  elif [ "$BUNDLES_SOFT_FAILED" = false ]; then
    log_info "Skipping REA bundle (deselected in menu)"
  fi
  if [ "$DO_DRAWIO" = true ]; then
    bundle_drawio_run || true
  elif [ "$NO_DRAWIO" = true ]; then
    log_info "Skipping drawio bundle (--no-drawio)"
  elif [ "$BUNDLES_SOFT_FAILED" = false ]; then
    log_info "Skipping drawio bundle (deselected in menu)"
  fi
fi

# ── Per-bundle × per-tool summary ──
echo ""
log_info "Agent bundle results:"
if [ -n "$REA_RESULTS" ]; then
  log_dim "  REA:    $(echo "$REA_RESULTS" | sed 's/ $//')"
elif [ "$REFRESH_ONLY" = false ] && [ "$DO_REA" != true ]; then
  log_dim "  REA:    skipped"
fi
if [ -n "$DRAWIO_RESULTS" ]; then
  log_dim "  drawio: $(echo "$DRAWIO_RESULTS" | sed 's/ $//')"
elif [ "$REFRESH_ONLY" = false ] && [ "$DO_DRAWIO" != true ]; then
  log_dim "  drawio: skipped"
fi
[ "$REA_FAIL" -gt 0 ]    && log_warn "REA bundle issues: $REA_FAIL"
[ "$DRAWIO_FAIL" -gt 0 ] && log_warn "drawio bundle issues: $DRAWIO_FAIL"

# ── Exit policy ──
# Companion skill failure → hard fail. Bundle failures → exit 0 unless --strict.
EXIT_RC=0
if [ "$COMP_FAILED" -ne 0 ]; then
  EXIT_RC=1
fi
if [ "$STRICT" = true ] && { [ "$REA_FAIL" -gt 0 ] || [ "$DRAWIO_FAIL" -gt 0 ]; }; then
  EXIT_RC=1
fi
exit "$EXIT_RC"
