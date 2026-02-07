"""Tests for POST /answer and GET /health endpoints."""


def _post_answer(client, macs: list[str]):
    """Helper: POST to /answer with given MAC addresses."""
    body = {
        "network_interfaces": [{"mac": mac} for mac in macs],
    }
    return client.post("/answer", json=body)


class TestAnswerLookup:
    """Core MAC -> TOML lookup logic."""

    def test_host_specific_match(self, client, answers_dir):
        (answers_dir / "hosts" / "aa-bb-cc-dd-ee-ff.toml").write_text(
            '[global]\nhostname = "node1"'
        )
        resp = _post_answer(client, ["aa:bb:cc:dd:ee:ff"])
        assert resp.status_code == 200
        assert 'hostname = "node1"' in resp.text
        assert resp.headers["content-type"] == "application/toml"

    def test_falls_back_to_default(self, client, answers_dir):
        (answers_dir / "default.toml").write_text('[global]\nhostname = "default"')
        resp = _post_answer(client, ["ff:ff:ff:ff:ff:ff"])
        assert resp.status_code == 200
        assert 'hostname = "default"' in resp.text

    def test_no_match_no_default_returns_404(self, client, answers_dir):
        resp = _post_answer(client, ["ff:ff:ff:ff:ff:ff"])
        assert resp.status_code == 404

    def test_first_mac_wins(self, client, answers_dir):
        (answers_dir / "hosts" / "11-22-33-44-55-66.toml").write_text(
            '[global]\nhostname = "second-nic"'
        )
        resp = _post_answer(client, ["aa:bb:cc:dd:ee:ff", "11:22:33:44:55:66"])
        assert resp.status_code == 200
        assert 'hostname = "second-nic"' in resp.text

    def test_host_takes_priority_over_default(self, client, answers_dir):
        (answers_dir / "default.toml").write_text('[global]\nhostname = "default"')
        (answers_dir / "hosts" / "aa-bb-cc-dd-ee-ff.toml").write_text(
            '[global]\nhostname = "specific"'
        )
        resp = _post_answer(client, ["aa:bb:cc:dd:ee:ff"])
        assert resp.status_code == 200
        assert 'hostname = "specific"' in resp.text


class TestMacNormalization:
    """MAC address format handling."""

    def test_colon_separated(self, client, answers_dir):
        (answers_dir / "hosts" / "aa-bb-cc-dd-ee-ff.toml").write_text("match = true")
        resp = _post_answer(client, ["aa:bb:cc:dd:ee:ff"])
        assert resp.status_code == 200

    def test_uppercase(self, client, answers_dir):
        (answers_dir / "hosts" / "aa-bb-cc-dd-ee-ff.toml").write_text("match = true")
        resp = _post_answer(client, ["AA:BB:CC:DD:EE:FF"])
        assert resp.status_code == 200

    def test_bare_format(self, client, answers_dir):
        (answers_dir / "hosts" / "aa-bb-cc-dd-ee-ff.toml").write_text("match = true")
        resp = _post_answer(client, ["aabbccddeeff"])
        assert resp.status_code == 200

    def test_dash_separated(self, client, answers_dir):
        (answers_dir / "hosts" / "aa-bb-cc-dd-ee-ff.toml").write_text("match = true")
        resp = _post_answer(client, ["aa-bb-cc-dd-ee-ff"])
        assert resp.status_code == 200


class TestBadRequests:
    """Invalid or malformed requests."""

    def test_no_macs_in_body(self, client):
        resp = client.post("/answer", json={"network_interfaces": []})
        assert resp.status_code == 400

    def test_missing_network_interfaces(self, client):
        resp = client.post("/answer", json={"something": "else"})
        assert resp.status_code == 400

    def test_invalid_json(self, client):
        resp = client.post(
            "/answer", content="not json", headers={"content-type": "application/json"}
        )
        assert resp.status_code == 400


class TestHealth:
    """GET /health endpoint."""

    def test_health_no_config(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"
        assert data["default_exists"] is False
        assert data["host_count"] == 0

    def test_health_with_config(self, client, answers_dir):
        (answers_dir / "default.toml").write_text("")
        (answers_dir / "hosts" / "aa-bb-cc-dd-ee-ff.toml").write_text("")
        (answers_dir / "hosts" / "11-22-33-44-55-66.toml").write_text("")
        resp = client.get("/health")
        data = resp.json()
        assert data["default_exists"] is True
        assert data["host_count"] == 2
