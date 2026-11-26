#!/usr/bin/env bash
# helpers/versions.sh — Component version display helpers
#
# Provides:
#   show_installed_versions <project_dir>
#     Print installed/pinned versions of every component as an aligned
#     table (coding tools from PATH, slim plugin + Docker image tags
#     from repo files):
#       project, opencode, oh-my-opencode-slim, codex, claude-code, pi,
#       litellm, postgresql, prometheus, grafana
#
# Sourced by: bootstrap.sh, 02_litellm.sh, 03d_pi.sh, 04_skills_mcps.sh,
# 05_validate.sh, update.sh
# (helpers/common.sh must be sourced first —
# C_BOLD/C_DIM/C_RESET colors come from there).
#
# Every version fetch is failure-safe (2>/dev/null + || fallbacks):
# a missing tool or file yields an empty value, printed as a dim
# "(not installed)" — never a set -e trap.

# ── Agent tool bundle pins ───────────────────────────────────
# Pinned versions for the optional-but-default-on agent tool bundles
# installed by scripts/04_skills_mcps.sh and checked by scripts/05_validate.sh.
# NOTE: rea-agents stays at 6.9.0 while opencode is on the v1 host line —
# 6.10.x `rea setup --client opencode` writes the v2 `mcp.servers` config
# shape, which opencode v1 cannot read. Bump together with the opencode
# v2 migration.
REA_AGENTS_VERSION="6.9.0"
DRAWIO_MCP_VERSION="1.13.1"
# REA (rea-agents) requires Node >= 22.23.4; the drawio stdio server runs on
# the same resolved node. Both bundles share this floor.
NODE_MCP_MIN_VERSION="22.23.4"

# ── Repo file pin getters ────────────────────────────────────
# Single-source-of-truth readers shared by show_installed_versions and by
# 02_litellm.sh / 05_validate.sh / update.sh, so each pin is parsed in exactly
# one place.

# slim_version <project_dir>
#   Print the SLIM_VERSION pinned in scripts/03a_opencode.sh.
slim_version() {
  local project_dir="${1:-${PROJECT_DIR:-.}}"
  grep 'SLIM_VERSION=' "$project_dir/scripts/03a_opencode.sh" 2>/dev/null \
    | head -1 | sed 's/.*="\([^"]*\)".*/\1/' || true
}

# compose_image_tag <service> [compose_file]
#   Print the image tag pinned in docker-compose.yml for one of
#   litellm|postgres|prometheus|grafana, exactly as written (leading "v"
#   preserved — e.g. v1.109.4, 16-alpine, v3.16.0, 13.3.1).
compose_image_tag() {
  local svc="$1" compose_file="${2:-${PROJECT_DIR:-.}/docker-compose.yml}"
  case "$svc" in
    litellm)    grep 'image:.*litellm:' "$compose_file" 2>/dev/null | head -1 | sed 's/.*litellm://' || true ;;
    postgres)   grep 'image:.*postgres:' "$compose_file" 2>/dev/null | head -1 | sed 's/.*postgres://' || true ;;
    prometheus) grep 'image:.*prom/prometheus:' "$compose_file" 2>/dev/null | head -1 | sed 's/.*prom\/prometheus://' || true ;;
    grafana)    grep 'image:.*grafana/grafana:' "$compose_file" 2>/dev/null | head -1 | sed 's|.*grafana/grafana:||' || true ;;
    *)          return 1 ;;
  esac
}

# ── Print one aligned table row ──
# Empty value → dim "(not installed)".
# Usage: _version_row "label" "value"
_version_row() {
  local label="$1" value="$2"
  if [ -z "$value" ]; then
    value="${C_DIM}(not installed)${C_RESET}"
  fi
  printf "    ${C_DIM}%-22s${C_RESET} %s\n" "$label" "$value"
}

# Print installed/pinned versions of every component as an aligned table.
# Usage: show_installed_versions "$PROJECT_DIR"
show_installed_versions() {
  local project_dir="$1"
  local compose_file="$project_dir/docker-compose.yml"
  local v_project v_opencode v_slim v_codex v_claude v_pi
  local v_litellm v_postgres v_prometheus v_grafana

  # project — first line of VERSION, shown in the v-prefixed form (v1.22.0)
  v_project=$(head -1 "$project_dir/VERSION" 2>/dev/null || true)
  if [ -n "$v_project" ]; then
    v_project="v${v_project#v}"
  fi

  # Coding tools (CLI on PATH)
  v_opencode=$(opencode --version 2>/dev/null || echo "")
  v_codex=$(codex --version 2>/dev/null | sed 's/codex-cli //' || echo "")
  v_claude=$(claude --version 2>/dev/null | sed 's/ (Claude Code)//' || echo "")
  v_pi=$(pi --version 2>/dev/null || echo "")

  # oh-my-opencode-slim — pinned in scripts/03a_opencode.sh
  v_slim=$(slim_version "$project_dir")

  # Docker image tags pinned in docker-compose.yml
  v_litellm=$(compose_image_tag litellm "$compose_file")
  v_postgres=$(compose_image_tag postgres "$compose_file")
  v_prometheus=$(compose_image_tag prometheus "$compose_file")
  v_grafana=$(compose_image_tag grafana "$compose_file")

  # PostgreSQL tag is pinned (never floating) — annotate it
  if [ -n "$v_postgres" ]; then
    v_postgres="$v_postgres ${C_DIM}(pinned)${C_RESET}"
  fi

  echo ""
  echo -e "  ${C_BOLD}Component versions:${C_RESET}"
  _version_row "project"              "$v_project"
  _version_row "opencode"             "$v_opencode"
  _version_row "oh-my-opencode-slim"  "$v_slim"
  _version_row "codex"                "$v_codex"
  _version_row "claude-code"          "$v_claude"
  _version_row "pi"                   "$v_pi"
  _version_row "litellm"              "$v_litellm"
  _version_row "postgresql"           "$v_postgres"
  _version_row "prometheus"           "$v_prometheus"
  _version_row "grafana"              "$v_grafana"
}
