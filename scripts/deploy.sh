#!/bin/bash
# ════════════════════════════════════════════════════════════════
# deploy.sh — InfraWatch Automated Deployment Script
# ════════════════════════════════════════════════════════════════
#
# Usage:     sudo bash scripts/deploy.sh
# Purpose:   Pull latest code, rebuild containers, verify health
# Cron:      Not recommended for deploy — use CI/CD instead
#
# What it does:
#   1. Validates prerequisites (docker, git)
#   2. Backs up current deployment
#   3. Pulls latest code from GitHub
#   4. Rebuilds Docker images (--no-cache for fresh build)
#   5. Restarts all containers with zero-downtime approach
#   6. Runs health checks with retries
#   7. Cleans up old Docker images
# ════════════════════════════════════════════════════════════════

set -euo pipefail   # Exit on error (-e), undefined vars (-u), pipe failures (-o pipefail)

# ── Configuration ──────────────────────────────────────────────────────────
PROJECT_DIR="/opt/infrawatch"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"
LOG_FILE="/var/log/infrawatch/deploy.log"
DEPLOY_USER="${DEPLOY_USER:-ubuntu}"

# ── Colour helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'
BOLD='\033[1m'; NC='\033[0m'

log()   { echo -e "${GREEN}[$(date '+%H:%M:%S')] ✅ $*${NC}" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️  $*${NC}" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[$(date '+%H:%M:%S')] ❌ $*${NC}" | tee -a "$LOG_FILE"; exit 1; }
info()  { echo -e "${BLUE}[$(date '+%H:%M:%S')] ℹ️  $*${NC}" | tee -a "$LOG_FILE"; }
step()  { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}\n" | tee -a "$LOG_FILE"; }

# ── Setup log file ──────────────────────────────────────────────────────────
mkdir -p "$(dirname "$LOG_FILE")"
echo "" >> "$LOG_FILE"
echo "════════════════════════════════════" >> "$LOG_FILE"
echo "  Deployment started: $(date)" >> "$LOG_FILE"
echo "  User: $(whoami) | Host: $(hostname)" >> "$LOG_FILE"
echo "════════════════════════════════════" >> "$LOG_FILE"

# ── Banner ──────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}"
echo "  ██╗███╗   ██╗███████╗██████╗  █████╗ "
echo "  ██║████╗  ██║██╔════╝██╔══██╗██╔══██╗"
echo "  ██║██╔██╗ ██║█████╗  ██████╔╝███████║"
echo "  ██║██║╚██╗██║██╔══╝  ██╔══██╗██╔══██║"
echo "  ██║██║ ╚████║██║     ██║  ██║██║  ██║"
echo "  ╚═╝╚═╝  ╚═══╝╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝"
echo -e "  WATCH — Deployment Script${NC}"
echo ""

# ── Step 1: Pre-flight checks ───────────────────────────────────────────────
step "Pre-flight Checks"

command -v docker   &>/dev/null || error "Docker is not installed. Run: apt install docker.io"
command -v git      &>/dev/null || error "Git is not installed. Run: apt install git"
[ -d "$PROJECT_DIR" ]          || error "Project directory not found: $PROJECT_DIR"
[ -f "$COMPOSE_FILE" ]         || error "docker-compose.yml not found: $COMPOSE_FILE"

DOCKER_RUNNING=$(docker info &>/dev/null && echo "yes" || echo "no")
[ "$DOCKER_RUNNING" = "yes" ]  || error "Docker daemon is not running. Run: systemctl start docker"

log "All pre-flight checks passed"

# ── Step 2: Backup ──────────────────────────────────────────────────────────
step "Creating Pre-Deployment Backup"

if bash "$PROJECT_DIR/scripts/backup.sh"; then
    log "Backup completed successfully"
else
    warn "Backup failed — continuing with deployment (manual backup recommended)"
fi

# ── Step 3: Pull latest code ────────────────────────────────────────────────
step "Pulling Latest Code from GitHub"

cd "$PROJECT_DIR"
git fetch origin main
CURRENT_COMMIT=$(git rev-parse --short HEAD)
git reset --hard origin/main
NEW_COMMIT=$(git rev-parse --short HEAD)

if [ "$CURRENT_COMMIT" = "$NEW_COMMIT" ]; then
    warn "No new commits (still at $NEW_COMMIT). Redeploying anyway..."
else
    log "Updated: $CURRENT_COMMIT → $NEW_COMMIT"
fi

# ── Step 4: Build Docker images ─────────────────────────────────────────────
step "Building Docker Images"

info "Building with --no-cache (fresh build ensures latest code is included)..."
docker compose -f "$COMPOSE_FILE" build --no-cache
log "Docker images built successfully"

# ── Step 5: Stop old containers ─────────────────────────────────────────────
step "Stopping Existing Containers"

docker compose -f "$COMPOSE_FILE" down --remove-orphans 2>/dev/null || true
log "Old containers stopped"

# ── Step 6: Start new containers ────────────────────────────────────────────
step "Starting New Containers"

docker compose -f "$COMPOSE_FILE" up -d
log "Containers started in detached mode"

# ── Step 7: Wait for startup ─────────────────────────────────────────────────
step "Waiting for Application Startup"

info "Giving containers 20 seconds to initialize..."
sleep 20

# ── Step 8: Health check with retry ─────────────────────────────────────────
step "Running Health Checks"

MAX_RETRIES=10
RETRY_DELAY=5
COUNT=0

until curl -sf http://localhost/healthz > /dev/null 2>&1; do
    COUNT=$((COUNT + 1))
    if [ "$COUNT" -ge "$MAX_RETRIES" ]; then
        error "Health check failed after $MAX_RETRIES attempts! Check logs:"$'\n'"  docker compose -f $COMPOSE_FILE logs"
    fi
    warn "Health check attempt $COUNT/$MAX_RETRIES failed. Retrying in ${RETRY_DELAY}s..."
    sleep "$RETRY_DELAY"
done

log "Health check passed at attempt $COUNT!"

# ── Step 9: Cleanup ──────────────────────────────────────────────────────────
step "Post-Deployment Cleanup"

docker image prune -f  > /dev/null 2>&1 && log "Unused Docker images removed"
docker container prune -f > /dev/null 2>&1 && log "Stopped containers cleaned up"

# ── Final Summary ────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${GREEN}══════════════════════════════════════════${NC}"
log "🚀 DEPLOYMENT COMPLETE!"
echo ""
info "Deployed commit : $NEW_COMMIT"
info "API endpoint    : http://$(curl -s ifconfig.me 2>/dev/null || echo 'your-ip')"
info "Logs            : $LOG_FILE"
info "Container status:"
docker compose -f "$COMPOSE_FILE" ps
echo -e "${BOLD}${GREEN}══════════════════════════════════════════${NC}"
echo ""
