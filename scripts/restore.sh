#!/bin/bash
# ════════════════════════════════════════════════════════════════
# restore.sh — InfraWatch Backup Restoration Script
# ════════════════════════════════════════════════════════════════
#
# Usage:  bash scripts/restore.sh <backup_date>
# Exapmle: bash scripts/restore.sh 20240115_020001
#
# What it restores:
#   1. Application source code from tar.gz
#   2. Docker volumes (app logs, nginx logs) if backup exists
#
# The backup_date must match a backup created by backup.sh
# e.g. the date portion of: infrawatch_backup_20240115_020001_app.tar.gz
# ════════════════════════════════════════════════════════════════

set -uo pipefail

BACKUP_DIR="/var/backups/infrawatch"
PROJECT_DIR="/opt/infrawatch"
BACKUP_DATE="${1:-}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()   { echo -e "${GREEN}[RESTORE $(date '+%H:%M:%S')] ✅ $*${NC}"; }
warn()  { echo -e "${YELLOW}[RESTORE $(date '+%H:%M:%S')] ⚠️  $*${NC}"; }
error() { echo -e "${RED}[RESTORE $(date '+%H:%M:%S')] ❌ $*${NC}"; exit 1; }
info()  { echo -e "${BLUE}[RESTORE $(date '+%H:%M:%S')] ℹ️  $*${NC}"; }

# ── Usage check ────────────────────────────────────────────────────────────
if [ -z "$BACKUP_DATE" ]; then
    echo "Usage: bash restore.sh <backup_date>"
    echo ""
    echo "Available backups:"
    echo "──────────────────"
    if [ -d "$BACKUP_DIR" ]; then
        ls -1 "${BACKUP_DIR}"/*_app.tar.gz 2>/dev/null \
            | xargs -I{} basename {} _app.tar.gz \
            | sed 's/infrawatch_backup_//' \
            || echo "  No backups found in $BACKUP_DIR"
    else
        echo "  Backup directory $BACKUP_DIR does not exist"
    fi
    exit 1
fi

BACKUP_NAME="infrawatch_backup_${BACKUP_DATE}"
APP_BACKUP="${BACKUP_DIR}/${BACKUP_NAME}_app.tar.gz"

# ── Validate backup exists ─────────────────────────────────────────────────
[ -f "$APP_BACKUP" ] || error "Backup not found: $APP_BACKUP"

echo ""
echo "══════════════════════════════════════════════"
echo "  InfraWatch Backup Restoration"
echo "  Backup date: $BACKUP_DATE"
echo "  Source:      $APP_BACKUP"
echo "══════════════════════════════════════════════"
echo ""

# ── Confirmation ──────────────────────────────────────────────────────────
warn "⚠️  WARNING: This will OVERWRITE the current deployment at $PROJECT_DIR"
warn "   Current git commit: $(cd "$PROJECT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
echo ""
read -rp "  Type 'yes' to confirm restore: " CONFIRM
[ "$CONFIRM" = "yes" ] || { info "Restore cancelled."; exit 0; }

echo ""

# ── Step 1: Stop running containers ────────────────────────────────────────
info "Stopping running containers..."
docker compose -f "${PROJECT_DIR}/docker-compose.yml" down --remove-orphans 2>/dev/null || true
log "Containers stopped"

# ── Step 2: Restore application source ────────────────────────────────────
info "Restoring application source from $APP_BACKUP..."
# Remove current app dir contents and restore
tar -xzf "$APP_BACKUP" -C /opt
log "Application source restored"

# ── Step 3: Restore Docker volumes ────────────────────────────────────────
APP_LOGS_BACKUP="${BACKUP_DIR}/${BACKUP_NAME}_app_logs.tar.gz"
if [ -f "$APP_LOGS_BACKUP" ]; then
    info "Restoring app logs Docker volume..."
    # Ensure volume exists
    docker volume create infrawatch_app_logs 2>/dev/null || true
    docker run --rm \
        --volume infrawatch_app_logs:/volume_data \
        --volume "$BACKUP_DIR":/backup \
        alpine:latest \
        sh -c "rm -rf /volume_data/* && tar -xzf '/backup/${BACKUP_NAME}_app_logs.tar.gz' -C /volume_data"
    log "App logs volume restored"
else
    warn "App logs backup not found — volume not restored"
fi

NGINX_LOGS_BACKUP="${BACKUP_DIR}/${BACKUP_NAME}_nginx_logs.tar.gz"
if [ -f "$NGINX_LOGS_BACKUP" ]; then
    info "Restoring nginx logs Docker volume..."
    docker volume create infrawatch_nginx_logs 2>/dev/null || true
    docker run --rm \
        --volume infrawatch_nginx_logs:/volume_data \
        --volume "$BACKUP_DIR":/backup \
        alpine:latest \
        sh -c "rm -rf /volume_data/* && tar -xzf '/backup/${BACKUP_NAME}_nginx_logs.tar.gz' -C /volume_data"
    log "Nginx logs volume restored"
fi

# ── Step 4: Restart containers ────────────────────────────────────────────
info "Restarting containers..."
docker compose -f "${PROJECT_DIR}/docker-compose.yml" up -d --build
log "Containers restarted"

# ── Step 5: Health verification ───────────────────────────────────────────
info "Waiting 20 seconds for startup..."
sleep 20

info "Verifying API health..."
MAX=5; COUNT=0
until curl -sf http://localhost/healthz > /dev/null 2>&1; do
    COUNT=$((COUNT + 1))
    [ "$COUNT" -ge "$MAX" ] && error "Health check failed after restore! Check logs."
    warn "Retrying health check ($COUNT/$MAX)..."
    sleep 5
done
log "Health check passed!"

# ── Summary ───────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════"
log "✅ Restore completed successfully!"
info "  Restored from: $BACKUP_DATE"
info "  API status:    $(curl -s http://localhost/healthz)"
echo "══════════════════════════════════════════════"
echo ""
