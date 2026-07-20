"""
InfraWatch Test Suite
=====================
Tests all API endpoints using Flask's built-in test client.
No real server needed — tests run in-process.

Run with: pytest tests/ -v
"""

import os
import sys

# Add project root to path so we can import infrawatch
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pytest

from infrawatch import create_app


# ─────────────────────────────────────────────────────────────────────────────
# Fixtures
# ─────────────────────────────────────────────────────────────────────────────

@pytest.fixture(scope="module")
def client():
    """
    Creates a test client for the Flask application.
    scope="module" means one client is shared across all tests in this file.
    """
    app = create_app()
    app.config["TESTING"] = True
    app.config["ENVIRONMENT"] = "testing"
    with app.test_client() as test_client:
        yield test_client


# ─────────────────────────────────────────────────────────────────────────────
# Health Endpoint Tests
# ─────────────────────────────────────────────────────────────────────────────

class TestRootEndpoint:
    """Tests for GET /"""

    def test_returns_200(self, client):
        resp = client.get("/")
        assert resp.status_code == 200, f"Expected 200, got {resp.status_code}"

    def test_returns_json(self, client):
        resp = client.get("/")
        assert resp.is_json, "Response should be JSON"

    def test_has_required_fields(self, client):
        data = client.get("/").get_json()
        assert "service" in data
        assert "version" in data
        assert "status" in data
        assert "environment" in data
        assert "timestamp" in data

    def test_status_is_running(self, client):
        data = client.get("/").get_json()
        assert data["status"] == "running"

    def test_service_name_is_infrawatch(self, client):
        data = client.get("/").get_json()
        assert data["service"] == "InfraWatch"


class TestHealthzEndpoint:
    """Tests for GET /healthz (liveness probe)"""

    def test_returns_200(self, client):
        resp = client.get("/healthz")
        assert resp.status_code == 200

    def test_returns_json(self, client):
        resp = client.get("/healthz")
        assert resp.is_json

    def test_status_is_ok(self, client):
        data = client.get("/healthz").get_json()
        assert data["status"] == "ok"

    def test_has_timestamp(self, client):
        data = client.get("/healthz").get_json()
        assert "timestamp" in data


class TestReadyzEndpoint:
    """Tests for GET /readyz (readiness probe)"""

    def test_returns_200(self, client):
        resp = client.get("/readyz")
        assert resp.status_code == 200

    def test_status_is_ready(self, client):
        data = client.get("/readyz").get_json()
        assert data["status"] == "ready"


# ─────────────────────────────────────────────────────────────────────────────
# System Metric Endpoint Tests
# ─────────────────────────────────────────────────────────────────────────────

class TestMetricsEndpoint:
    """Tests for GET /api/v1/metrics"""

    def test_returns_200(self, client):
        resp = client.get("/api/v1/metrics")
        assert resp.status_code == 200

    def test_returns_json(self, client):
        resp = client.get("/api/v1/metrics")
        assert resp.is_json

    def test_has_cpu_data(self, client):
        data = client.get("/api/v1/metrics").get_json()
        assert "cpu" in data
        cpu = data["cpu"]
        assert "percent" in cpu
        assert "cores_logical" in cpu

    def test_has_memory_data(self, client):
        data = client.get("/api/v1/metrics").get_json()
        assert "memory" in data
        mem = data["memory"]
        assert "total_gb" in mem
        assert "percent" in mem

    def test_has_disk_data(self, client):
        data = client.get("/api/v1/metrics").get_json()
        assert "disk" in data
        disk = data["disk"]
        assert "total_gb" in disk
        assert "percent" in disk

    def test_has_system_info(self, client):
        data = client.get("/api/v1/metrics").get_json()
        assert "system" in data
        assert "hostname" in data["system"]
        assert "uptime" in data["system"]

    def test_cpu_percent_is_number(self, client):
        data = client.get("/api/v1/metrics").get_json()
        assert isinstance(data["cpu"]["percent"], (int, float))

    def test_disk_percent_within_range(self, client):
        data = client.get("/api/v1/metrics").get_json()
        pct = data["disk"]["percent"]
        assert 0 <= pct <= 100, f"Disk percent {pct} out of 0-100 range"


class TestProcessesEndpoint:
    """Tests for GET /api/v1/processes"""

    def test_returns_200(self, client):
        resp = client.get("/api/v1/processes")
        assert resp.status_code == 200

    def test_has_process_list(self, client):
        data = client.get("/api/v1/processes").get_json()
        assert "top_processes" in data
        assert isinstance(data["top_processes"], list)

    def test_max_10_processes_returned(self, client):
        data = client.get("/api/v1/processes").get_json()
        assert len(data["top_processes"]) <= 10

    def test_has_total_count(self, client):
        data = client.get("/api/v1/processes").get_json()
        assert "total_processes" in data
        assert data["total_processes"] > 0


class TestNetworkEndpoint:
    """Tests for GET /api/v1/network"""

    def test_returns_200(self, client):
        resp = client.get("/api/v1/network")
        assert resp.status_code == 200

    def test_has_hostname(self, client):
        data = client.get("/api/v1/network").get_json()
        assert "hostname" in data
        assert isinstance(data["hostname"], str)

    def test_has_interfaces(self, client):
        data = client.get("/api/v1/network").get_json()
        assert "interfaces" in data
        assert isinstance(data["interfaces"], dict)


# ─────────────────────────────────────────────────────────────────────────────
# Edge Case Tests
# ─────────────────────────────────────────────────────────────────────────────

class TestEdgeCases:
    """Tests for error handling and edge cases"""

    def test_404_on_unknown_route(self, client):
        resp = client.get("/this-route-does-not-exist")
        assert resp.status_code == 404

    def test_method_not_allowed(self, client):
        # POST to a GET-only endpoint
        resp = client.post("/healthz")
        assert resp.status_code == 405
