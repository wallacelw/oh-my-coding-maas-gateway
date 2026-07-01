#!/usr/bin/env bash
set -euo pipefail

# ─── 01_env.sh — Environment & secrets (pipeline step 01, core) ───────────────
#
# Domain:        Environment & secrets
# Order:         01 (first — everything needs .env)
# Optional:      no (core, always runs)
# Description:   Generate/update .env with immutable secrets, Huawei MaaS API
#                keys, and endpoint URLs. Auto-generates and preserves secrets
#                (idempotent); collects the MaaS key from the HUAWEI_MAAS_API_KEY
#                env var or an interactive prompt. Configures git hooks to block
#                committing secrets.
# Inputs:        HUAWEI_MAAS_API_KEY (env var or prompt),
#                HUAWEI_MAAS_API_KEY_COUNT + HUAWEI_MAAS_API_KEY_1..N (env vars
#                or prompt), --force (regenerate secrets)
# Outputs:       .env (chmod 600), git hooks configured
# Standalone:    yes — ./scripts/01_env.sh
# ──────────────────────────────────────────────────────────────────────────────

# ── Resolve project root ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_EXAMPLE="$PROJECT_DIR/configs/.env.template"
ENV_FILE="$PROJECT_DIR/.env"

# ── Helpers ──
source "$SCRIPT_DIR/helpers/prereqs.sh"
source "$SCRIPT_DIR/helpers/common.sh"
prereq_ensure_apt "python3" python3 python3
prereq_ensure_apt "git"     git     git

generate_secret() { python3 -c 'import secrets; print(secrets.token_urlsafe(32))'; }
generate_master_key() { echo "sk-$(generate_secret)"; }

# ── Parse args ──
FORCE=false
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    *) echo "Usage: $0 [--force]" >&2; exit 1 ;;
  esac
done

echo "══════════════════════════════════════════════════════"
echo "  Step 01 — Environment & secrets"
echo "══════════════════════════════════════════════════════"
echo ""

# ── Check env template exists ──
if [ ! -f "$ENV_EXAMPLE" ]; then
  echo "ERROR: $ENV_EXAMPLE not found." >&2
  exit 1
fi

# ── Read existing secrets to preserve (idempotent) ──
EXISTING_MASTER_KEY=""
EXISTING_SALT_KEY=""
EXISTING_DB_PASSWORD=""
EXISTING_GRAFANA_PASSWORD=""
EXISTING_PROM_RETENTION=""
EXISTING_MAAS_BASE=""
EXISTING_MAAS_ANTHROPIC_BASE=""
if [ -f "$ENV_FILE" ]; then
  EXISTING_MASTER_KEY="$(grep -oP '^LITELLM_MASTER_KEY="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
  EXISTING_SALT_KEY="$(grep -oP '^LITELLM_SALT_KEY="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
  EXISTING_DB_PASSWORD="$(grep -oP '^DB_PASSWORD="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
  EXISTING_GRAFANA_PASSWORD="$(grep -oP '^GRAFANA_ADMIN_PASSWORD="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
  EXISTING_PROM_RETENTION="$(grep -oP '^PROMETHEUS_RETENTION="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
  EXISTING_MAAS_BASE="$(grep -oP '^HUAWEI_MAAS_API_BASE="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
  EXISTING_MAAS_ANTHROPIC_BASE="$(grep -oP '^HUAWEI_MAAS_ANTHROPIC_API_BASE="?\K[^"]+' "$ENV_FILE" 2>/dev/null || true)"
fi

# ── Generate / preserve secrets ──
# Immutable secrets are preserved on re-run (changing them breaks existing
# deployments). --force regenerates all (for key rotation).
MASTER_KEY="$(generate_master_key)"
SALT_KEY="$(generate_secret)"
DB_PASSWORD="$(generate_secret)"
GRAFANA_PASSWORD="$(generate_secret)"
PROM_RETENTION="30d"
MAAS_API_BASE="https://api-ap-southeast-1.modelarts-maas.com/openai/v1"
MAAS_ANTHROPIC_BASE="https://api-ap-southeast-1.modelarts-maas.com/anthropic"

if [ "$FORCE" != true ]; then
  [ -n "$EXISTING_MASTER_KEY" ]        && MASTER_KEY="$EXISTING_MASTER_KEY"
  [ -n "$EXISTING_SALT_KEY" ]          && SALT_KEY="$EXISTING_SALT_KEY"
  [ -n "$EXISTING_DB_PASSWORD" ]       && DB_PASSWORD="$EXISTING_DB_PASSWORD"
  [ -n "$EXISTING_GRAFANA_PASSWORD" ]  && GRAFANA_PASSWORD="$EXISTING_GRAFANA_PASSWORD"
  [ -n "$EXISTING_PROM_RETENTION" ]    && PROM_RETENTION="$EXISTING_PROM_RETENTION"
  [ -n "$EXISTING_MAAS_BASE" ]         && MAAS_API_BASE="$EXISTING_MAAS_BASE"
  [ -n "$EXISTING_MAAS_ANTHROPIC_BASE" ] && MAAS_ANTHROPIC_BASE="$EXISTING_MAAS_ANTHROPIC_BASE"
  [ -f "$ENV_FILE" ] && echo "  Preserving existing secrets (idempotent). Use --force to regenerate."
fi

# ── Collect MaaS API key (env var or prompt) ──
MAAS_API_KEY="${HUAWEI_MAAS_API_KEY:-}"
if [ -n "$MAAS_API_KEY" ]; then
  echo "  ✓ HUAWEI_MAAS_API_KEY set from environment"
elif [ -t 0 ]; then
  echo ""
  echo "  Enter Huawei MaaS API key (region ap-southeast-1):"
  read -r MAAS_API_KEY < /dev/tty
else
  echo "ERROR: HUAWEI_MAAS_API_KEY is required. Set it as an env var or run interactively." >&2
  exit 1
fi

# ── Collect extra MaaS keys for load balancing (env vars or prompt) ──
EXTRA_KEYS=()
if [ -n "${HUAWEI_MAAS_API_KEY_COUNT:-}" ] && [ "${HUAWEI_MAAS_API_KEY_COUNT:-1}" -gt 1 ]; then
  for i in $(seq 1 $((HUAWEI_MAAS_API_KEY_COUNT - 1))); do
    VAR="HUAWEI_MAAS_API_KEY_$i"
    VAL="${!VAR:-}"
    [ -n "$VAL" ] && EXTRA_KEYS+=("$VAL")
  done
  [ ${#EXTRA_KEYS[@]} -gt 0 ] && echo "  ✓ ${#EXTRA_KEYS[@]} extra MaaS key(s) from environment"
elif [ -t 0 ]; then
  echo ""
  echo "  ── Additional MaaS API keys for load balancing ──"
  echo "  Each extra key multiplies effective RPM/TPM across all models."
  echo "  Press Enter without typing anything to skip (0 extra keys)."
  echo ""
  while true; do
    EXTRA_NUM=$(( ${#EXTRA_KEYS[@]} + 1 ))
    read -r -p "  Enter MaaS API key #$EXTRA_NUM (or press Enter to finish): " extra_key < /dev/tty
    [ -z "$extra_key" ] && break
    EXTRA_KEYS+=("$extra_key")
    echo "  ✓ Extra key #$EXTRA_NUM added"
  done
fi

KEY_COUNT=$(( 1 + ${#EXTRA_KEYS[@]} ))

# ── Validate ──
ERRORS=0
if [[ ! "$MASTER_KEY" == sk-* ]]; then
  echo "ERROR: LITELLM_MASTER_KEY must start with 'sk-'." >&2
  ERRORS=$((ERRORS + 1))
fi
if [ -z "$MAAS_API_KEY" ]; then
  echo "ERROR: HUAWEI_MAAS_API_KEY is required." >&2
  ERRORS=$((ERRORS + 1))
fi
if [[ "$MAAS_API_KEY" == *"change-me"* ]] || [[ "$MAAS_API_KEY" == *"xxx"* ]]; then
  echo "ERROR: HUAWEI_MAAS_API_KEY still has a placeholder value." >&2
  ERRORS=$((ERRORS + 1))
fi
for i in "${!EXTRA_KEYS[@]}"; do
  key="${EXTRA_KEYS[$i]}"
  if [ -z "$key" ]; then
    echo "ERROR: Additional MaaS API key $((i + 1)) is empty." >&2
    ERRORS=$((ERRORS + 1))
  elif [[ "$key" == *"change-me"* ]] || [[ "$key" == *"xxx"* ]]; then
    echo "ERROR: Additional MaaS API key $((i + 1)) still has a placeholder value." >&2
    ERRORS=$((ERRORS + 1))
  fi
done
if [[ ! "$PROM_RETENTION" =~ ^([0-9]+)([dhw])$ ]]; then
  echo "ERROR: PROMETHEUS_RETENTION must be a Prometheus duration like 30d, 14d, 7d. Got: $PROM_RETENTION" >&2
  ERRORS=$((ERRORS + 1))
fi
if [ "$ERRORS" -gt 0 ]; then
  echo "" >&2
  echo "Validation failed with $ERRORS error(s)." >&2
  exit 1
fi

# ── Write .env ──
cat > "$ENV_FILE" <<EOF
# ── Proxy Auth ───────────────────────────────────
LITELLM_MASTER_KEY="${MASTER_KEY}"
LITELLM_SALT_KEY="${SALT_KEY}"

# ── Database ─────────────────────────────────────
DB_PASSWORD="${DB_PASSWORD}"

# ── Grafana ──────────────────────────────────────
GRAFANA_ADMIN_PASSWORD="${GRAFANA_PASSWORD}"

# ── Prometheus ───────────────────────────────────
PROMETHEUS_RETENTION="${PROM_RETENTION}"

# ── Huawei MaaS ──────────────────────────────────
HUAWEI_MAAS_API_KEY="${MAAS_API_KEY}"
HUAWEI_MAAS_API_KEY_COUNT=${KEY_COUNT}
HUAWEI_MAAS_API_KEY_0="${MAAS_API_KEY}"
EOF
for i in "${!EXTRA_KEYS[@]}"; do
  echo "HUAWEI_MAAS_API_KEY_$((i + 1))=\"${EXTRA_KEYS[$i]}\"" >> "$ENV_FILE"
done
cat >> "$ENV_FILE" <<EOF

# ── MaaS Endpoint ──────────────────────────────────
HUAWEI_MAAS_API_BASE="${MAAS_API_BASE}"

# ── MaaS Anthropic Endpoint ───────────────────────
HUAWEI_MAAS_ANTHROPIC_API_BASE="${MAAS_ANTHROPIC_BASE}"
EOF
chmod 600 "$ENV_FILE"

# ── Configure git hooks (prevent committing secrets) ──
if [ -d "$PROJECT_DIR/.githooks" ]; then
  CURRENT_HOOKS=$(git -C "$PROJECT_DIR" config --local core.hooksPath 2>/dev/null || true)
  if [ "$CURRENT_HOOKS" != ".githooks" ]; then
    git -C "$PROJECT_DIR" config core.hooksPath .githooks
    echo "  ✓ Git hooks configured (.githooks/pre-commit blocks .env and secrets)"
  fi
fi

# ── Warn if --force was used ──
if [ "$FORCE" = true ]; then
  echo ""
  echo "WARNING: All secrets were regenerated (--force). Restart Docker to apply:"
  echo "  docker compose up -d"
  echo "Existing virtual keys are invalidated — re-run tool installs to mint new ones."
fi

# ── Summary ──
echo ""
echo "  .env written: $ENV_FILE (chmod 600)"
echo "  HUAWEI_MAAS_API_KEY = $(mask_key "$MAAS_API_KEY")"
echo "  MaaS API key count  = ${KEY_COUNT}"
echo "  LITELLM_MASTER_KEY  = $(mask_key "$MASTER_KEY")"
echo "  PROMETHEUS_RETENTION   = ${PROM_RETENTION}"
