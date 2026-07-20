"""
app.py — Gunicorn compatibility alias
======================================
This file exists so Gunicorn can be invoked as:
    gunicorn app:app

All application logic lives in the `infrawatch/` package.
For development, use: python run.py
"""

from dotenv import load_dotenv

load_dotenv()

from infrawatch import create_app  # noqa: E402

app = create_app()
