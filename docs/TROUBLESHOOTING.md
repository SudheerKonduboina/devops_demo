# InfraWatch — Troubleshooting Guide

Common issues encountered while setting up and running InfraWatch, with solutions.

---

## 1. Docker Issues

### Container won't start

```bash
# Check what happened
docker compose logs app
docker compose logs nginx

# Check if port 80 is already used
sudo lsof -i :80
sudo netstat -tlnp | grep ':80'

# Kill the process using port 80
sudo systemctl stop nginx   # If system Nginx is running
sudo kill -9 $(lsof -ti:80)
```

### "Permission denied" when running docker

```bash
# Add yourself to docker group
sudo usermod -aG docker $USER

# Apply without logging out
newgrp docker

# Or use sudo
sudo docker compose up -d
```

### Container health check failing

```bash
# View detailed container info
docker inspect infrawatch-app | grep -A 20 Health

# Test health endpoint manually
docker exec infrawatch-app curl -s http://localhost:5000/healthz

# Check if Gunicorn is actually running
docker exec infrawatch-app ps aux | grep gunicorn

# Force rebuild
docker compose down
docker compose build --no-cache
docker compose up -d
```

### "No space left on device" error

```bash
# Check disk usage
df -h /

# Clean up Docker resources
docker system prune -a -f
docker volume prune -f

# Find large files
du -sh /var/lib/docker/
sudo du -h /var/lib/ | sort -rh | head -20
```

---

## 2. Application Issues

### Flask app returns 500 Internal Server Error

```bash
# Check Flask logs
docker compose logs app --tail=50

# Run Python directly to see the error
docker exec -it infrawatch-app python3 -c "from infrawatch import create_app; app = create_app()"

# Check if all dependencies are installed
docker exec infrawatch-app pip list | grep flask
docker exec infrawatch-app pip list | grep psutil
```

### "Module not found: infrawatch" error

```bash
# Make sure run.py is in the container
docker exec infrawatch-app ls -la /app/

# Check Python path inside container
docker exec infrawatch-app python3 -c "import sys; print(sys.path)"

# The issue might be the .env file isn't loaded
docker exec infrawatch-app cat /app/.env  # Should exist
```

### Port 5000 is already in use

```bash
# Find what's using port 5000
sudo lsof -i :5000
sudo fuser 5000/tcp

# Kill it
sudo fuser -k 5000/tcp

# Or change Flask port in .env
echo "PORT=5001" >> .env
```

---

## 3. Nginx Issues

### Nginx returns 502 Bad Gateway

**Cause:** Nginx can't reach the Flask app.

```bash
# Check if Flask app is running
docker compose ps app

# Check the container name in nginx.conf
# Should match the service name in docker-compose.yml
grep "server app:" nginx/nginx.conf

# Test Flask directly (bypass Nginx)
curl http://localhost:5000/healthz   # Should work

# Check Docker network
docker network inspect infrawatch_network
```

### Nginx returns 504 Gateway Timeout

**Cause:** Flask is taking too long to respond.

```bash
# Check nginx.conf timeout values
grep "timeout" nginx/nginx.conf

# Check Flask is not stuck
docker exec infrawatch-app ps aux
docker compose logs app --tail=20

# Increase timeout in nginx.conf
# proxy_read_timeout 60s;  (change 30s to 60s)
docker compose restart nginx
```

### "Permission denied" reading nginx.conf

```bash
# Check config file permissions
ls -la nginx/nginx.conf

# Should be readable
chmod 644 nginx/nginx.conf

# Verify Nginx config is valid
docker exec infrawatch-nginx nginx -t
```

---

## 4. CI/CD Pipeline Issues

### "Permission denied (publickey)" in GitHub Actions

**Cause:** `EC2_SSH_KEY` secret is wrong or EC2's authorized_keys doesn't have the public key.

```bash
# On EC2: verify authorized_keys
cat ~/.ssh/authorized_keys

# Test SSH manually from local machine
ssh -i ~/.ssh/infrawatch_deploy ubuntu@YOUR_EC2_IP

# The secret value in GitHub must be the PRIVATE key content (not .pub)
# It should start with: -----BEGIN OPENSSH PRIVATE KEY-----
cat ~/.ssh/infrawatch_deploy
```

### "No such file or directory: /opt/infrawatch"

```bash
# Create the directory on EC2
ssh ubuntu@EC2_IP "sudo mkdir -p /opt/infrawatch && sudo chown ubuntu:ubuntu /opt/infrawatch"

# Then clone the repo
ssh ubuntu@EC2_IP "git clone https://github.com/SudheerKonduboina/devops_demo.git /opt/infrawatch"
```

### GitHub Actions workflow not triggering

```bash
# Check workflow file location
ls .github/workflows/ci-cd.yml

# Verify the branch name in ci-cd.yml matches your branch
grep "branches:" .github/workflows/ci-cd.yml

# Check Actions tab in GitHub for any visible errors
# Repository → Actions → Select the workflow
```

### Black formatting check fails

```bash
# Auto-format locally
pip install black
black infrawatch/ run.py app.py

# Then commit the formatted files
git add -A
git commit -m "style: auto-format with black"
git push
```

---

## 5. AWS Issues

### Can't SSH into EC2

```bash
# Check key file permissions
ls -la infrawatch-key.pem   # Should be: -r--------
chmod 400 infrawatch-key.pem

# Verify you're using the right user (ubuntu for Ubuntu AMI)
ssh -i infrawatch-key.pem ubuntu@YOUR_IP   # NOT root@ or ec2-user@

# Check Security Group allows port 22 from your IP
# AWS Console → EC2 → Security Groups → Inbound Rules

# Check if Elastic IP is correctly associated
aws ec2 describe-instances --instance-ids YOUR_INSTANCE_ID
```

### EC2 can't reach GitHub (git pull fails)

```bash
# Test internet connectivity
ping 8.8.8.8
curl -v https://github.com

# Check outbound security group allows all traffic
# AWS Console → Security Group → Outbound → All traffic → 0.0.0.0/0

# If in a VPC, check route table has Internet Gateway
```

---

## 6. Backup/Restore Issues

### backup.sh fails: "No such volume"

```bash
# Check if Docker volumes exist
docker volume ls | grep infrawatch

# If volumes don't exist yet (no deployments):
docker compose up -d   # Start containers to create volumes
# Then run backup again
```

### restore.sh: "Health check failed after restore"

```bash
# Check the restored containers
docker compose ps

# View logs
docker compose logs app

# Try manual restart
docker compose down
docker compose up -d --build

# If problem persists, check .env file
cat /opt/infrawatch/.env
```

---

## 7. Monitoring Issues

### health_monitor.py can't connect to API

```bash
# Check if containers are running
docker compose ps

# Verify API URL in .env
grep MONITOR_API_URL .env

# Test the URL manually
curl http://localhost/healthz

# If using inside Docker, URL should be:
# MONITOR_API_URL=http://app:5000/healthz  (not localhost)
```

### Monitor not running as systemd service

```bash
# Check service status
sudo systemctl status infrawatch-monitor

# View detailed errors
sudo journalctl -u infrawatch-monitor -n 50 --no-pager

# Common fix: wrong Python path
which python3    # Get Python path
# Update ExecStart in service file to use this path

sudo systemctl daemon-reload
sudo systemctl restart infrawatch-monitor
```

---

## Quick Diagnostic Commands

```bash
# One-shot: show everything important
echo "=== CONTAINERS ===" && docker compose ps
echo "=== DISK ===" && df -h /
echo "=== MEMORY ===" && free -h
echo "=== CPU ===" && top -bn1 | head -5
echo "=== API ===" && curl -s http://localhost/healthz
echo "=== LOGS (last 10) ===" && docker compose logs --tail=10
```
