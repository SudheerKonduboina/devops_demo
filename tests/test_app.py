import sys
import os
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from app import app


def test_home():
    c = app.test_client()
    r = c.get("/")
    assert r.status_code == 200
    assert b"Hello from Flask" in r.data

def test_healthz():
    c = app.test_client()
    r = c.get("/healthz")
    assert r.status_code == 200
    assert r.is_json
    assert r.get_json()["status"] == "ok"
