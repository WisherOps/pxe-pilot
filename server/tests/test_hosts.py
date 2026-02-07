"""Tests for GET /hosts and GET /hosts/{mac} endpoints."""


class TestListHosts:
    """GET /hosts endpoint."""

    def test_empty(self, client):
        resp = client.get("/hosts")
        assert resp.status_code == 200
        data = resp.json()
        assert data["hosts"] == []
        assert data["host_count"] == 0
        assert data["default_exists"] is False

    def test_with_hosts_and_default(self, client, answers_dir):
        (answers_dir / "default.toml").write_text("")
        (answers_dir / "hosts" / "aa-bb-cc-dd-ee-ff.toml").write_text("")
        (answers_dir / "hosts" / "11-22-33-44-55-66.toml").write_text("")
        resp = client.get("/hosts")
        data = resp.json()
        assert data["default_exists"] is True
        assert data["host_count"] == 2
        assert "aa-bb-cc-dd-ee-ff" in data["hosts"]
        assert "11-22-33-44-55-66" in data["hosts"]

    def test_sorted(self, client, answers_dir):
        (answers_dir / "hosts" / "cc-cc-cc-cc-cc-cc.toml").write_text("")
        (answers_dir / "hosts" / "aa-aa-aa-aa-aa-aa.toml").write_text("")
        (answers_dir / "hosts" / "bb-bb-bb-bb-bb-bb.toml").write_text("")
        resp = client.get("/hosts")
        data = resp.json()
        assert data["hosts"] == [
            "aa-aa-aa-aa-aa-aa",
            "bb-bb-bb-bb-bb-bb",
            "cc-cc-cc-cc-cc-cc",
        ]

    def test_ignores_non_toml_files(self, client, answers_dir):
        (answers_dir / "hosts" / "aa-bb-cc-dd-ee-ff.toml").write_text("")
        (answers_dir / "hosts" / "notes.txt").write_text("")
        (answers_dir / "hosts" / ".gitkeep").write_text("")
        resp = client.get("/hosts")
        data = resp.json()
        assert data["host_count"] == 1
        assert data["hosts"] == ["aa-bb-cc-dd-ee-ff"]


class TestGetHost:
    """GET /hosts/{mac} endpoint."""

    def test_host_specific(self, client, answers_dir):
        (answers_dir / "hosts" / "aa-bb-cc-dd-ee-ff.toml").write_text(
            '[global]\nhostname = "node1"'
        )
        resp = client.get("/hosts/aa-bb-cc-dd-ee-ff")
        assert resp.status_code == 200
        assert 'hostname = "node1"' in resp.text
        assert resp.headers["x-pxe-pilot-source"] == "hosts/aa-bb-cc-dd-ee-ff.toml"

    def test_falls_back_to_default(self, client, answers_dir):
        (answers_dir / "default.toml").write_text('[global]\nhostname = "default"')
        resp = client.get("/hosts/ff-ff-ff-ff-ff-ff")
        assert resp.status_code == 200
        assert 'hostname = "default"' in resp.text
        assert resp.headers["x-pxe-pilot-source"] == "default.toml"

    def test_404_no_match_no_default(self, client, answers_dir):
        resp = client.get("/hosts/ff-ff-ff-ff-ff-ff")
        assert resp.status_code == 404

    def test_mac_normalization(self, client, answers_dir):
        (answers_dir / "hosts" / "aa-bb-cc-dd-ee-ff.toml").write_text("match = true")
        # Colon-separated
        resp = client.get("/hosts/AA:BB:CC:DD:EE:FF")
        assert resp.status_code == 200
        assert resp.headers["x-pxe-pilot-source"] == "hosts/aa-bb-cc-dd-ee-ff.toml"

    def test_content_type(self, client, answers_dir):
        (answers_dir / "hosts" / "aa-bb-cc-dd-ee-ff.toml").write_text("test = true")
        resp = client.get("/hosts/aa-bb-cc-dd-ee-ff")
        assert resp.headers["content-type"] == "application/toml"
