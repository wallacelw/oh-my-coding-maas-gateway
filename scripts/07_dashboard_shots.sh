#!/usr/bin/env bash
set -euo pipefail

# ─── 07_dashboard_shots.sh — Grafana visual verification shots (maintenance) ──
#
# Domain:        Grafana dashboard (visual verification)
# Order:         maintenance — not part of the install pipeline (like update.sh)
# Optional:      n/a (run manually after any dashboard change)
# Description:   Capture the rendered Grafana dashboard as PNG screenshots
#                via helpers/grafana_shots.py: full.png (entire dashboard)
#                plus band-NN.png (1100px vertical bands sized for
#                vision-model review). Run after any change to
#                configs/grafana/dashboards/main.json, then have a
#                vision-capable agent review the bands.
# Inputs:        .env (GRAFANA_ADMIN_PASSWORD), running Grafana
# Outputs:       $OUT_DIR/full.png, $OUT_DIR/band-NN.png (default
#                /tmp/dashboard-shots)
# Standalone:    yes — ./scripts/07_dashboard_shots.sh
#
# Usage:
#   ./07_dashboard_shots.sh                     # capture to /tmp/dashboard-shots
#   ./07_dashboard_shots.sh --out=DIR           # custom output directory
#   ./07_dashboard_shots.sh --dry-run           # show what would be captured
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DASHBOARD_JSON="$PROJECT_DIR/configs/grafana/dashboards/main.json"
GRAFANA_URL="http://127.0.0.1:3000"

source "$SCRIPT_DIR/helpers/common.sh"

usage() {
  cat <<'EOF'
Usage: ./scripts/07_dashboard_shots.sh [--out=DIR] [--dry-run]

Capture the rendered Grafana dashboard as PNG screenshots for visual
verification: full.png (entire dashboard) plus band-NN.png (1100px
vertical bands sized for vision-model review).

  --out=DIR     Output directory (default /tmp/dashboard-shots)
  --dry-run     Show what would be captured; no prerequisites required

Requires python3 + playwright + chromium and a running Grafana.
One-time setup:
  pip3 install --user --break-system-packages playwright && python3 -m playwright install chromium
EOF
}

# ── Parse args ──
OUT_DIR="/tmp/dashboard-shots"
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    --out=*)    OUT_DIR="${arg#--out=}" ;;
    --dry-run)  DRY_RUN=true ;;
    --help|-h)  usage; exit 0 ;;
    *)          log_error "Unknown flag: $arg"; exit 1 ;;
  esac
done

# Expand a leading tilde so --out=~/dir resolves like a shell path.
OUT_DIR="${OUT_DIR/#\~/$HOME}"

# --out= with an empty value would write to the CWD — reject it.
if [ -z "$OUT_DIR" ]; then
  log_error "--out requires a directory path."
  exit 1
fi

log_step "Step 07 — Dashboard visual verification shots"

# ── Prerequisites ──
# Gather every status first so --dry-run can report the full capability
# picture; normal mode below fails on the first missing prerequisite.
HAVE_PYTHON=false
HAVE_PLAYWRIGHT=false
HAVE_CHROMIUM=false
HAVE_JQ=false
HAVE_GRAFANA=false
HAVE_PASSWORD=false
DASHBOARD_UID=""

if command -v python3 >/dev/null 2>&1; then
  HAVE_PYTHON=true
  if python3 -c "import playwright" >/dev/null 2>&1; then
    HAVE_PLAYWRIGHT=true
  fi
fi
if ls "$HOME/.cache/ms-playwright" 2>/dev/null | grep -q chromium; then
  HAVE_CHROMIUM=true
fi
if command -v jq >/dev/null 2>&1; then
  HAVE_JQ=true
fi

# Load .env exactly like 04_validate.sh: source_env exports every variable,
# so GRAFANA_ADMIN_PASSWORD reaches grafana_shots.py through the environment
# without ever appearing in a command line or log line.
source_env "$PROJECT_DIR"
if [ -n "${GRAFANA_ADMIN_PASSWORD:-}" ]; then
  HAVE_PASSWORD=true
fi

if curl -sf -m 5 "$GRAFANA_URL/api/health" >/dev/null 2>&1; then
  HAVE_GRAFANA=true
fi

if [ -f "$DASHBOARD_JSON" ]; then
  DASHBOARD_UID=$(jq -r '.uid // empty' "$DASHBOARD_JSON" 2>/dev/null || true)
fi

# ── Dry-run: show what would be captured plus capability status ──
if [ "$DRY_RUN" = true ]; then
  log_info "Would capture: $GRAFANA_URL (UID: ${DASHBOARD_UID:-(missing)})"
  log_dim "  Output: $OUT_DIR — full.png + band-NN.png"
  if [ "$HAVE_PYTHON" = true ] && [ "$HAVE_PLAYWRIGHT" = true ] && [ "$HAVE_CHROMIUM" = true ]; then
    log_dim "  Capture tooling: python3 + playwright + chromium available"
  elif [ "$HAVE_PLAYWRIGHT" = true ]; then
    log_dim "  Capture tooling: chromium missing — python3 -m playwright install chromium"
  else
    log_dim "  Capture tooling: missing — pip3 install --user --break-system-packages playwright && python3 -m playwright install chromium"
  fi
  if [ "$HAVE_GRAFANA" = true ]; then
    log_dim "  Grafana: reachable"
  else
    log_dim "  Grafana: not reachable — start the stack: ./scripts/02_litellm.sh"
  fi
  if [ "$HAVE_PASSWORD" = true ]; then
    log_dim "  Admin password: set"
  else
    log_dim "  Admin password: missing — create .env: ./scripts/01_env.sh"
  fi
  exit 0
fi

# ── Normal mode: fail on the first missing prerequisite, with the fix ──
if [ "$HAVE_PYTHON" != true ]; then
  log_error "python3 not found — install it first (e.g. sudo apt install python3)"
  exit 1
fi
if [ "$HAVE_PLAYWRIGHT" != true ]; then
  log_error "playwright not installed — fix: pip3 install --user --break-system-packages playwright && python3 -m playwright install chromium"
  exit 1
fi
# The playwright-module check above already exited with the pip3 fix, so
# here the module is importable and only the browser download is missing.
if [ "$HAVE_CHROMIUM" != true ]; then
  log_error "playwright chromium not installed — fix: python3 -m playwright install chromium"
  exit 1
fi
if [ "$HAVE_JQ" != true ]; then
  log_error "jq not found — fix: install jq (e.g. sudo apt install jq); it extracts the dashboard UID from main.json"
  exit 1
fi
if [ "$HAVE_PASSWORD" != true ]; then
  log_error "GRAFANA_ADMIN_PASSWORD not set — fix: create .env first (./scripts/01_env.sh)"
  exit 1
fi
if [ "$HAVE_GRAFANA" != true ]; then
  log_error "Grafana not reachable at $GRAFANA_URL — fix: start the stack (./scripts/02_litellm.sh)"
  exit 1
fi
if [ -z "$DASHBOARD_UID" ]; then
  log_error "Dashboard UID is empty — fix: check .uid in configs/grafana/dashboards/main.json"
  exit 1
fi

# ── Capture ──
# GRAFANA_ADMIN_PASSWORD is already exported by source_env above.
export GRAFANA_SHOTS_URL="$GRAFANA_URL"
export GRAFANA_SHOTS_UID="$DASHBOARD_UID"
export GRAFANA_SHOTS_OUT="$OUT_DIR"

log_info "Capturing dashboard screenshots (takes ~30s, longer if dropped queries force extra refresh waits)..."
if ! python3 "$SCRIPT_DIR/helpers/grafana_shots.py"; then
  log_error "Screenshot capture failed — see the output above (debug.png in $OUT_DIR shows the failed render, if any)"
  exit 1
fi

log_ok "Screenshots written to $OUT_DIR (full.png + band-NN.png)"
log_dim "  Next: feed the band images to a vision-capable agent for review — see SKILL.md 'Visual dashboard verification'"
