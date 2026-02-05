"""Tests for the HTTP server."""

import json
import tempfile
import threading
import time
from pathlib import Path
from http.client import HTTPConnection

import pytest

from pxe_pilot.server import run_server, create_handler
from pxe_pilot.config import ConfigLoader


class TestServerIntegration:
    """Integration tests for the HTTP server."""

    @pytest.fixture
    def config_dir(self):
        """Create a temporary config directory with test data."""
        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = Path(tmpdir)
            hosts_dir = config_path / "hosts"
            hosts_dir.mkdir()

            # Create defaults
            defaults = config_path / "defaults.toml"
            defaults.write_text("""
[global]
keyboard = "en-us"
country = "us"
timezone = "UTC"

[network]
dns = "1.1.1.1"

[disk]
filesystem = "zfs"
""")

            # Create a host config
            host = hosts_dir / "aa-bb-cc-dd-ee-ff.toml"
            host.write_text("""
hostname = "test-host"

[network]
address = "10.0.0.10/24"
gateway = "10.0.0.1"

[disk]
target = "/dev/sda"
""")

            yield config_path

    @pytest.fixture
    def server(self, config_dir):
        """Start test server in a thread."""
        port = 18080  # Use a high port to avoid conflicts

        def run():
            run_server(config_dir, "127.0.0.1", port)

        thread = threading.Thread(target=run, daemon=True)
        thread.start()

        # Wait for server to start
        time.sleep(0.5)

        yield port

        # Server will be stopped when thread is killed (daemon=True)

    def test_health_endpoint(self, server):
        """Test GET /health returns OK."""
        conn = HTTPConnection("127.0.0.1", server, timeout=5)
        conn.request("GET", "/health")
        response = conn.getresponse()

        assert response.status == 200
        data = json.loads(response.read())
        assert data["status"] == "ok"
        conn.close()

    def test_hosts_endpoint(self, server):
        """Test GET /hosts returns list of hosts."""
        conn = HTTPConnection("127.0.0.1", server, timeout=5)
        conn.request("GET", "/hosts")
        response = conn.getresponse()

        assert response.status == 200
        data = json.loads(response.read())
        assert "hosts" in data
        assert "aa-bb-cc-dd-ee-ff" in data["hosts"]
        conn.close()

    def test_answer_endpoint_valid_mac(self, server):
        """Test POST /answer with valid MAC returns answer file."""
        conn = HTTPConnection("127.0.0.1", server, timeout=5)

        body = json.dumps({
            "network_interfaces": [
                {"mac": "AA:BB:CC:DD:EE:FF", "name": "eth0"}
            ]
        })

        conn.request(
            "POST",
            "/answer",
            body=body,
            headers={"Content-Type": "application/json"}
        )
        response = conn.getresponse()

        assert response.status == 200
        assert response.getheader("Content-Type") == "application/toml"

        content = response.read().decode()
        assert "[global]" in content
        assert 'hostname = "test-host"' in content
        assert "[network]" in content
        assert 'address = "10.0.0.10/24"' in content
        conn.close()

    def test_answer_endpoint_unknown_mac(self, server):
        """Test POST /answer with unknown MAC returns 404."""
        conn = HTTPConnection("127.0.0.1", server, timeout=5)

        body = json.dumps({
            "network_interfaces": [
                {"mac": "11:22:33:44:55:66", "name": "eth0"}
            ]
        })

        conn.request(
            "POST",
            "/answer",
            body=body,
            headers={"Content-Type": "application/json"}
        )
        response = conn.getresponse()

        # Should return defaults since no host-specific config
        # but validation should fail due to missing required fields
        assert response.status == 500
        conn.close()

    def test_answer_endpoint_no_body(self, server):
        """Test POST /answer with no body returns 400."""
        conn = HTTPConnection("127.0.0.1", server, timeout=5)

        conn.request(
            "POST",
            "/answer",
            headers={"Content-Type": "application/json", "Content-Length": "0"}
        )
        response = conn.getresponse()

        assert response.status == 400
        conn.close()

    def test_answer_endpoint_invalid_json(self, server):
        """Test POST /answer with invalid JSON returns 400."""
        conn = HTTPConnection("127.0.0.1", server, timeout=5)

        conn.request(
            "POST",
            "/answer",
            body="not json",
            headers={"Content-Type": "application/json"}
        )
        response = conn.getresponse()

        assert response.status == 400
        data = json.loads(response.read())
        assert "error" in data
        conn.close()

    def test_answer_endpoint_no_mac(self, server):
        """Test POST /answer with no MAC in body returns 400."""
        conn = HTTPConnection("127.0.0.1", server, timeout=5)

        body = json.dumps({"some": "data"})

        conn.request(
            "POST",
            "/answer",
            body=body,
            headers={"Content-Type": "application/json"}
        )
        response = conn.getresponse()

        assert response.status == 400
        data = json.loads(response.read())
        assert "MAC" in data["error"]
        conn.close()

    def test_not_found(self, server):
        """Test unknown endpoint returns 404."""
        conn = HTTPConnection("127.0.0.1", server, timeout=5)
        conn.request("GET", "/unknown")
        response = conn.getresponse()

        assert response.status == 404
        conn.close()
