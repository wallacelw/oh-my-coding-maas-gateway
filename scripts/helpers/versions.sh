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
# Sourced by: bootstrap.sh (helpers/common.sh must be sourced first —
# C_BOLD/C_DIM/C_RESET colors come from there).
#
# Every version fetch is failure-safe (2>/dev/null + || fallbacks):
# a missing tool or file yields an empty value, printed as a dim
# "(not installed)" — never a set -e trap.

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
  v_slim=$(grep 'SLIM_VERSION=' "$project_dir/scripts/03a_opencode.sh" 2>/dev/null | head -1 | sed 's/.*="\([^"]*\)".*/\1/' || true)

  # Docker image tags pinned in docker-compose.yml
  v_litellm=$(grep 'image:.*litellm:' "$compose_file" 2>/dev/null | head -1 | sed 's/.*litellm://' || true)
  v_postgres=$(grep 'image:.*postgres:' "$compose_file" 2>/dev/null | head -1 | sed 's/.*postgres://' || true)
  v_prometheus=$(grep 'image:.*prom/prometheus:' "$compose_file" 2>/dev/null | head -1 | sed 's/.*prom\/prometheus://' || true)
  v_grafana=$(grep 'image:.*grafana/grafana:' "$compose_file" 2>/dev/null | head -1 | sed 's|.*grafana/grafana:||' || true)

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
