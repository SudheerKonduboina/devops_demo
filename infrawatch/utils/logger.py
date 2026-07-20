"""
Logger Utility
==============
Configures structured, rotating file logging for the Flask app.

Features:
- Console output (stdout) for Docker log capture
- Rotating file handler: 10 MB max, 5 backup files
- Configurable log level via LOG_LEVEL env var
- ISO timestamp format
"""

import logging
import os
import sys
from logging.handlers import RotatingFileHandler


def setup_logger(app) -> None:
    """
    Attaches console and rotating file handlers to the Flask app logger.
    Called once during application factory setup.

    Environment variables:
        LOG_LEVEL  — DEBUG, INFO, WARNING, ERROR (default: INFO)
        LOG_FILE   — path to log file (default: logs/infrawatch.log)
    """
    log_level_name = os.getenv("LOG_LEVEL", "INFO").upper()
    log_level = getattr(logging, log_level_name, logging.INFO)
    log_file = os.getenv("LOG_FILE", "logs/infrawatch.log")

    # ── Formatter ────────────────────────────────────────────────────────────
    formatter = logging.Formatter(
        fmt="[%(asctime)s] %(levelname)-8s | %(module)s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # ── Console Handler (captured by Docker: docker logs) ────────────────────
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setFormatter(formatter)
    console_handler.setLevel(log_level)

    # ── Rotating File Handler ─────────────────────────────────────────────────
    os.makedirs(os.path.dirname(log_file), exist_ok=True)
    file_handler = RotatingFileHandler(
        filename=log_file,
        maxBytes=10 * 1024 * 1024,  # 10 MB per file
        backupCount=5,               # Keep 5 backup files
        encoding="utf-8",
    )
    file_handler.setFormatter(formatter)
    file_handler.setLevel(log_level)

    # ── Attach to Flask app logger ────────────────────────────────────────────
    app.logger.setLevel(log_level)
    app.logger.addHandler(console_handler)
    app.logger.addHandler(file_handler)

    # Prevent double-logging via root logger propagation
    app.logger.propagate = False
