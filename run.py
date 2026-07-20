"""
InfraWatch — Application Entry Point
=====================================
Development:  python run.py
Production:   gunicorn --bind 0.0.0.0:5000 run:app
"""

import os

from dotenv import load_dotenv

# Load .env file before importing app (so env vars are available)
load_dotenv()

from infrawatch import create_app  # noqa: E402

app = create_app()

if __name__ == "__main__":
    port = int(os.getenv("PORT", 5000))
    debug = os.getenv("FLASK_DEBUG", "false").lower() == "true"
    app.run(host="0.0.0.0", port=port, debug=debug)
