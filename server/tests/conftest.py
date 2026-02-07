"""Shared test fixtures for pxe-pilot server tests."""

import importlib
import pytest
from fastapi.testclient import TestClient


@pytest.fixture()
def answers_dir(tmp_path):
    """Create a temp answers directory with hosts/ subdirectory."""
    hosts_dir = tmp_path / "hosts"
    hosts_dir.mkdir()
    return tmp_path


@pytest.fixture()
def client(answers_dir, monkeypatch):
    """FastAPI test client with ANSWERS_DIR pointed at temp directory."""
    monkeypatch.setenv("PXE_PILOT_ANSWERS_DIR", str(answers_dir))

    import server.server as srv

    importlib.reload(srv)

    return TestClient(srv.app)
