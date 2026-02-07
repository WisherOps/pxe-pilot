"""Tests for GET /boot.ipxe and GET /menu.ipxe endpoints."""


class TestBootIpxe:
    """GET /boot.ipxe endpoint."""

    def test_returns_chain(self, client):
        resp = client.get("/boot.ipxe")
        assert resp.status_code == 200
        assert "#!ipxe" in resp.text
        assert "chain /menu.ipxe" in resp.text


class TestMenuIpxe:
    """GET /menu.ipxe endpoint."""

    def test_empty_assets(self, client):
        resp = client.get("/menu.ipxe")
        assert resp.status_code == 200
        assert "#!ipxe" in resp.text
        assert "No boot assets found" in resp.text

    def test_single_product_version(self, client, assets_dir):
        ver_dir = assets_dir / "proxmox-ve" / "9.1-1"
        ver_dir.mkdir(parents=True)
        (ver_dir / "vmlinuz").write_text("kernel")
        (ver_dir / "initrd").write_text("initrd")

        resp = client.get("/menu.ipxe")
        assert resp.status_code == 200
        assert "Proxmox VE" in resp.text
        assert "proxmox-ve-9.1-1" in resp.text
        assert "vmlinuz" in resp.text
        assert "proxmox-start-auto-installer" in resp.text

    def test_multiple_versions_sorted(self, client, assets_dir):
        for ver in ["8.4-1", "9.1-1", "9.0-2"]:
            ver_dir = assets_dir / "proxmox-ve" / ver
            ver_dir.mkdir(parents=True)
            (ver_dir / "vmlinuz").write_text("kernel")
            (ver_dir / "initrd").write_text("initrd")

        resp = client.get("/menu.ipxe")
        text = resp.text
        # 9.1-1 should appear before 9.0-2 which should appear before 8.4-1
        pos_91 = text.index("proxmox-ve-9.1-1")
        pos_90 = text.index("proxmox-ve-9.0-2")
        pos_84 = text.index("proxmox-ve-8.4-1")
        assert pos_91 < pos_90 < pos_84

    def test_multiple_products(self, client, assets_dir):
        for product, ver in [("proxmox-ve", "9.1-1"), ("proxmox-bs", "3.3-1")]:
            ver_dir = assets_dir / product / ver
            ver_dir.mkdir(parents=True)
            (ver_dir / "vmlinuz").write_text("kernel")
            (ver_dir / "initrd").write_text("initrd")

        resp = client.get("/menu.ipxe")
        assert "Proxmox VE" in resp.text
        assert "Proxmox BS" in resp.text

    def test_skips_incomplete_versions(self, client, assets_dir):
        # Has vmlinuz but no initrd
        ver_dir = assets_dir / "proxmox-ve" / "9.1-1"
        ver_dir.mkdir(parents=True)
        (ver_dir / "vmlinuz").write_text("kernel")

        resp = client.get("/menu.ipxe")
        assert "No boot assets found" in resp.text

    def test_asset_url_override(self, client, assets_dir, monkeypatch):
        import server.server as srv

        monkeypatch.setattr(srv, "ASSET_URL", "http://custom.host:9090")

        ver_dir = assets_dir / "proxmox-ve" / "9.1-1"
        ver_dir.mkdir(parents=True)
        (ver_dir / "vmlinuz").write_text("kernel")
        (ver_dir / "initrd").write_text("initrd")

        resp = client.get("/menu.ipxe")
        assert "http://custom.host:9090/assets/" in resp.text
