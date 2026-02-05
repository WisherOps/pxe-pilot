"""Tests for config loading and merging."""

import pytest
from pathlib import Path
import tempfile
import os

from pxe_pilot.config import normalize_mac, deep_merge, ConfigLoader


class TestNormalizeMac:
    """Tests for MAC address normalization."""

    def test_colon_separated_uppercase(self):
        assert normalize_mac("AA:BB:CC:DD:EE:FF") == "aa-bb-cc-dd-ee-ff"

    def test_colon_separated_lowercase(self):
        assert normalize_mac("aa:bb:cc:dd:ee:ff") == "aa-bb-cc-dd-ee-ff"

    def test_hyphen_separated(self):
        assert normalize_mac("AA-BB-CC-DD-EE-FF") == "aa-bb-cc-dd-ee-ff"

    def test_no_separator(self):
        assert normalize_mac("AABBCCDDEEFF") == "aa-bb-cc-dd-ee-ff"

    def test_mixed_case(self):
        assert normalize_mac("Aa:Bb:Cc:Dd:Ee:Ff") == "aa-bb-cc-dd-ee-ff"

    def test_invalid_length_short(self):
        with pytest.raises(ValueError, match="Invalid MAC address"):
            normalize_mac("AA:BB:CC")

    def test_invalid_length_long(self):
        with pytest.raises(ValueError, match="Invalid MAC address"):
            normalize_mac("AA:BB:CC:DD:EE:FF:GG")

    def test_invalid_characters(self):
        with pytest.raises(ValueError, match="Invalid MAC address"):
            normalize_mac("GG:HH:II:JJ:KK:LL")


class TestDeepMerge:
    """Tests for deep dictionary merging."""

    def test_simple_merge(self):
        base = {"a": 1, "b": 2}
        override = {"b": 3, "c": 4}
        result = deep_merge(base, override)
        assert result == {"a": 1, "b": 3, "c": 4}

    def test_nested_merge(self):
        base = {"a": {"x": 1, "y": 2}, "b": 3}
        override = {"a": {"y": 99, "z": 100}}
        result = deep_merge(base, override)
        assert result == {"a": {"x": 1, "y": 99, "z": 100}, "b": 3}

    def test_list_replacement(self):
        base = {"a": [1, 2, 3]}
        override = {"a": [4, 5]}
        result = deep_merge(base, override)
        assert result == {"a": [4, 5]}

    def test_base_unchanged(self):
        base = {"a": 1}
        override = {"b": 2}
        deep_merge(base, override)
        assert base == {"a": 1}

    def test_deeply_nested(self):
        base = {"a": {"b": {"c": {"d": 1}}}}
        override = {"a": {"b": {"c": {"e": 2}}}}
        result = deep_merge(base, override)
        assert result == {"a": {"b": {"c": {"d": 1, "e": 2}}}}


class TestConfigLoader:
    """Tests for ConfigLoader."""

    @pytest.fixture
    def config_dir(self):
        """Create a temporary config directory."""
        with tempfile.TemporaryDirectory() as tmpdir:
            hosts_dir = Path(tmpdir) / "hosts"
            hosts_dir.mkdir()
            yield Path(tmpdir)

    def test_load_defaults_missing(self, config_dir):
        loader = ConfigLoader(config_dir)
        assert loader.load_defaults() == {}

    def test_load_defaults(self, config_dir):
        defaults_path = config_dir / "defaults.toml"
        defaults_path.write_text('[global]\nkeyboard = "en-us"\n')

        loader = ConfigLoader(config_dir)
        defaults = loader.load_defaults()
        assert defaults == {"global": {"keyboard": "en-us"}}

    def test_load_host_config_missing(self, config_dir):
        loader = ConfigLoader(config_dir)
        result = loader.load_host_config("AA:BB:CC:DD:EE:FF")
        assert result is None

    def test_load_host_config(self, config_dir):
        host_path = config_dir / "hosts" / "aa-bb-cc-dd-ee-ff.toml"
        host_path.write_text('hostname = "test-host"\n')

        loader = ConfigLoader(config_dir)
        result = loader.load_host_config("AA:BB:CC:DD:EE:FF")
        assert result == {"hostname": "test-host"}

    def test_get_config_for_mac_defaults_only(self, config_dir):
        defaults_path = config_dir / "defaults.toml"
        defaults_path.write_text('[global]\nkeyboard = "en-us"\n')

        loader = ConfigLoader(config_dir)
        result = loader.get_config_for_mac("AA:BB:CC:DD:EE:FF")
        assert result == {"global": {"keyboard": "en-us"}}

    def test_get_config_for_mac_merged(self, config_dir):
        defaults_path = config_dir / "defaults.toml"
        defaults_path.write_text(
            '[global]\nkeyboard = "en-us"\n[network]\ndns = "1.1.1.1"\n'
        )

        host_path = config_dir / "hosts" / "aa-bb-cc-dd-ee-ff.toml"
        host_path.write_text('hostname = "test-host"\n[network]\naddress = "10.0.0.1/24"\n')

        loader = ConfigLoader(config_dir)
        result = loader.get_config_for_mac("AA:BB:CC:DD:EE:FF")

        assert result["global"]["keyboard"] == "en-us"
        assert result["hostname"] == "test-host"
        assert result["network"]["dns"] == "1.1.1.1"
        assert result["network"]["address"] == "10.0.0.1/24"

    def test_list_hosts_empty(self, config_dir):
        loader = ConfigLoader(config_dir)
        assert loader.list_hosts() == []

    def test_list_hosts(self, config_dir):
        (config_dir / "hosts" / "aa-bb-cc-dd-ee-ff.toml").write_text("")
        (config_dir / "hosts" / "11-22-33-44-55-66.toml").write_text("")

        loader = ConfigLoader(config_dir)
        hosts = loader.list_hosts()
        assert sorted(hosts) == ["11-22-33-44-55-66", "aa-bb-cc-dd-ee-ff"]
