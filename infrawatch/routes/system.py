"""
System Routes
=============
Exposes real-time infrastructure metrics via REST API.

Endpoints:
    GET /api/v1/metrics    → CPU, memory, disk, network summary
    GET /api/v1/processes  → Top 10 processes by CPU usage
    GET /api/v1/network    → Network interface addresses
"""

import socket
import platform
from datetime import datetime, timezone

import psutil
from flask import Blueprint, current_app, jsonify

system_bp = Blueprint("system", __name__)


# ──────────────────────────────────────────────────────────────────────────────
# Helper Utilities
# ──────────────────────────────────────────────────────────────────────────────

def _bytes_to_gb(value: int) -> float:
    """Convert bytes to gigabytes, rounded to 2 decimal places."""
    return round(value / (1024 ** 3), 2)


def _bytes_to_mb(value: int) -> float:
    """Convert bytes to megabytes, rounded to 2 decimal places."""
    return round(value / (1024 ** 2), 2)


def _get_uptime() -> str:
    """Return human-readable system uptime string."""
    boot_time = datetime.fromtimestamp(psutil.boot_time(), tz=timezone.utc)
    delta = datetime.now(timezone.utc) - boot_time
    hours, remainder = divmod(int(delta.total_seconds()), 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours}h {minutes}m {seconds}s"


# ──────────────────────────────────────────────────────────────────────────────
# Endpoints
# ──────────────────────────────────────────────────────────────────────────────

@system_bp.route("/metrics")
def metrics():
    """
    Returns comprehensive system metrics:
    - CPU: usage %, core count
    - Memory: total, used, available, percent
    - Disk: total, used, free, percent (root partition)
    - Network: bytes sent/received
    - System: OS, hostname, uptime, Python version
    """
    cpu_pct = psutil.cpu_percent(interval=1)
    mem = psutil.virtual_memory()
    disk = psutil.disk_usage("/")
    net = psutil.net_io_counters()

    current_app.logger.info("Metrics requested | cpu=%.1f%%", cpu_pct)

    return jsonify(
        {
            "cpu": {
                "percent": cpu_pct,
                "cores_physical": psutil.cpu_count(logical=False),
                "cores_logical": psutil.cpu_count(logical=True),
            },
            "memory": {
                "total_gb": _bytes_to_gb(mem.total),
                "used_gb": _bytes_to_gb(mem.used),
                "available_gb": _bytes_to_gb(mem.available),
                "percent": mem.percent,
            },
            "disk": {
                "total_gb": _bytes_to_gb(disk.total),
                "used_gb": _bytes_to_gb(disk.used),
                "free_gb": _bytes_to_gb(disk.free),
                "percent": disk.percent,
            },
            "network": {
                "bytes_sent_mb": _bytes_to_mb(net.bytes_sent),
                "bytes_recv_mb": _bytes_to_mb(net.bytes_recv),
                "packets_sent": net.packets_sent,
                "packets_recv": net.packets_recv,
            },
            "system": {
                "os": platform.system(),
                "os_release": platform.release(),
                "hostname": socket.gethostname(),
                "python_version": platform.python_version(),
                "uptime": _get_uptime(),
            },
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    )


@system_bp.route("/processes")
def processes():
    """
    Returns top 10 processes sorted by CPU usage.
    Useful for identifying resource-heavy processes.
    """
    procs = []
    for proc in psutil.process_iter(
        ["pid", "name", "cpu_percent", "memory_percent", "status"]
    ):
        try:
            info = proc.info
            # Round float fields
            info["cpu_percent"] = round(info.get("cpu_percent") or 0.0, 2)
            info["memory_percent"] = round(info.get("memory_percent") or 0.0, 2)
            procs.append(info)
        except (psutil.NoSuchProcess, psutil.AccessDenied):
            pass

    top10 = sorted(procs, key=lambda x: x["cpu_percent"], reverse=True)[:10]

    current_app.logger.info("Processes requested | total=%d", len(procs))

    return jsonify(
        {
            "top_processes": top10,
            "total_processes": len(procs),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    )


@system_bp.route("/network")
def network():
    """
    Returns all network interface addresses.
    Covers IPv4 and IPv6 assignments per interface.
    """
    interfaces = {}
    for iface_name, addr_list in psutil.net_if_addrs().items():
        interfaces[iface_name] = [
            {
                "family": str(addr.family),
                "address": addr.address,
                "netmask": addr.netmask,
            }
            for addr in addr_list
        ]

    return jsonify(
        {
            "hostname": socket.gethostname(),
            "interfaces": interfaces,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    )
