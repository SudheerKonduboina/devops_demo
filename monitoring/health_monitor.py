#!/usr/bin/env python3
"""
InfraWatch Health Monitor Daemon
==================================
A Python automation script that continuously monitors server health
and logs alerts. Can be run as a background process or systemd service.

Features:
  - Monitors API health endpoint with response time measurement
  - Tracks CPU, memory, disk usage with configurable thresholds
  - Checks internet connectivity
  - Sends email alerts when thresholds are exceeded (optional)
  - Structured log output with timestamps
  - Graceful shutdown on SIGINT/SIGTERM

Usage:
  python3 monitoring/health_monitor.py

Run as systemd service:
  See docs/DEPLOYMENT_GUIDE.md → "Run Monitor as systemd Service"

Environment variables:
  MONITOR_API_URL    — URL to check (default: http://localhost/healthz)
  MONITOR_INTERVAL   — Seconds between checks (default: 60)
  CPU_THRESHOLD      — CPU % alert level (default: 85.0)
  MEMORY_THRESHOLD   — Memory % alert level (default: 85.0)
  DISK_THRESHOLD     — Disk % alert level (default: 90.0)
  ALERT_EMAIL        — Email to send alerts (optional)
  SMTP_USER / SMTP_PASS — SMTP credentials for alerts (optional)
"""

import logging
import os
import platform
import signal
import smtplib
import socket
import sys
import time
from datetime import datetime, timezone
from email.mime.text import MIMEText
from typing import Any

import psutil
import requests

# ─────────────────────────────────────────────────────────────────────────────
# Configuration (environment variables with sensible defaults)
# ─────────────────────────────────────────────────────────────────────────────
API_URL = os.getenv("MONITOR_API_URL", "http://localhost/healthz")
CHECK_INTERVAL = int(os.getenv("MONITOR_INTERVAL", "60"))
LOG_FILE = os.getenv("LOG_FILE", "logs/monitor.log")
CPU_THRESHOLD = float(os.getenv("CPU_THRESHOLD", "85.0"))
MEMORY_THRESHOLD = float(os.getenv("MEMORY_THRESHOLD", "85.0"))
DISK_THRESHOLD = float(os.getenv("DISK_THRESHOLD", "90.0"))

# Email alert config (all optional)
ALERT_EMAIL = os.getenv("ALERT_EMAIL", "")
SMTP_HOST = os.getenv("SMTP_HOST", "smtp.gmail.com")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASS = os.getenv("SMTP_PASS", "")

# Track consecutive alert count to avoid alert spam
_alert_cooldown: dict[str, int] = {}
ALERT_COOLDOWN_CYCLES = 5  # Only re-alert after 5 cycles of silence


# ─────────────────────────────────────────────────────────────────────────────
# Logging Setup
# ─────────────────────────────────────────────────────────────────────────────
def _setup_logging() -> logging.Logger:
    """Configure file + console logger."""
    os.makedirs(os.path.dirname(LOG_FILE) if os.path.dirname(LOG_FILE) else ".", exist_ok=True)

    formatter = logging.Formatter(
        fmt="[%(asctime)s] %(levelname)-8s %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    logger = logging.getLogger("InfraWatchMonitor")
    logger.setLevel(logging.DEBUG)

    # Console handler
    ch = logging.StreamHandler(sys.stdout)
    ch.setFormatter(formatter)
    logger.addHandler(ch)

    # File handler
    try:
        fh = logging.FileHandler(LOG_FILE, encoding="utf-8")
        fh.setFormatter(formatter)
        logger.addHandler(fh)
    except Exception as e:
        logger.warning("Could not create log file %s: %s", LOG_FILE, e)

    return logger


logger = _setup_logging()


# ─────────────────────────────────────────────────────────────────────────────
# Health Check Functions
# ─────────────────────────────────────────────────────────────────────────────
def check_api(url: str) -> dict[str, Any]:
    """
    Sends HTTP GET to the health endpoint.
    Returns status, HTTP code, and response time in ms.
    """
    try:
        start = time.monotonic()
        resp = requests.get(url, timeout=5)
        elapsed_ms = round((time.monotonic() - start) * 1000, 1)
        return {
            "ok": resp.status_code == 200,
            "http_code": resp.status_code,
            "response_ms": elapsed_ms,
        }
    except requests.exceptions.ConnectionError:
        return {"ok": False, "http_code": 0, "error": "Connection refused"}
    except requests.exceptions.Timeout:
        return {"ok": False, "http_code": 0, "error": "Timeout (5s)"}
    except Exception as exc:
        return {"ok": False, "http_code": 0, "error": str(exc)}


def check_cpu() -> dict[str, Any]:
    """Measure CPU usage over 2 seconds."""
    percent = psutil.cpu_percent(interval=2)
    return {
        "percent": percent,
        "cores": psutil.cpu_count(logical=True),
        "alert": percent > CPU_THRESHOLD,
    }


def check_memory() -> dict[str, Any]:
    """Check virtual memory utilization."""
    mem = psutil.virtual_memory()
    return {
        "percent": mem.percent,
        "used_gb": round(mem.used / 1024 ** 3, 2),
        "total_gb": round(mem.total / 1024 ** 3, 2),
        "alert": mem.percent > MEMORY_THRESHOLD,
    }


def check_disk(path: str = "/") -> dict[str, Any]:
    """Check disk partition utilization."""
    disk = psutil.disk_usage(path)
    return {
        "path": path,
        "percent": disk.percent,
        "free_gb": round(disk.free / 1024 ** 3, 2),
        "total_gb": round(disk.total / 1024 ** 3, 2),
        "alert": disk.percent > DISK_THRESHOLD,
    }


def check_internet(host: str = "8.8.8.8", port: int = 53, timeout: int = 3) -> bool:
    """Test internet connectivity by attempting a TCP connection to Google DNS."""
    try:
        socket.setdefaulttimeout(timeout)
        socket.create_connection((host, port))
        return True
    except OSError:
        return False


# ─────────────────────────────────────────────────────────────────────────────
# Alerting
# ─────────────────────────────────────────────────────────────────────────────
def send_email_alert(subject: str, body: str) -> None:
    """
    Sends a plain-text email alert via SMTP with TLS.
    Silently skips if ALERT_EMAIL or SMTP_USER is not configured.
    """
    if not ALERT_EMAIL or not SMTP_USER:
        return
    try:
        msg = MIMEText(body, "plain")
        msg["Subject"] = f"[InfraWatch ALERT] {subject}"
        msg["From"] = SMTP_USER
        msg["To"] = ALERT_EMAIL
        with smtplib.SMTP(SMTP_HOST, SMTP_PORT, timeout=10) as server:
            server.ehlo()
            server.starttls()
            server.login(SMTP_USER, SMTP_PASS)
            server.send_message(msg)
        logger.info("Alert email sent to %s", ALERT_EMAIL)
    except Exception as exc:
        logger.error("Failed to send alert email: %s", exc)


def _should_alert(key: str) -> bool:
    """Cooldown check — only alert every ALERT_COOLDOWN_CYCLES cycles."""
    count = _alert_cooldown.get(key, 0)
    if count == 0:
        _alert_cooldown[key] = ALERT_COOLDOWN_CYCLES
        return True
    _alert_cooldown[key] = count - 1
    return False


def _reset_alert(key: str) -> None:
    """Reset cooldown counter when condition clears."""
    _alert_cooldown.pop(key, None)


# ─────────────────────────────────────────────────────────────────────────────
# Main Check Loop
# ─────────────────────────────────────────────────────────────────────────────
def run_check() -> None:
    """Execute one full health check cycle and log results."""
    api = check_api(API_URL)
    cpu = check_cpu()
    mem = check_memory()
    disk = check_disk("/")
    internet = check_internet()
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # One-liner summary log
    api_icon = "✅" if api["ok"] else "❌"
    logger.info(
        "%s API=%s(%dms) | CPU=%.1f%% | MEM=%.1f%% | DISK=%.1f%% | NET=%s",
        api_icon,
        api.get("http_code", "ERR"),
        api.get("response_ms", 0),
        cpu["percent"],
        mem["percent"],
        disk["percent"],
        "ok" if internet else "DOWN",
    )

    # ── Alerts ──────────────────────────────────────────────────────────────
    alerts: list[str] = []

    if not api["ok"]:
        msg = f"API health check FAILED: {api.get('error') or api.get('http_code')}"
        if _should_alert("api"):
            alerts.append(msg)
            logger.critical("🚨 %s", msg)
    else:
        _reset_alert("api")

    if cpu["alert"]:
        msg = f"High CPU: {cpu['percent']:.1f}% (threshold: {CPU_THRESHOLD}%)"
        if _should_alert("cpu"):
            alerts.append(msg)
            logger.warning("⚠️  %s", msg)
    else:
        _reset_alert("cpu")

    if mem["alert"]:
        msg = f"High Memory: {mem['percent']:.1f}% (threshold: {MEMORY_THRESHOLD}%)"
        if _should_alert("mem"):
            alerts.append(msg)
            logger.warning("⚠️  %s", msg)
    else:
        _reset_alert("mem")

    if disk["alert"]:
        msg = f"High Disk: {disk['percent']:.1f}% on {disk['path']} (threshold: {DISK_THRESHOLD}%)"
        if _should_alert("disk"):
            alerts.append(msg)
            logger.critical("🚨 %s", msg)
    else:
        _reset_alert("disk")

    if not internet:
        msg = "Internet connectivity LOST"
        if _should_alert("net"):
            alerts.append(msg)
            logger.critical("🚨 %s", msg)
    else:
        _reset_alert("net")

    if alerts:
        body = (
            f"Server: {platform.node()}\n"
            f"Time:   {ts}\n\n"
            f"Alerts:\n" + "\n".join(f"  • {a}" for a in alerts)
        )
        send_email_alert(f"{len(alerts)} alert(s) on {platform.node()}", body)


# ─────────────────────────────────────────────────────────────────────────────
# Entry Point
# ─────────────────────────────────────────────────────────────────────────────
def main() -> None:
    # Graceful shutdown handlers
    def _shutdown(signum, frame):
        logger.info("Shutdown signal received. Stopping monitor.")
        sys.exit(0)

    signal.signal(signal.SIGINT, _shutdown)
    signal.signal(signal.SIGTERM, _shutdown)

    logger.info("=" * 55)
    logger.info("InfraWatch Health Monitor STARTED")
    logger.info("  Host     : %s (%s %s)", platform.node(), platform.system(), platform.release())
    logger.info("  API URL  : %s", API_URL)
    logger.info("  Interval : %ds", CHECK_INTERVAL)
    logger.info("  Thresholds: CPU=%.0f%% MEM=%.0f%% DISK=%.0f%%", CPU_THRESHOLD, MEMORY_THRESHOLD, DISK_THRESHOLD)
    logger.info("  Alert email: %s", ALERT_EMAIL if ALERT_EMAIL else "disabled")
    logger.info("=" * 55)

    while True:
        try:
            run_check()
        except Exception as exc:
            logger.error("Unexpected error in check cycle: %s", exc, exc_info=True)
        time.sleep(CHECK_INTERVAL)


if __name__ == "__main__":
    main()
