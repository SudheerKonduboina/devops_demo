# InfraWatch — Linux Administration Reference

This document covers Linux commands used to manage the InfraWatch server.
All commands are meant to be run on Ubuntu 22.04 LTS.

---

## 1. User Management

```bash
# Create a new user
sudo useradd -m -s /bin/bash sudheer

# Create user with specific home directory
sudo useradd -m -d /home/sudheer -s /bin/bash sudheer

# Set password for user
sudo passwd sudheer

# Add user to a group (e.g., docker group)
sudo usermod -aG docker sudheer

# Add user to sudoers
sudo usermod -aG sudo sudheer

# View all users
cat /etc/passwd

# View all groups
cat /etc/group

# View current user
whoami

# View user's groups
groups sudheer

# Delete a user (and home directory)
sudo userdel -r sudheer

# Lock a user account (disable login)
sudo usermod -L sudheer

# Unlock a user account
sudo usermod -U sudheer

# Switch to another user
su - sudheer
sudo -u sudheer bash
```

---

## 2. File Permissions

Linux permissions: **owner | group | others** — Read(4) Write(2) Execute(1)

```bash
# View permissions
ls -la /opt/infrawatch/

# Change file owner
sudo chown ubuntu:ubuntu /opt/infrawatch/run.py

# Change directory owner recursively
sudo chown -R ubuntu:ubuntu /opt/infrawatch/

# Change permissions (number format)
chmod 755 scripts/deploy.sh    # rwxr-xr-x (owner:rwx, group:r-x, others:r-x)
chmod 644 .env.example         # rw-r--r-- (owner:rw, group:r, others:r)
chmod 600 .env                 # rw------- (owner only — protect secrets!)
chmod 400 infrawatch-key.pem   # r-------- (read-only — SSH key)

# Make scripts executable
chmod +x scripts/deploy.sh
chmod +x scripts/backup.sh

# Symbolic permission format
chmod u+x scripts/deploy.sh    # Add execute for owner (user)
chmod g-w .env                 # Remove write for group
chmod o-r secrets.txt          # Remove read for others
```

**Permission number reference:**
```
7 = rwx (4+2+1)
6 = rw- (4+2)
5 = r-x (4+1)
4 = r-- (4)
0 = --- (0)
```

---

## 3. systemctl — Service Management

```bash
# Check service status
sudo systemctl status docker
sudo systemctl status nginx
sudo systemctl status infrawatch-monitor

# Start a service
sudo systemctl start docker

# Stop a service
sudo systemctl stop nginx

# Restart a service
sudo systemctl restart infrawatch-monitor

# Enable service to start on boot
sudo systemctl enable docker

# Disable service from starting on boot
sudo systemctl disable nginx

# Reload service config without restart
sudo systemctl reload nginx

# View all running services
sudo systemctl list-units --type=service --state=running

# Check if service is enabled
sudo systemctl is-enabled docker

# Reload systemd after editing service file
sudo systemctl daemon-reload
```

---

## 4. journalctl — Log Viewing

```bash
# View logs for a service
sudo journalctl -u infrawatch-monitor

# Follow logs in real-time (like tail -f)
sudo journalctl -u infrawatch-monitor -f

# Last 50 lines
sudo journalctl -u infrawatch-monitor -n 50

# Logs since last boot
sudo journalctl -u docker -b

# Logs since specific time
sudo journalctl -u nginx --since "2024-01-15 10:00:00"
sudo journalctl -u nginx --since "1 hour ago"

# Filter by priority (err, warning, info, debug)
sudo journalctl -u docker -p err

# View kernel messages
sudo journalctl -k

# Clear old logs (keep last 100MB)
sudo journalctl --vacuum-size=100M
```

---

## 5. crontab — Scheduled Tasks

```bash
# Edit crontab for current user
crontab -e

# Edit crontab for specific user (as root)
sudo crontab -u ubuntu -e

# View current crontab
crontab -l

# Remove all cron jobs
crontab -r
```

**Cron syntax:**
```
# ┌───────── minute       (0–59)
# │ ┌─────── hour         (0–23)
# │ │ ┌───── day of month (1–31)
# │ │ │ ┌─── month        (1–12)
# │ │ │ │ ┌─ day of week  (0–7, 0 and 7 = Sunday)
# │ │ │ │ │
# * * * * * command

# Every minute
* * * * * echo "hello" >> /tmp/cron.log

# Every 5 minutes
*/5 * * * * bash /opt/infrawatch/scripts/health_check.sh

# Every day at 2 AM
0 2 * * * bash /opt/infrawatch/scripts/backup.sh

# Every Sunday at 3 AM
0 3 * * 0 bash /opt/infrawatch/scripts/cleanup.sh

# Every hour
0 * * * * python3 /opt/infrawatch/monitoring/health_monitor.py
```

---

## 6. Package Installation

```bash
# Update package list (always run before installing)
sudo apt-get update

# Install a package
sudo apt-get install -y docker.io
sudo apt-get install -y nginx git curl wget htop vim

# Install multiple packages
sudo apt-get install -y git curl wget htop vim net-tools

# Remove a package
sudo apt-get remove nginx

# Remove package and config files
sudo apt-get purge nginx

# Remove unused dependencies
sudo apt-get autoremove

# Search for a package
apt-cache search docker

# Show package info
apt-cache show nginx

# List installed packages
dpkg -l | grep nginx
```

---

## 7. Process Monitoring

```bash
# Interactive process viewer (press 'q' to exit)
htop
top

# List all processes
ps aux

# Find process by name
ps aux | grep python
ps aux | grep gunicorn

# Kill a process by PID
kill 12345
kill -9 12345    # Force kill

# Kill by process name
pkill python
killall gunicorn

# Find PID of a process
pgrep python
pidof gunicorn

# Monitor a specific PID
watch -n 2 "ps -p 12345 -o pid,ppid,pcpu,pmem,cmd"

# Background processes
nohup python3 monitoring/health_monitor.py &  # Run in background
jobs                                           # List background jobs
fg 1                                           # Bring job 1 to foreground
```

---

## 8. Disk Monitoring

```bash
# Disk usage by filesystem
df -h

# Disk usage of a directory
du -sh /opt/infrawatch/
du -sh /var/log/

# Top 10 largest directories in /var
du -h /var/ | sort -rh | head -10

# Check inode usage (important for log-heavy systems)
df -i

# Find large files (>100MB)
find / -size +100M -type f 2>/dev/null

# Check disk I/O
iostat -xz 1 5   # 5 samples, 1 second apart
```

---

## 9. Network Monitoring

```bash
# Show network interfaces and IPs
ip addr show
ifconfig   # older command

# Show routing table
ip route show
route -n

# Show open ports and listening processes
sudo netstat -tlnp
sudo ss -tlnp

# Test connectivity
ping google.com -c 4
ping 8.8.8.8 -c 4

# DNS lookup
nslookup google.com
dig google.com
host google.com

# Trace route to a host
traceroute google.com
mtr google.com   # Combined ping + traceroute

# Check bandwidth usage
vnstat             # Install: apt install vnstat
iftop              # Install: apt install iftop

# Test if a port is open (from inside server)
curl -v telnet://localhost:80
nc -zv localhost 80

# HTTP request with details
curl -v http://localhost/healthz
curl -s -o /dev/null -w "%{http_code}" http://localhost/healthz
```

---

## 10. Common System Checks

```bash
# System info
uname -a
hostnamectl
cat /etc/os-release

# Uptime and load average
uptime

# Memory usage
free -h
cat /proc/meminfo

# CPU info
lscpu
cat /proc/cpuinfo | grep "model name" | head -1

# Environment variables
env
echo $PATH
printenv HOME

# View running Docker containers
docker ps
docker stats --no-stream

# View all Docker images
docker images

# Inspect a container
docker inspect infrawatch-app

# Execute command inside container
docker exec -it infrawatch-app bash
docker exec infrawatch-app cat /etc/os-release
```

---

## SSH Key Setup (for CI/CD)

```bash
# Generate SSH key pair on your local machine
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/infrawatch_deploy

# Files created:
# ~/.ssh/infrawatch_deploy     ← PRIVATE key (add to GitHub Secrets as EC2_SSH_KEY)
# ~/.ssh/infrawatch_deploy.pub ← PUBLIC key (add to EC2 authorized_keys)

# Add public key to EC2
cat ~/.ssh/infrawatch_deploy.pub | ssh -i infrawatch-key.pem ubuntu@YOUR_IP \
    "cat >> ~/.ssh/authorized_keys"

# Test login with new key
ssh -i ~/.ssh/infrawatch_deploy ubuntu@YOUR_IP

# Paste private key content into GitHub Secret
cat ~/.ssh/infrawatch_deploy
# Copy everything including -----BEGIN and -----END lines
```
