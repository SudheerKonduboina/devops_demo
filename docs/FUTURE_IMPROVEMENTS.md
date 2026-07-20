# InfraWatch — Future Improvements

This document outlines planned enhancements to evolve InfraWatch from an intern-level
project into a production-grade platform.

---

## Phase 1: Security & Reliability (Next Steps)

### HTTPS / SSL Certificate
```bash
# Setup Let's Encrypt with Certbot
sudo apt install certbot python3-certbot-nginx
sudo certbot --nginx -d infrawatch.example.com
# Certbot auto-updates nginx.conf to redirect HTTP → HTTPS
```
- **Why:** HTTP sends data in plaintext. HTTPS is mandatory for production.
- **Effort:** 1-2 hours

### Secrets Management (HashiCorp Vault or AWS Secrets Manager)
- Instead of `.env` files, fetch secrets from a centralized vault
- **Why:** `.env` files can be accidentally committed or leaked
- **Effort:** 2-3 days

### Docker Image Vulnerability Scanning
```yaml
# Add to ci-cd.yml after build job:
- name: Scan image for vulnerabilities
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: infrawatch:latest
    severity: CRITICAL,HIGH
```
- **Why:** Container images can have known CVEs (vulnerabilities)
- **Tool:** Trivy (free, widely used)

---

## Phase 2: Observability (Monitoring Dashboard)

### Prometheus + Grafana Stack
```yaml
# Add to docker-compose.yml:
  prometheus:
    image: prom/prometheus
    volumes:
      - ./monitoring/prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"
```
- Prometheus scrapes `/metrics` endpoint every 15s
- Grafana visualizes metrics with beautiful dashboards
- **Why:** The current API returns metrics on-demand; Prometheus stores history

### Flask Prometheus Metrics Endpoint
```python
# Add to requirements.txt: prometheus-flask-exporter
from prometheus_flask_exporter import PrometheusMetrics
metrics = PrometheusMetrics(app)
# Auto-exposes /metrics endpoint in Prometheus format
```

### AWS CloudWatch Integration
```bash
# Install CloudWatch Agent on EC2
sudo apt install amazon-cloudwatch-agent
# Configure to send container logs to CloudWatch
```
- **Why:** Centralized logging across multiple EC2 instances

---

## Phase 3: Infrastructure as Code

### Terraform (AWS Provisioning)
```hcl
# main.tf
resource "aws_instance" "infrawatch" {
  ami           = "ami-0c7217cdde317cfec"  # Ubuntu 22.04
  instance_type = "t2.micro"
  key_name      = aws_key_pair.infrawatch.key_name
  
  vpc_security_group_ids = [aws_security_group.infrawatch.id]

  tags = {
    Name = "infrawatch-server"
  }
}
```
- **Why:** Currently the EC2 setup is manual. Terraform makes it repeatable and version-controlled.
- One `terraform apply` provisions the entire infrastructure.

### Ansible (Configuration Management)
```yaml
# playbook.yml
- name: Setup InfraWatch server
  hosts: ec2_servers
  tasks:
    - name: Install Docker
      apt: name=docker.io state=present
    - name: Clone repository
      git: repo=https://github.com/.../devops_demo.git dest=/opt/infrawatch
    - name: Start containers
      docker_compose: project_src=/opt/infrawatch state=present
```
- **Why:** Instead of SSH-ing and running commands manually, Ansible automates server setup.

---

## Phase 4: Scalability

### Kubernetes Deployment
```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: infrawatch
spec:
  replicas: 3
  selector:
    matchLabels:
      app: infrawatch
  template:
    spec:
      containers:
      - name: app
        image: infrawatch:latest
        livenessProbe:
          httpGet:
            path: /healthz
            port: 5000
```
- **Why:** Docker Compose runs on a single server. Kubernetes runs across multiple servers.
- Auto-scales based on CPU/memory load
- Automatically restarts crashed pods

### AWS ECS (Elastic Container Service)
- Managed container orchestration on AWS
- Easier than Kubernetes for small teams
- Native integration with ALB, CloudWatch

### Database Layer (PostgreSQL)
```yaml
# Add to docker-compose.yml:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: infrawatch
      POSTGRES_USER: infrawatch
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
```
- Store historical metrics in a database
- Enable trend analysis and alerting on metric history

---

## Phase 5: Multi-Environment Pipeline

### Current (single env):
```
push to main → deploy to EC2
```

### Future (multi-env):
```
push to develop → deploy to STAGING → auto-test → manual approval → deploy to PRODUCTION
```

```yaml
# ci-cd.yml additions:
  deploy-staging:
    environment: staging
    if: github.ref == 'refs/heads/develop'

  deploy-production:
    environment: production
    needs: [deploy-staging, integration-tests]
    if: github.ref == 'refs/heads/main'
```

---

## Phase 6: Advanced CI/CD

### Docker Registry (Push to DockerHub/ECR)
```yaml
- name: Login to DockerHub
  uses: docker/login-action@v3
  with:
    username: ${{ secrets.DOCKERHUB_USERNAME }}
    password: ${{ secrets.DOCKERHUB_TOKEN }}

- name: Push image
  run: docker push sudheer/infrawatch:latest
```
- **Why:** Currently the image is built on EC2 every deploy. Pushing to a registry means
  EC2 just pulls the pre-built image → faster deployments.

### AWS S3 Backup Integration
```bash
# In backup.sh, add after creating tar.gz:
aws s3 cp "${BACKUP_DIR}/${BACKUP_NAME}_app.tar.gz" \
    "s3://infrawatch-backups/${BACKUP_NAME}_app.tar.gz"
```
- **Why:** Local backups are lost if the EC2 instance is terminated.
  S3 provides durable, cross-region backup storage.

### Integration & Load Tests
```python
# tests/test_integration.py
import locust

class InfraWatchUser(locust.HttpUser):
    @locust.task
    def metrics(self):
        self.client.get("/api/v1/metrics")
```
- Locust: load testing tool (simulates 100+ concurrent users)

---

## Feature Ideas

- [ ] **WebSocket endpoint** — push real-time metrics updates to browser
- [ ] **Alert webhook** — POST to Slack/Discord when threshold exceeded
- [ ] **Basic auth** — protect admin endpoints with username/password
- [ ] **Rate limit per API key** — for multi-tenant use
- [ ] **Metrics history** — store last N readings in SQLite
- [ ] **Web dashboard** — simple HTML/JS frontend showing live metrics
- [ ] **Docker Swarm** — simpler alternative to Kubernetes for clustering
- [ ] **Nginx HTTPS** — Let's Encrypt SSL for `https://` access
- [ ] **Log aggregation** — ship Nginx + app logs to ELK or Loki+Grafana

---

## Technology Progression Path

```
CURRENT (Intern Level)
  Flask + Docker + Nginx + GitHub Actions + EC2
          ↓
INTERMEDIATE (Junior DevOps)
  + Terraform + Ansible + Prometheus + Grafana + SSL
          ↓
ADVANCED (Mid-Level DevOps)
  + Kubernetes + Helm + CI Registry + Multi-env + S3 + CloudWatch
          ↓
SENIOR (Senior DevOps/SRE)
  + Service Mesh (Istio) + GitOps (ArgoCD) + Chaos Engineering + SLOs
```
