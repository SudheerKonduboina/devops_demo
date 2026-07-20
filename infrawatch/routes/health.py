"""
Health Routes
=============
Provides liveness and readiness probes for Docker/Kubernetes health checks.

Endpoints:
    GET /           → Service info
    GET /healthz    → Liveness probe  (is the app alive?)
    GET /readyz     → Readiness probe (is the app ready for traffic?)
"""

from datetime import datetime, timezone

from flask import Blueprint, current_app, jsonify

health_bp = Blueprint("health", __name__)


@health_bp.route("/")
def index():
    """
    Root endpoint — returns service metadata.
    Useful for verifying the correct version is deployed.
    """
    return jsonify(
        {
            "service": current_app.config["APP_NAME"],
            "version": current_app.config["APP_VERSION"],
            "environment": current_app.config["ENVIRONMENT"],
            "status": "running",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "docs": "/api/v1/metrics",
        }
    )


@health_bp.route("/healthz")
def health():
    """
    Liveness probe — used by Docker HEALTHCHECK and load balancers.
    Returns 200 OK when the application process is alive.
    """
    return (
        jsonify(
            {
                "status": "ok",
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }
        ),
        200,
    )


@health_bp.route("/readyz")
def ready():
    """
    Readiness probe — used by orchestrators (Kubernetes, ECS) to determine
    if the pod/container should receive traffic.
    """
    return (
        jsonify(
            {
                "status": "ready",
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }
        ),
        200,
    )
