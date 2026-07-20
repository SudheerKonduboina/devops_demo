"""
InfraWatch — Application Factory
=================================
Creates and configures the Flask application.

Usage:
    from infrawatch import create_app
    app = create_app()
"""

import os
import logging

from flask import Flask
from flask_cors import CORS

from .routes.health import health_bp
from .routes.system import system_bp
from .utils.logger import setup_logger


def create_app() -> Flask:
    """
    Application factory pattern.
    Returns a fully configured Flask instance.
    """
    app = Flask(__name__)
    CORS(app)

    # ── Load configuration from environment ──────────────────────────────────
    app.config.update(
        APP_NAME=os.getenv("APP_NAME", "InfraWatch"),
        APP_VERSION=os.getenv("APP_VERSION", "1.0.0"),
        ENVIRONMENT=os.getenv("ENVIRONMENT", "production"),
        SECRET_KEY=os.getenv("SECRET_KEY", "change-this-in-production"),
        TESTING=os.getenv("TESTING", "false").lower() == "true",
    )

    # ── Setup structured logging ──────────────────────────────────────────────
    setup_logger(app)

    # ── Register route blueprints ─────────────────────────────────────────────
    app.register_blueprint(health_bp)
    app.register_blueprint(system_bp, url_prefix="/api/v1")

    app.logger.info(
        "InfraWatch started | env=%s | version=%s",
        app.config["ENVIRONMENT"],
        app.config["APP_VERSION"],
    )

    return app
