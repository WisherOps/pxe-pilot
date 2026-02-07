"""Tests for BOOT_ENABLED mode and related configuration."""


class TestBootConfig:
    """Boot mode configuration."""

    def test_health_shows_boot_disabled(self, client):
        resp = client.get("/health")
        data = resp.json()
        assert data["boot_enabled"] is False

    def test_health_shows_boot_enabled(self, client, monkeypatch):
        import server.server as srv

        monkeypatch.setattr(srv, "BOOT_ENABLED", True)
        resp = client.get("/health")
        data = resp.json()
        assert data["boot_enabled"] is True

    def test_boot_ipxe_always_available(self, client):
        """boot.ipxe should work regardless of BOOT_ENABLED."""
        resp = client.get("/boot.ipxe")
        assert resp.status_code == 200
        assert "#!ipxe" in resp.text
