# ════════════════════════════════════════════════════════════════
# InfraWatch — Dockerfile (Multi-Stage Build)
# ════════════════════════════════════════════════════════════════
#
# Why multi-stage?
#   Stage 1 (builder): installs build tools + compiles packages
#   Stage 2 (runtime): copies only the binaries — no gcc, no cache
#   Result: ~60% smaller final image, smaller attack surface
#
# ════════════════════════════════════════════════════════════════

# ── Stage 1: Builder ─────────────────────────────────────────────
FROM python:3.11-slim AS builder

WORKDIR /app

# Install build dependencies (needed to compile some psutil C extensions)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copy only requirements first (Docker layer cache optimization)
# If requirements.txt doesn't change, this layer is cached → faster builds
COPY requirements.txt .

# Install packages to user home (will be copied to runtime stage)
RUN pip install --user --no-cache-dir -r requirements.txt


# ── Stage 2: Runtime ─────────────────────────────────────────────
FROM python:3.11-slim

# Image metadata labels (good practice for production)
LABEL maintainer="Sudheer Konduboina <sudheer@example.com>"
LABEL version="1.0.0"
LABEL description="InfraWatch — Infrastructure Monitoring REST API"
LABEL org.opencontainers.image.source="https://github.com/SudheerKonduboina/devops_demo"

WORKDIR /app

# ── Security: Create non-root user ───────────────────────────────
# Running as root inside a container is a security risk.
# If the container is compromised, the attacker gets root on the host.
RUN groupadd --system appgroup && \
    useradd --system --gid appgroup --no-create-home appuser

# ── Copy installed Python packages from builder stage ─────────────
COPY --from=builder /root/.local /home/appuser/.local

# ── Copy application source code ─────────────────────────────────
COPY --chown=appuser:appgroup . .

# ── Create logs directory with proper ownership ───────────────────
RUN mkdir -p logs && chown -R appuser:appgroup logs

# ── Environment variables ─────────────────────────────────────────
ENV PATH=/home/appuser/.local/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PORT=5000

# ── Expose internal port ──────────────────────────────────────────
EXPOSE 5000

# ── Switch to non-root user ───────────────────────────────────────
USER appuser

# ── Docker HEALTHCHECK ────────────────────────────────────────────
# Docker will probe this every 30s. If it fails 3 times → unhealthy.
# Nginx depends_on: app (condition: service_healthy)
HEALTHCHECK \
    --interval=30s \
    --timeout=10s \
    --start-period=15s \
    --retries=3 \
    CMD python -c \
        "import urllib.request, sys; \
         r = urllib.request.urlopen('http://localhost:5000/healthz', timeout=5); \
         sys.exit(0 if r.status == 200 else 1)"

# ── Start Gunicorn production server ──────────────────────────────
# --workers 2        : 2 worker processes (good for t2.micro)
# --threads 4        : 4 threads per worker
# --timeout 120      : 2 min timeout for slow health checks
# --access-logfile - : Log to stdout (captured by Docker)
# --error-logfile -  : Errors to stderr
CMD ["gunicorn", \
     "--bind", "0.0.0.0:5000", \
     "--workers", "2", \
     "--threads", "4", \
     "--timeout", "120", \
     "--access-logfile", "-", \
     "--error-logfile", "-", \
     "run:app"]
