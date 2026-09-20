#!/usr/bin/env bash
set -euo pipefail

# ─── 06_backup.sh — PostgreSQL backup & restore (maintenance, standalone) ─────
#
# Domain:        LiteLLM PostgreSQL database (spend history, virtual keys, budgets)
# Order:         maintenance — not part of the install pipeline (like update.sh)
# Optional:      n/a (run manually whenever a backup is needed)
# Description:   pg_dump the LiteLLM database to backups/litellm_YYYYmmdd_HHMMSS.sql
#                (chmod 600, pruned to the newest --keep dumps), or restore a
#                previous dump (stops LiteLLM, pipes it into psql, restarts).
# Inputs:        --dry-run, --restore FILE, --keep N, --yes
# Outputs:       backups/litellm_YYYYmmdd_HHMMSS.sql
# Standalone:    yes — ./scripts/06_backup.sh
# ──────────────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKUP_DIR="$PROJECT_DIR/backups"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"

source "$SCRIPT_DIR/helpers/common.sh"
LOG_TAG="backup"

usage() {
  cat <<'EOF'
Usage: ./scripts/06_backup.sh [--dry-run] [--restore FILE] [--keep N] [--yes]

Back up the LiteLLM PostgreSQL database (spend history, virtual keys,
budgets) to backups/litellm_YYYYmmdd_HHMMSS.sql. Dumps are chmod 600
(they contain spend history and key hashes) and pruned to the newest N
(--keep, default 10).

  --dry-run        Show what would happen without executing
  --restore FILE   Stop LiteLLM, restore FILE into the database, restart
                   LiteLLM. Prompts for confirmation (--yes skips).
  --keep N         Keep the newest N backups (default 10)
  --yes            Skip the restore confirmation prompt

Restore is a clean restore — wipe the DB volume first, then restore into
the empty database (recreates schema and data):
  docker compose stop litellm && docker compose rm -f db
  docker volume rm litellm_postgres_data
  docker compose up -d db        # wait ~10s for healthy
  ./scripts/06_backup.sh --restore FILE
EOF
}

# ── Parse args ──
DRY_RUN=false
RESTORE_FILE=""
RESTORE_PASSED=false
KEEP=10
ASSUME_YES=false
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)    DRY_RUN=true; shift ;;
    --restore)
      [ $# -ge 2 ] || { log_error "--restore requires a file argument"; exit 1; }
      RESTORE_FILE="$2"; RESTORE_PASSED=true; shift 2 ;;
    --restore=*)  RESTORE_FILE="${1#--restore=}"; RESTORE_PASSED=true; shift ;;
    --keep)
      [ $# -ge 2 ] || { log_error "--keep requires a number argument"; exit 1; }
      KEEP="$2"; shift 2 ;;
    --keep=*)     KEEP="${1#--keep=}"; shift ;;
    --yes)        ASSUME_YES=true; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            log_error "Unknown flag: $1"; echo ""; usage; exit 1 ;;
  esac
done

if ! [[ "$KEEP" =~ ^[0-9]+$ ]] || [ "$KEEP" -lt 1 ]; then
  log_error "--keep must be a positive integer. Got: $KEEP"
  exit 1
fi

# --restore= or --restore "" with an empty value is a user error — without
# this check it would silently run a backup instead.
if [ "$RESTORE_PASSED" = true ] && [ -z "$RESTORE_FILE" ]; then
  log_error "--restore requires a file path."
  exit 1
fi

log_step "PostgreSQL Backup"

# ── Restore mode ──
if [ -n "$RESTORE_FILE" ]; then
  if [ ! -f "$RESTORE_FILE" ]; then
    log_error "Restore file not found: $RESTORE_FILE"
    exit 1
  fi
  if ! grep -q 'PostgreSQL database dump' "$RESTORE_FILE" 2>/dev/null; then
    log_error "Not a valid pg_dump file (missing dump header): $RESTORE_FILE"
    exit 1
  fi

  if [ "$DRY_RUN" = true ]; then
    log_info "Would stop litellm, restore '$RESTORE_FILE', restart litellm"
    log_dim "  docker compose stop litellm"
    log_dim "  docker compose exec -T db psql -U llmproxy -d litellm -v ON_ERROR_STOP=1 < $RESTORE_FILE"
    log_dim "  docker compose up -d litellm"
    exit 0
  fi

  log_warn "This will REPLACE the current database content with: $RESTORE_FILE"
  if [ "$ASSUME_YES" != true ]; then
    if ! prompt_yesno "This will REPLACE the current database. Continue?" n; then
      log_info "Restore cancelled."
      exit 0
    fi
  fi

  log_info "Stopping LiteLLM (database must be idle during restore)..."
  docker compose -f "$COMPOSE_FILE" stop litellm
  # Ensure LiteLLM comes back up even if the script exits abnormally below
  # (idempotent no-op when it is already running).
  trap 'docker compose -f "$COMPOSE_FILE" up -d litellm 2>/dev/null || true' EXIT

  log_info "Restoring: $RESTORE_FILE"
  if ! docker compose -f "$COMPOSE_FILE" exec -T db psql -U llmproxy -d litellm -v ON_ERROR_STOP=1 < "$RESTORE_FILE"; then
    log_error "Restore failed — psql stopped on the first SQL error."
    log_dim "  The database may be partially restored. The reliable path is the"
    log_dim "  clean procedure: wipe the DB volume, then re-run --restore."
    exit 1
  fi

  log_info "Restarting LiteLLM..."
  docker compose -f "$COMPOSE_FILE" up -d litellm
  log_ok "Restore complete: $RESTORE_FILE"
  exit 0
fi

# ── Backup mode ──
umask 077  # dumps contain spend history + key hashes — deny group/world access
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUT="$BACKUP_DIR/litellm_${TIMESTAMP}.sql"

if [ "$DRY_RUN" = true ]; then
  log_info "Would create: $OUT"
  log_dim "  docker compose exec -T db pg_dump -U llmproxy -d litellm > $OUT"
  log_dim "  chmod 600 $OUT, then prune to newest $KEEP backup(s)"
  exit 0
fi

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

log_info "Dumping LiteLLM database..."
DUMP_RC=0
docker compose -f "$COMPOSE_FILE" exec -T db pg_dump -U llmproxy -d litellm > "${OUT}.tmp" 2>/dev/null || DUMP_RC=$?
if [ "$DUMP_RC" -ne 0 ] || [ ! -s "${OUT}.tmp" ] || ! grep -q 'PostgreSQL database dump' "${OUT}.tmp"; then
  log_error "Backup failed: pg_dump exit $DUMP_RC, output empty or failed sanity check."
  log_dim "  Check: docker compose logs db --tail 20"
  rm -f "${OUT}.tmp"
  exit 1
fi
mv "${OUT}.tmp" "$OUT"
chmod 600 "$OUT"
log_ok "Backup written: $OUT ($(du -h "$OUT" | cut -f1))"

# ── Prune old backups (keep newest N) ──
# 10# forces base-10 — a leading zero (e.g. --keep 08) would otherwise be
# parsed as an invalid octal literal in arithmetic context.
PRUNE_COUNT=$(ls -t "$BACKUP_DIR"/litellm_*.sql 2>/dev/null | tail -n +$((10#$KEEP + 1)) | wc -l || true)
if [ "$PRUNE_COUNT" -gt 0 ]; then
  ls -t "$BACKUP_DIR"/litellm_*.sql 2>/dev/null | tail -n +$((10#$KEEP + 1)) | xargs -r rm -f 2>/dev/null || true
  log_info "Pruned $PRUNE_COUNT old backup(s) — keeping newest $KEEP"
fi

echo ""
log_ok "Backup complete"
log_dim "Restore with: ./scripts/06_backup.sh --restore $OUT"
