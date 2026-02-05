"""Tests for answer file generation."""

import pytest

from pxe_pilot.answer import validate_config, generate_answer_toml, AnswerFileError


class TestValidateConfig:
    """Tests for configuration validation."""

    def test_valid_config(self):
        config = {
            "hostname": "test-host",
            "global": {
                "keyboard": "en-us",
                "country": "us",
                "timezone": "UTC",
            },
            "network": {
                "address": "10.0.0.1/24",
                "gateway": "10.0.0.254",
            },
            "disk": {
                "filesystem": "zfs",
                "target": "/dev/sda",
            },
        }
        missing = validate_config(config)
        assert missing == []

    def test_missing_hostname(self):
        config = {
            "global": {
                "keyboard": "en-us",
                "country": "us",
                "timezone": "UTC",
            },
            "network": {
                "address": "10.0.0.1/24",
                "gateway": "10.0.0.254",
            },
            "disk": {
                "filesystem": "zfs",
                "target": "/dev/sda",
            },
        }
        missing = validate_config(config)
        assert "hostname" in missing

    def test_hostname_in_global(self):
        config = {
            "global": {
                "hostname": "test-host",
                "keyboard": "en-us",
                "country": "us",
                "timezone": "UTC",
            },
            "network": {
                "address": "10.0.0.1/24",
                "gateway": "10.0.0.254",
            },
            "disk": {
                "filesystem": "zfs",
                "target": "/dev/sda",
            },
        }
        missing = validate_config(config)
        assert missing == []

    def test_missing_global_section(self):
        config = {
            "hostname": "test-host",
            "network": {
                "address": "10.0.0.1/24",
                "gateway": "10.0.0.254",
            },
            "disk": {
                "filesystem": "zfs",
                "target": "/dev/sda",
            },
        }
        missing = validate_config(config)
        assert "global.keyboard" in missing
        assert "global.country" in missing
        assert "global.timezone" in missing

    def test_missing_network_fields(self):
        config = {
            "hostname": "test-host",
            "global": {
                "keyboard": "en-us",
                "country": "us",
                "timezone": "UTC",
            },
            "network": {},
            "disk": {
                "filesystem": "zfs",
                "target": "/dev/sda",
            },
        }
        missing = validate_config(config)
        assert "network.address" in missing
        assert "network.gateway" in missing

    def test_missing_disk_fields(self):
        config = {
            "hostname": "test-host",
            "global": {
                "keyboard": "en-us",
                "country": "us",
                "timezone": "UTC",
            },
            "network": {
                "address": "10.0.0.1/24",
                "gateway": "10.0.0.254",
            },
            "disk": {},
        }
        missing = validate_config(config)
        assert "disk.filesystem" in missing
        assert "disk.target" in missing


class TestGenerateAnswerToml:
    """Tests for answer file generation."""

    def test_generate_valid_answer(self):
        config = {
            "hostname": "test-host",
            "global": {
                "keyboard": "en-us",
                "country": "us",
                "timezone": "UTC",
            },
            "network": {
                "address": "10.0.0.1/24",
                "gateway": "10.0.0.254",
                "dns": "1.1.1.1",
            },
            "disk": {
                "filesystem": "zfs",
                "target": "/dev/sda",
            },
        }

        result = generate_answer_toml(config)

        assert "[global]" in result
        assert 'keyboard = "en-us"' in result
        assert 'hostname = "test-host"' in result
        assert "[network]" in result
        assert 'address = "10.0.0.1/24"' in result
        assert "[disk]" in result
        assert 'target = "/dev/sda"' in result

    def test_strict_mode_raises_on_missing(self):
        config = {
            "hostname": "test-host",
            # Missing required sections
        }

        with pytest.raises(AnswerFileError, match="Missing required fields"):
            generate_answer_toml(config, strict=True)

    def test_non_strict_mode_allows_missing(self):
        config = {
            "hostname": "test-host",
        }

        # Should not raise
        result = generate_answer_toml(config, strict=False)
        assert "[global]" in result

    def test_root_password_handling(self):
        config = {
            "hostname": "test-host",
            "root_password": "secret123",
            "global": {
                "keyboard": "en-us",
                "country": "us",
                "timezone": "UTC",
            },
            "network": {
                "address": "10.0.0.1/24",
                "gateway": "10.0.0.254",
            },
            "disk": {
                "filesystem": "zfs",
                "target": "/dev/sda",
            },
        }

        result = generate_answer_toml(config)
        assert 'root_password = "secret123"' in result

    def test_root_password_hash_handling(self):
        config = {
            "hostname": "test-host",
            "root_password_hash": "$6$salt$hash",
            "global": {
                "keyboard": "en-us",
                "country": "us",
                "timezone": "UTC",
            },
            "network": {
                "address": "10.0.0.1/24",
                "gateway": "10.0.0.254",
            },
            "disk": {
                "filesystem": "zfs",
                "target": "/dev/sda",
            },
        }

        result = generate_answer_toml(config)
        assert 'root_password_hash = "$6$salt$hash"' in result

    def test_post_installation_section(self):
        config = {
            "hostname": "test-host",
            "global": {
                "keyboard": "en-us",
                "country": "us",
                "timezone": "UTC",
            },
            "network": {
                "address": "10.0.0.1/24",
                "gateway": "10.0.0.254",
            },
            "disk": {
                "filesystem": "zfs",
                "target": "/dev/sda",
            },
            "post_installation": {
                "reboot": True,
            },
        }

        result = generate_answer_toml(config)
        assert "[post_installation]" in result
        assert "reboot = true" in result
