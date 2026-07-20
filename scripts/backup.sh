#!/bin/bash
# ════════════════════════════════════════════════════════════════
# backup.sh — InfraWatch Backup Script
# ════════════════════════════════════════════════════════════════
#
# Usage:     bash scripts/backup.sh
# Cron:      0 2 * * * /opt/infrawatch/scripts/backup.sh
#            (Runs at 2 AM every day)
#
# What it backs up:
#   1. Application source code (tar.gz, excluding .git and venv)
#   2. Docker volume: app_logs (application logs)
#   3. Docker volume: nginx_logs (Nginx access/error logs)
#
# Retention: Deletes backups older than 7 days automatically
# ════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────
BACKUP_DIR="/var/backups/infrawatch"
PROJECT_DIR="/opt/infrawatch"
DATE=$(date '+%Y%m%d_%H%M%S')
BACKUP_PREFIX="infrawatch_backup_${DATE}"
RETENTION_DAYS=7

# ── Colours ────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log()   { echo -e "${GREEN}[BACKUP $(date '+%H:%M:%S')] ✅ $*${NC}"; }
warn()  { echo -e "${YELLOW}[BACKUP $(date '+%H:%M:%S')] ⚠️  $*${NC}"; }
error() { echo -e "${RED}[BACKUP $(date '+%H:%M:%S')] ❌ $*${NC}"; exit 1; }
info()  { echo -e "${BLUE}[BACKUP $(date '+%H:%M:%S')] ℹ️  $*${NC}"; }

echo ""
echo "══════════════════════════════════"
echo "  InfraWatch Backup Script"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "══════════════════════════════════"
echo ""

# ── Create backup directory ────────────────────────────────────────────────
mkdir -p "$BACKUP_DIR"
info "Backup destination: $BACKUP_DIR"

# ── 1. Backup application source code ─────────────────────────────────────
info "Backing up application source code..."
tar -czf "${BACKUP_DIR}/${BACKUP_PREFIX}_app.tar.gz" \
    --exclude="${PROJECT_DIR}/.git" \
    --exclude="${PROJECT_DIR}/.venv" \
    --exclude="${PROJECT_DIR}/venv" \
    --exclude="${PROJECT_DIR}/__pycache__" \
    --exclude="${PROJECT_DIR}/logs" \
    -C /opt infrawatch 2>/dev/null
log "App backup: ${BACKUP_PREFIX}_app.tar.gz ($(du -sh "${BACKUP_DIR}/${BACKUP_PREFIX}_app.tar.gz" | cut -f1))"

# ── 2. Backup app logs Docker volume ──────────────────────────────────────
info "Backing up application logs Docker volume..."
if docker volume inspect infrawatch_app_logs &>/dev/null; then
    docker run --rm \
        --volume infrawatch_app_logs:/volume_data:ro \
        --volume "${BACKUP_DIR}":/backup \
        alpine:latest \
        tar -czf "/backup/${BACKUP_PREFIX}_app_logs.tar.gz" -C /volume_data . 2>/dev/null
    log "App logs backup: ${BACKUP_PREFIX}_app_logs.tar.gz"
else
    warn "Volume infrawatch_app_logs not found — skipping"
fi

# ── 3. Backup Nginx logs Docker volume ────────────────────────────────────
info "Backing up Nginx logs Docker volume..."
if docker volume inspect infrawatch_nginx_logs &>/dev/null; then
    docker run --rm \
        --volume infrawatch_nginx_logs:/volume_data:ro \
        --volume "${BACKUP_DIR}":/backup \
        alpine:latest \
        tar -czf "/backup/${BACKUP_PREFIX}_nginx_logs.tar.gz" -C /volume_data . 2>/dev/null
    log "Nginx logs backup: ${BACKUP_PREFIX}_nginx_logs.tar.gz"
else
    warn "Volume infrawatch_nginx_logs not found — skipping"
fi

# ── 4. Create backup manifest ─────────────────────────────────────────────
info "Creating backup manifest..."
cat > "${BACKUP_DIR}/${BACKUP_PREFIX}_manifest.txt" << EOF
InfraWatch Backup Manifest
==========================
Date:      $(date '+%Y-%m-%d %H:%M:%S')
Host:      $(hostname)
User:      $(whoami)
Git commit: $(cd "$PROJECT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")

Files:
  ${BACKUP_PREFIX}_app.tar.gz        — Application source
  ${BACKUP_PREFIX}_app_logs.tar.gz   — Application logs volume
  ${BACKUP_PREFIX}_nginx_logs.tar.gz — Nginx logs volume
EOF
log "Manifest created"

# ── 5. Remove old backups ─────────────────────────────────────────────────
info "Removing backups older than $RETENTION_DAYS days..."
DELETED=$(find "$BACKUP_DIR" -name "infrawatch_backup_*" -mtime "+${RETENTION_DAYS}" -print -delete 2>/dev/null | wc -l)
[ "$DELETED" -gt 0 ] && log "Deleted $DELETED old backup file(s)" || info "No old backups to delete"

# ── Summary ───────────────────────────────────────────────────────────────
REMAINING=$(find "$BACKUP_DIR" -name "infrawatch_backup_*" | wc -l)
TOTAL_SIZE=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)

echo ""
echo "══════════════════════════════════"
log "Backup completed!"
info "  Location  : $BACKUP_DIR"
info "  Date/Time : $DATE"
info "  Total Size: $TOTAL_SIZE"
info "  Files kept: $REMAINING"
echo "══════════════════════════════════"
echo ""
