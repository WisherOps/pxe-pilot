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
def client(answers_dir, assets_dir, monkeypatch):
    """FastAPI test client with dirs pointed at temp directories."""
    monkeypatch.setenv("PXE_PILOT_ANSWERS_DIR", str(answers_dir))
    monkeypatch.setenv("PXE_PILOT_ASSETS_DIR", str(assets_dir))

    import server.server as srv

    importlib.reload(srv)

    return TestClient(srv.app)


@pytest.fixture()
def assets_dir(tmp_path):
    """Create a temp assets directory."""
    assets = tmp_path / "assets"
    assets.mkdir()
    return assets
