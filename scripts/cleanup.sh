#!/bin/bash
# ════════════════════════════════════════════════════════════════
# cleanup.sh — InfraWatch Docker & Log Cleanup Script
# ════════════════════════════════════════════════════════════════
#
# Usage:   bash scripts/cleanup.sh
# Cron:    0 3 * * 0 /opt/infrawatch/scripts/cleanup.sh
#          (Every Sunday at 3 AM)
#
# What it cleans:
#   1. Stopped Docker containers
#   2. Dangling Docker images (untagged layers)
#   3. Unused Docker networks
#   4. Docker build cache
#   5. Deploy log files older than 30 days
#   6. Temp files in /tmp matching infrawatch_*
# ════════════════════════════════════════════════════════════════

set -uo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'
log()  { echo -e "${GREEN}[CLEANUP $(date '+%H:%M:%S')] ✅ $*${NC}"; }
warn() { echo -e "${YELLOW}[CLEANUP $(date '+%H:%M:%S')] ⚠️  $*${NC}"; }
info() { echo -e "${BLUE}[CLEANUP $(date '+%H:%M:%S')] ℹ️  $*${NC}"; }

echo ""
echo -e "${BOLD}══════════════════════════════════${NC}"
echo "  InfraWatch Cleanup Script"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "${BOLD}══════════════════════════════════${NC}"
echo ""

# ── Before stats ───────────────────────────────────────────────────────────
info "Disk usage BEFORE cleanup:"
df -h / | tail -1
echo ""
info "Docker disk usage BEFORE cleanup:"
docker system df 2>/dev/null || true
echo ""

# ── 1. Stopped containers ──────────────────────────────────────────────────
info "Removing stopped containers..."
REMOVED_CONTAINERS=$(docker container prune -f 2>/dev/null | grep "deleted" | wc -l || echo 0)
log "Removed stopped containers: $REMOVED_CONTAINERS"

# ── 2. Dangling images ─────────────────────────────────────────────────────
info "Removing dangling Docker images..."
REMOVED_IMAGES=$(docker image prune -f 2>/dev/null | grep "deleted" | wc -l || echo 0)
log "Removed dangling images: $REMOVED_IMAGES"

# ── 3. Unused networks ─────────────────────────────────────────────────────
info "Removing unused Docker networks..."
docker network prune -f 2>/dev/null | grep -v "^$" | head -5 || true
log "Unused networks cleaned"

# ── 4. Build cache ─────────────────────────────────────────────────────────
info "Removing Docker build cache..."
CACHE_FREED=$(docker builder prune -f 2>/dev/null | tail -1 || echo "0B")
log "Build cache freed: $CACHE_FREED"

# ── 5. Old deploy logs ─────────────────────────────────────────────────────
LOG_DIR="/var/log/infrawatch"
if [ -d "$LOG_DIR" ]; then
    info "Removing deploy logs older than 30 days in $LOG_DIR..."
    DELETED_LOGS=$(find "$LOG_DIR" -name "*.log.*" -mtime +30 -print -delete 2>/dev/null | wc -l)
    log "Deleted old log files: $DELETED_LOGS"
else
    warn "$LOG_DIR not found — skipping log cleanup"
fi

# ── 6. Temp files ──────────────────────────────────────────────────────────
info "Removing temp files matching infrawatch_* in /tmp..."
DELETED_TMP=$(find /tmp -name "infrawatch_*" -mtime +1 -print -delete 2>/dev/null | wc -l)
log "Temp files removed: $DELETED_TMP"

# ── After stats ────────────────────────────────────────────────────────────
echo ""
info "Disk usage AFTER cleanup:"
df -h / | tail -1
echo ""
info "Docker disk usage AFTER cleanup:"
docker system df 2>/dev/null || true

echo ""
echo -e "${BOLD}══════════════════════════════════${NC}"
log "✅ Cleanup complete!"
echo -e "${BOLD}══════════════════════════════════${NC}"
echo ""
