# InfraWatch — AWS EC2 Deployment Guide

## Prerequisites

- AWS Account (free tier)
- GitHub account with the repo
- Terminal (Linux/Mac) or PowerShell/Git Bash (Windows)
- SSH client

---

## Phase 1: AWS Console Setup

### Step 1: Launch EC2 Instance

1. Log in to [AWS Console](https://console.aws.amazon.com)
2. Navigate to **EC2 → Instances → Launch Instance**
3. Configure:
   - **Name:** `infrawatch-server`
   - **AMI:** Ubuntu Server 22.04 LTS (free tier eligible)
   - **Instance type:** `t2.micro` (free tier)
   - **Key pair:** Create new → `infrawatch-key` → Download `.pem` file
   - **Security Group:** Create new → see Step 2

### Step 2: Configure Security Group

In the Security Group settings, add these **Inbound Rules**:

| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| SSH | TCP | 22 | My IP | SSH access |
| HTTP | TCP | 80 | 0.0.0.0/0 | Public web access |

> ⚠️ **Security Note:** For production, restrict SSH to your IP only.

### Step 3: Assign Elastic IP (Static IP)

1. Go to **EC2 → Elastic IPs → Allocate Elastic IP address**
2. Click **Allocate**
3. Select the new IP → **Actions → Associate Elastic IP**
4. Choose your `infrawatch-server` instance
5. Note the IP address — this is your permanent server IP

---

## Phase 2: Server Setup (SSH Into EC2)

### Connect to EC2

```bash
# Set correct permissions on key file (Linux/Mac)
chmod 400 infrawatch-key.pem

# SSH into server
ssh -i infrawatch-key.pem ubuntu@YOUR_ELASTIC_IP
```

> On Windows, use PuTTY or convert .pem to .ppk, or use Git Bash with the same command.

### Step 4: System Update

```bash
# Update package lists and upgrade existing packages
sudo apt-get update -y && sudo apt-get upgrade -y

# Install essential tools
sudo apt-get install -y git curl wget htop vim unzip
```

### Step 5: Install Docker

```bash
# Install Docker using official script
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add ubuntu user to docker group (no sudo needed)
sudo usermod -aG docker ubuntu

# Start Docker on boot
sudo systemctl enable docker
sudo systemctl start docker

# Log out and back in to apply group change
exit
ssh -i infrawatch-key.pem ubuntu@YOUR_ELASTIC_IP

# Verify Docker works
docker --version
docker compose version
```

### Step 6: Create Application Directory

```bash
# Create app directory
sudo mkdir -p /opt/infrawatch
sudo chown ubuntu:ubuntu /opt/infrawatch

# Create log directory
sudo mkdir -p /var/log/infrawatch
sudo chown ubuntu:ubuntu /var/log/infrawatch

# Create backup directory
sudo mkdir -p /var/backups/infrawatch
sudo chown ubuntu:ubuntu /var/backups/infrawatch
```

### Step 7: Clone Repository

```bash
# Clone the project
git clone https://github.com/SudheerKonduboina/devops_demo.git /opt/infrawatch
cd /opt/infrawatch

# Create environment file
cp .env.example .env

# Edit .env with your values
vim .env
# Press 'i' to insert, change SECRET_KEY to a random string
# Press 'Esc', then ':wq' to save and exit
```

---

## Phase 3: Deploy Application

### Step 8: Start with Docker Compose

```bash
cd /opt/infrawatch

# Build and start all containers (first time)
docker compose up -d --build

# Verify containers are running
docker compose ps

# Expected output:
# NAME                  SERVICE   STATUS         PORTS
# infrawatch-app        app       Up (healthy)   5000/tcp
# infrawatch-nginx      nginx     Up             0.0.0.0:80->80/tcp
```

### Step 9: Verify Deployment

```bash
# Test health endpoint locally
curl http://localhost/healthz

# Test metrics endpoint
curl http://localhost/api/v1/metrics

# From your browser: http://YOUR_ELASTIC_IP/api/v1/metrics
```

---

## Phase 4: Setup CI/CD (Auto Deploy)

### Step 10: Add GitHub Secrets

1. Go to your GitHub repository
2. **Settings → Secrets and variables → Actions → New repository secret**

Add these three secrets:

| Secret Name | Value |
|-------------|-------|
| `EC2_HOST` | Your Elastic IP (e.g., `13.233.45.67`) |
| `EC2_USER` | `ubuntu` |
| `EC2_SSH_KEY` | Paste the full content of your `.pem` file |

### Step 11: Test CI/CD Pipeline

```bash
# Make a small change, commit, and push
git checkout -b feature/test-cicd
echo "# test" >> README.md
git add README.md
git commit -m "test: trigger CI/CD pipeline"
git push origin feature/test-cicd

# Create Pull Request on GitHub → watch Actions tab
# Merge to main → watch deploy job
```

---

## Phase 5: Setup Crontab for Automation

```bash
# Open crontab editor
crontab -e

# Add these lines:
# (i) Health check every 5 minutes
*/5 * * * * bash /opt/infrawatch/scripts/health_check.sh >> /var/log/infrawatch/cron.log 2>&1

# (ii) Daily backup at 2 AM
0 2 * * * bash /opt/infrawatch/scripts/backup.sh >> /var/log/infrawatch/backup.log 2>&1

# (iii) Weekly cleanup (Sunday 3 AM)
0 3 * * 0 bash /opt/infrawatch/scripts/cleanup.sh >> /var/log/infrawatch/cleanup.log 2>&1

# Save and exit (:wq)
# Verify crontab
crontab -l
```

---

## Phase 6: Run Monitor as systemd Service

```bash
# Create systemd service file
sudo vim /etc/systemd/system/infrawatch-monitor.service
```

Paste this content:

```ini
[Unit]
Description=InfraWatch Health Monitor Daemon
After=network.target docker.service
Requires=docker.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/infrawatch
Environment="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=/usr/bin/python3 /opt/infrawatch/monitoring/health_monitor.py
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

```bash
# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable infrawatch-monitor
sudo systemctl start infrawatch-monitor

# Check status
sudo systemctl status infrawatch-monitor

# View logs
sudo journalctl -u infrawatch-monitor -f
```

---

## Phase 7: User Management (Linux Admin)

```bash
# Create a dedicated deploy user (least privilege)
sudo useradd -m -s /bin/bash deployuser
sudo usermod -aG docker deployuser

# Add SSH key for deployuser
sudo mkdir -p /home/deployuser/.ssh
sudo cp ~/.ssh/authorized_keys /home/deployuser/.ssh/
sudo chown -R deployuser:deployuser /home/deployuser/.ssh
sudo chmod 700 /home/deployuser/.ssh
sudo chmod 600 /home/deployuser/.ssh/authorized_keys

# Give deployuser access to project only
sudo chown -R deployuser:deployuser /opt/infrawatch
```

---

## Useful Commands Cheat Sheet

```bash
# Container management
docker compose -f /opt/infrawatch/docker-compose.yml ps
docker compose -f /opt/infrawatch/docker-compose.yml logs -f
docker compose -f /opt/infrawatch/docker-compose.yml restart

# Disk usage
df -h
du -sh /opt/infrawatch/
docker system df

# Process monitoring
htop
ps aux | grep python
ps aux | grep nginx

# Network
netstat -tlnp
ss -tlnp

# Nginx logs
docker exec infrawatch-nginx cat /var/log/nginx/access.log | tail -20
docker exec infrawatch-nginx cat /var/log/nginx/error.log | tail -20

# App logs
docker exec infrawatch-app cat /app/logs/infrawatch.log | tail -50

# Firewall (UFW)
sudo ufw status
sudo ufw allow 80/tcp
sudo ufw allow 22/tcp
sudo ufw enable
```

---

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for common issues.

Quick checks:
```bash
# Is Docker running?
sudo systemctl status docker

# Are containers healthy?
docker compose ps

# Can the app be reached internally?
curl http://localhost:5000/healthz

# Any port conflicts?
sudo netstat -tlnp | grep ':80'
```
