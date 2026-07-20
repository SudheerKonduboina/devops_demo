#!/bin/bash
# ════════════════════════════════════════════════════════════════
# health_check.sh — InfraWatch Health Validation Script
# ════════════════════════════════════════════════════════════════
#
# Usage:   bash scripts/health_check.sh
# Returns: Exit 0 if all checks pass, Exit 1 if any check fails
#
# Checks:
#   1. Container status (app + nginx)
#   2. API endpoint responses
#   3. CPU usage vs threshold
#   4. Memory usage vs threshold
#   5. Disk usage vs threshold
#   6. Docker resource summary
#   7. Nginx container status
#   8. Response time measurement
# ════════════════════════════════════════════════════════════════

set -uo pipefail

# ── Configuration ──────────────────────────────────────────────────────────
API_URL="http://localhost"
COMPOSE_FILE="/opt/infrawatch/docker-compose.yml"
CPU_THRESHOLD=85
MEM_THRESHOLD=85
DISK_THRESHOLD=90
RESPONSE_TIME_THRESHOLD=2000   # milliseconds

# ── Colours ────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

PASS=0; WARN_COUNT=0; FAILURES=0

pass()  { echo -e "  ${GREEN}✅ PASS${NC}  $*"; PASS=$((PASS + 1)); }
fail()  { echo -e "  ${RED}❌ FAIL${NC}  $*"; FAILURES=$((FAILURES + 1)); }
warn()  { echo -e "  ${YELLOW}⚠️  WARN${NC}  $*"; WARN_COUNT=$((WARN_COUNT + 1)); }
info()  { echo -e "  ${BLUE}ℹ️  INFO${NC}  $*"; }
header(){ echo -e "\n${BOLD}── $* ──${NC}"; }

# ── Header ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║      InfraWatch Health Check Report          ║${NC}"
echo -e "${BOLD}║      $(date '+%Y-%m-%d %H:%M:%S')                    ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"

# ── 1. Docker Container Status ──────────────────────────────────────────────
header "Container Status"

if docker inspect infrawatch-app --format='{{.State.Status}}' 2>/dev/null | grep -q "^running$"; then
    pass "infrawatch-app container is RUNNING"
else
    fail "infrawatch-app container is NOT running"
fi

if docker inspect infrawatch-nginx --format='{{.State.Status}}' 2>/dev/null | grep -q "^running$"; then
    pass "infrawatch-nginx container is RUNNING"
else
    fail "infrawatch-nginx container is NOT running"
fi

UNHEALTHY=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" 2>/dev/null)
if [ -n "$UNHEALTHY" ]; then
    fail "Unhealthy containers detected: $UNHEALTHY"
else
    pass "No unhealthy containers"
fi

# ── 2. API Endpoint Checks ──────────────────────────────────────────────────
header "API Endpoints"

check_endpoint() {
    local path="$1"
    local expected="$2"
    local start_ms
    start_ms=$(date +%s%3N)
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${API_URL}${path}" 2>/dev/null || echo "000")
    local end_ms
    end_ms=$(date +%s%3N)
    local duration=$((end_ms - start_ms))

    if [ "$HTTP_CODE" = "$expected" ]; then
        pass "GET ${path} → HTTP $HTTP_CODE (${duration}ms)"
        if [ "$duration" -gt "$RESPONSE_TIME_THRESHOLD" ]; then
            warn "Slow response on ${path}: ${duration}ms > ${RESPONSE_TIME_THRESHOLD}ms"
        fi
    else
        fail "GET ${path} → HTTP $HTTP_CODE (expected $expected)"
    fi
}

check_endpoint "/" "200"
check_endpoint "/healthz" "200"
check_endpoint "/readyz" "200"
check_endpoint "/api/v1/metrics" "200"
check_endpoint "/api/v1/processes" "200"
check_endpoint "/api/v1/network" "200"

# ── 3. System Resource Checks ───────────────────────────────────────────────
header "System Resources"

# CPU check
CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | cut -d. -f1 2>/dev/null || echo "0")
CPU_USED=$((100 - CPU_IDLE))
if [ "$CPU_USED" -lt "$CPU_THRESHOLD" ]; then
    pass "CPU usage: ${CPU_USED}% (threshold: ${CPU_THRESHOLD}%)"
elif [ "$CPU_USED" -lt 95 ]; then
    warn "CPU usage HIGH: ${CPU_USED}% (threshold: ${CPU_THRESHOLD}%)"
else
    fail "CPU usage CRITICAL: ${CPU_USED}%"
fi

# Memory check
MEM_USED=$(free | awk '/^Mem:/ {printf "%.0f", ($3/$2)*100}' 2>/dev/null || echo "0")
if [ "$MEM_USED" -lt "$MEM_THRESHOLD" ]; then
    pass "Memory usage: ${MEM_USED}% (threshold: ${MEM_THRESHOLD}%)"
elif [ "$MEM_USED" -lt 95 ]; then
    warn "Memory usage HIGH: ${MEM_USED}% (threshold: ${MEM_THRESHOLD}%)"
else
    fail "Memory usage CRITICAL: ${MEM_USED}%"
fi

# Disk check
DISK_USED=$(df -h / | awk 'NR==2 {gsub(/%/,"",$5); print $5}' 2>/dev/null || echo "0")
if [ "$DISK_USED" -lt "$DISK_THRESHOLD" ]; then
    pass "Disk usage: ${DISK_USED}% (threshold: ${DISK_THRESHOLD}%)"
elif [ "$DISK_USED" -lt 95 ]; then
    warn "Disk usage HIGH: ${DISK_USED}%"
else
    fail "Disk usage CRITICAL: ${DISK_USED}% — free space running out!"
fi

# ── 4. Docker Resource Summary ──────────────────────────────────────────────
header "Docker Resources"
info "$(docker system df 2>/dev/null | tail -n +2 | head -5 || echo 'docker system df not available')"

# ── 5. Log File Check ───────────────────────────────────────────────────────
header "Log Files"
LOG_FILE="/var/log/infrawatch/deploy.log"
if [ -f "$LOG_FILE" ]; then
    LOG_SIZE=$(du -sh "$LOG_FILE" | cut -f1)
    pass "Deploy log exists ($LOG_SIZE)"
else
    info "Deploy log not found at $LOG_FILE (may not have deployed yet)"
fi

# ── Summary ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                   SUMMARY                   ║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════════╣${NC}"
echo -e "║  ${GREEN}✅ PASS${NC}   : ${PASS}                                  ║"
echo -e "║  ${YELLOW}⚠️  WARN${NC}   : ${WARN_COUNT}                                  ║"
echo -e "║  ${RED}❌ FAIL${NC}   : ${FAILURES}                                  ║"
echo -e "${BOLD}╚══════════════════════════════════════════════╝${NC}"
echo ""

if [ "$FAILURES" -gt 0 ]; then
    echo -e "${RED}${BOLD}❌ $FAILURES check(s) failed! Investigate immediately.${NC}"
    exit 1
elif [ "$WARN_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}${BOLD}⚠️  All critical checks passed. $WARN_COUNT warning(s) require attention.${NC}"
    exit 0
else
    echo -e "${GREEN}${BOLD}🎉 All checks passed! System is healthy.${NC}"
    exit 0
fi
