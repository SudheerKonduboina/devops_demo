# InfraWatch — Networking Concepts

This document explains the networking fundamentals used in the InfraWatch project,
specifically tailored for a DevOps Intern interview.

---

## 1. TCP/IP — The Foundation

**TCP/IP** is the communication protocol that powers the entire internet.

### IP (Internet Protocol)
- Assigns a unique **address** to every device on a network
- Two versions: **IPv4** (192.168.1.1) and **IPv6** (::1)
- Like a postal address — tells packets where to go

### TCP (Transmission Control Protocol)
- Ensures reliable, ordered data delivery
- Uses a **3-way handshake** before data transfer:
  ```
  Client → Server: SYN  (I want to connect)
  Server → Client: SYN-ACK  (OK, I accept)
  Client → Server: ACK  (Great, let's talk)
  ```
- Used by: HTTP, HTTPS, SSH, FTP

### UDP (User Datagram Protocol)
- Faster but unreliable (no guarantee of delivery)
- Used by: DNS queries, video streaming, gaming

### In InfraWatch:
```
User's PC (TCP client)  →  AWS EC2 (TCP server) on port 80
          ↑
          TCP connection established via 3-way handshake
          HTTP request sent over this connection
          Response received
          Connection closed
```

---

## 2. DNS — Domain Name System

**DNS** translates human-readable names to IP addresses.

```
User types: http://infrawatch.example.com
          ↓
DNS query: "What is the IP for infrawatch.example.com?"
          ↓
DNS server responds: "13.233.45.67"
          ↓
Browser connects to: 13.233.45.67:80
```

### DNS Record Types

| Record | Purpose | Example |
|--------|---------|---------|
| A | Maps domain → IPv4 | `infrawatch.com → 13.233.45.67` |
| AAAA | Maps domain → IPv6 | `infrawatch.com → 2001:db8::1` |
| CNAME | Alias for another domain | `www.infrawatch.com → infrawatch.com` |
| MX | Mail server | `infrawatch.com → mail.infrawatch.com` |
| TXT | Text records (verification) | SPF, DKIM |

### In InfraWatch:
- We use an **Elastic IP** (static IP) instead of a domain for simplicity
- In production, you'd: Point your domain's A record → Elastic IP
- Docker containers resolve each other by **service name** (internal DNS):
  - Nginx finds Flask by hostname `app` → Docker resolves to container IP

```bash
# Test DNS resolution
nslookup google.com
dig google.com
host google.com

# Check what IP a hostname resolves to inside Docker
docker exec infrawatch-nginx nslookup app
```

---

## 3. DHCP — Dynamic Host Configuration Protocol

**DHCP** automatically assigns IP addresses to devices on a network.

**Without DHCP:** You'd manually configure IP, subnet, gateway, DNS for every device.

**With DHCP:**
```
Device joins network → Broadcasts "I need an IP!"
DHCP server → Responds with: IP, Subnet Mask, Gateway, DNS
Device → Uses assigned IP for lease duration (e.g., 24 hours)
```

### In InfraWatch:
- **AWS EC2** gets its private IP via DHCP from AWS's internal DHCP server
- **Docker containers** get IPs from Docker's built-in DHCP server (172.17.0.0/16 range)
- **EC2 Elastic IP** — static public IP that doesn't change (unlike DHCP-assigned IPs)

```bash
# View Docker network DHCP assignments
docker network inspect infrawatch_network

# View EC2's DHCP-assigned private IP
ip addr show eth0
```

---

## 4. HTTP vs HTTPS

### HTTP (HyperText Transfer Protocol)
- Data sent in **plaintext** — anyone can read it
- Default port: **80**
- Example: `http://13.233.45.67/api/v1/metrics`

### HTTPS (HTTP Secure)
- HTTP + **TLS encryption** — data is encrypted
- Default port: **443**
- Example: `https://infrawatch.example.com/api/v1/metrics`
- Requires an **SSL certificate** (free via Let's Encrypt)

### Why InfraWatch uses HTTP (not HTTPS):
This is a demo project on a bare IP. HTTPS requires:
1. A registered domain name
2. SSL certificate (free with Let's Encrypt / Certbot)

**In production**, you would:
```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx

# Obtain SSL certificate
sudo certbot --nginx -d infrawatch.example.com

# Auto-renewal (Certbot adds this automatically)
sudo certbot renew --dry-run
```

---

## 5. Ports

A **port** is like an apartment number inside a building (IP address).

| Port | Protocol | Usage in InfraWatch |
|------|----------|---------------------|
| 22 | SSH | Remote server management |
| 80 | HTTP | Public web traffic → Nginx |
| 443 | HTTPS | Encrypted web (future) |
| 5000 | HTTP (internal) | Flask/Gunicorn (not exposed publicly) |

### Port Visibility:
```
Internet → EC2 port 80  (Nginx — PUBLIC)
         → EC2 port 22  (SSH — YOUR IP ONLY)
         
Internal (Docker network only):
         app:5000  (Flask — PRIVATE, only Nginx can reach)
```

```bash
# View all listening ports on EC2
sudo ss -tlnp
sudo netstat -tlnp

# Check if port 80 is open from outside
curl http://YOUR_EC2_IP:80/healthz

# Check if port 5000 is NOT exposed (should timeout)
curl --max-time 3 http://YOUR_EC2_IP:5000/healthz
```

---

## 6. Reverse Proxy (Nginx)

A **reverse proxy** sits in front of your application servers and:
- Receives client requests
- Forwards them to the appropriate backend server
- Returns the response to the client

```
Client → [Nginx :80] → [Flask :5000]
                ↑ Reverse Proxy
```

**Why is it called "reverse"?**
- A regular **forward proxy** sits between clients and the internet (like a VPN)
- A **reverse proxy** sits between the internet and your servers (protecting them)

### What Nginx does for InfraWatch:

1. **Load distribution** — if you had 3 Flask containers, Nginx distributes traffic
2. **Rate limiting** — blocks IPs that send too many requests
3. **Gzip compression** — shrinks response size by ~70%
4. **Security headers** — protects against clickjacking, XSS
5. **Access logging** — records every request
6. **SSL termination** — handles HTTPS (future)

```bash
# Test Nginx config syntax
docker exec infrawatch-nginx nginx -t

# Reload Nginx config without downtime
docker exec infrawatch-nginx nginx -s reload

# View Nginx access log (last 20 lines)
docker exec infrawatch-nginx tail -20 /var/log/nginx/access.log
```

---

## 7. SSH (Secure Shell)

**SSH** creates an encrypted tunnel for remote server management.

```bash
# Basic SSH connection
ssh -i key.pem ubuntu@13.233.45.67

# SSH with port forwarding (tunnel port 5000 to local 8080)
ssh -i key.pem -L 8080:localhost:5000 ubuntu@13.233.45.67

# Copy file to server
scp -i key.pem deploy.sh ubuntu@13.233.45.67:/tmp/

# Copy file from server
scp -i key.pem ubuntu@13.233.45.67:/var/log/app.log ./

# SSH config file (save connection details)
# Edit ~/.ssh/config:
Host infrawatch
    HostName 13.233.45.67
    User ubuntu
    IdentityFile ~/.ssh/infrawatch-key.pem

# Then connect with just:
ssh infrawatch
```

### SSH Key Pair Explained:
```
Your local machine           EC2 Server
┌────────────────┐          ┌────────────────┐
│ Private Key    │  ──SSH── │ Public Key     │
│ (SECRET!       │          │ (in            │
│  never share)  │          │  authorized_   │
│                │          │  keys)         │
└────────────────┘          └────────────────┘

It's like: Private key = your house key
           Public key = your door lock
You can share the lock design (public key) freely,
but only the actual key (private key) opens the door.
```

---

## 8. Firewall

A **firewall** controls which network traffic is allowed in/out.

### UFW (Uncomplicated Firewall) on Ubuntu:

```bash
# Check firewall status
sudo ufw status verbose

# Enable firewall
sudo ufw enable

# Allow SSH (always do this BEFORE enabling!)
sudo ufw allow 22/tcp

# Allow HTTP
sudo ufw allow 80/tcp

# Allow HTTPS
sudo ufw allow 443/tcp

# Allow specific IP only (SSH from your IP)
sudo ufw allow from 203.0.113.5 to any port 22

# Block an IP
sudo ufw deny from 192.168.1.100

# Delete a rule
sudo ufw delete allow 80/tcp

# Show numbered rules
sudo ufw status numbered
```

### AWS Security Groups:
Security Groups are **AWS-level firewalls** — they work even before traffic reaches the EC2 instance.

```
Internet → AWS Security Group (firewall) → EC2 instance

Inbound rules (what's allowed in):
  SSH: port 22 from My IP (0.0.0.0/0 in dev)
  HTTP: port 80 from 0.0.0.0/0

Outbound rules (what the server can send out):
  All traffic (needed for apt-get update, git pull, etc.)
```

---

## Networking Summary Table

| Concept | What it does | InfraWatch usage |
|---------|-------------|------------------|
| TCP/IP | Communication protocol | HTTP over TCP between all components |
| DNS | Name → IP resolution | Docker container discovery by name |
| DHCP | Auto-assigns IPs | EC2 private IP, Docker container IPs |
| HTTP | Web protocol | API communication (port 80) |
| Ports | Service endpoints | 80 (Nginx), 5000 (Flask), 22 (SSH) |
| Reverse Proxy | Traffic router | Nginx → Flask |
| SSH | Encrypted remote access | Deploy from GitHub Actions to EC2 |
| Firewall | Traffic control | AWS Security Groups + UFW |
