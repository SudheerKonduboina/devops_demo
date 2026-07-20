# InfraWatch — Architecture Documentation

## Overview

InfraWatch follows a **microservices-inspired, containerized architecture** where each
component has a single responsibility and communicates through defined interfaces.

---

## Component Roles

### 1. Flask Application (`infrawatch/`)

**What it is:** A Python web application using the Flask framework.

**Why Flask?**
- Lightweight — no unnecessary overhead
- Perfect for REST APIs
- Large ecosystem and community
- Widely used in DevOps tooling (Airflow, Vault UI, etc.)

**Internal structure:**
```
infrawatch/
├── __init__.py        # Application factory — creates and configures Flask
├── routes/
│   ├── health.py      # Probes for container orchestrators (Docker, K8s)
│   └── system.py      # System metrics via psutil library
└── utils/
    └── logger.py      # Rotating file handler + console output
```

**Application factory pattern:**
Instead of creating `app = Flask(__name__)` globally, we use `create_app()`.
This is a best practice because:
- Easier to test (create a fresh app per test)
- Supports multiple configurations (dev/staging/prod)
- Prevents circular imports

---

### 2. Gunicorn (WSGI Server)

**What it is:** A production-grade Python WSGI server.

**Why Gunicorn instead of Flask's dev server?**
- Flask's `app.run()` is **single-threaded** and not safe for production
- Gunicorn spawns **multiple worker processes** to handle concurrent requests
- Our config: `--workers 2 --threads 4` = 8 concurrent request slots

**How it works:**
```
Gunicorn Master Process
    ├── Worker Process 1 (handles requests)
    ├── Worker Process 2 (handles requests)
    └── (manages workers, restarts crashed ones)
```

---

### 3. Nginx (Reverse Proxy)

**What it is:** A high-performance HTTP server acting as a reverse proxy.

**Why Nginx in front of Gunicorn?**

| Without Nginx | With Nginx |
|--------------|------------|
| App directly exposed to internet | Nginx shields the app |
| No SSL/TLS termination | SSL handled by Nginx |
| No rate limiting | 10 req/s limit per IP |
| No compression | Gzip enabled |
| No security headers | X-Frame-Options, etc. |

**Data flow:**
```
Client → Nginx :80 → (Docker network) → Gunicorn :5000 → Flask
```

**Key config decisions:**
- `upstream infrawatch_backend` — defines the Flask container as upstream
- `limit_req_zone` — prevents DDoS/brute-force attacks
- `keepalive 32` — reuses connections to Flask (performance)
- `server_tokens off` — hides Nginx version from attackers

---

### 4. Docker (Containerization)

**What it is:** A platform to package apps and their dependencies into containers.

**Why Docker?**
- **"Works on my machine"** → eliminated. Container is identical everywhere.
- Easy to deploy to any server (EC2, GCP, bare metal)
- Resource isolation (app can't affect host OS)
- Easy rollbacks (just run old image)

**Multi-stage build explanation:**

```dockerfile
# Stage 1: Builder
# Has gcc and build tools — needed to compile psutil C extension
FROM python:3.11-slim AS builder
RUN pip install --user -r requirements.txt

# Stage 2: Runtime
# ONLY copies compiled packages from builder
# No gcc, no build tools → smaller, more secure image
FROM python:3.11-slim
COPY --from=builder /root/.local /home/appuser/.local
```

**Result:** Final image is ~200MB instead of ~400MB.

---

### 5. Docker Compose (Orchestration)

**What it is:** Tool for defining and running multi-container apps with a YAML file.

**Why Docker Compose?**
- One `docker compose up -d` starts the entire stack
- Networks are automatically created (containers find each other by name)
- Volumes persist data across restarts
- `depends_on: condition: service_healthy` ensures Nginx waits for Flask

**Service dependency:**
```
nginx depends_on app (condition: service_healthy)
         ↓
         Nginx only starts after Flask passes HEALTHCHECK
```

---

### 6. GitHub Actions (CI/CD)

**What it is:** Automated pipeline built into GitHub that runs on code events.

**Pipeline flow:**
```
Developer pushes code
       │
       ▼
   GitHub.com detects push
       │
       ▼
   Actions runner (ubuntu-latest VM):
   [Job 1] Lint  → format + style checks
   [Job 2] Test  → pytest (requires Job 1 success)
   [Job 3] Build → Docker image + smoke test (requires Job 2)
   [Job 4] Deploy → SSH into EC2 (requires Job 3, only on main)
```

**Why CI/CD matters:**
- Catches bugs before they reach production
- Every deployment is automated and consistent
- No manual SSH-and-drag every time you update code

---

### 7. AWS EC2 (Cloud Hosting)

**What it is:** A virtual machine running in AWS's data centers.

**Configuration:**
- Instance type: `t2.micro` (1 vCPU, 1 GB RAM) — free tier eligible
- AMI: Ubuntu Server 22.04 LTS
- Region: `ap-south-1` (Mumbai) or your nearest
- Elastic IP: Static public IP address (doesn't change on restart)

**Security Group rules:**
```
Inbound:
  Port 22  (SSH)  — Your IP only (or 0.0.0.0/0 for simplicity)
  Port 80  (HTTP) — 0.0.0.0/0 (public access)

Outbound:
  All traffic — 0.0.0.0/0 (needed for git pull, package install)
```

---

## Data Flow — Full Request Lifecycle

```
1. User opens browser → http://your-ec2-ip/api/v1/metrics

2. AWS routes request to EC2's public IP (Elastic IP)

3. EC2 Security Group checks: Is port 80 open? YES → forward

4. Nginx container receives request on port 80
   ├── Rate limit check: is this IP within 10 req/s? YES → forward
   ├── Adds headers: X-Real-IP, X-Forwarded-For
   └── Proxy_pass → http://app:5000/api/v1/metrics

5. Docker resolves "app" → infrawatch-app container IP

6. Gunicorn assigns request to a worker process

7. Flask handler (system.py → metrics()) executes:
   ├── psutil.cpu_percent()
   ├── psutil.virtual_memory()
   ├── psutil.disk_usage("/")
   └── Returns JSON response

8. Response travels back: Flask → Gunicorn → Nginx → User
   └── Nginx adds: gzip compression, security headers

9. Logger writes entry to logs/infrawatch.log (Docker volume)
```

---

## Why This Architecture for a DevOps Intern Project?

1. **Industry-standard** — Flask + Nginx + Docker is how most Python APIs are deployed
2. **Free** — runs on AWS Free Tier
3. **Demonstrates depth** — shows understanding of each layer
4. **Scalable pattern** — same architecture works for much larger systems
5. **Interview-ready** — every decision can be explained with clear reasoning
