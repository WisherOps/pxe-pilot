"""Configuration loading and merging for pxe-pilot."""

import re
import sys
from pathlib import Path
from typing import Any

if sys.version_info >= (3, 11):
    import tomllib
else:
    import tomli as tomllib


def normalize_mac(mac: str) -> str:
    """Normalize MAC address to lowercase with hyphens.

    Accepts formats:
    - AA:BB:CC:DD:EE:FF
    - AA-BB-CC-DD-EE-FF
    - AABBCCDDEEFF
    - aa:bb:cc:dd:ee:ff

    Returns:
    - aa-bb-cc-dd-ee-ff
    """
    # Remove all separators and convert to lowercase
    mac_clean = re.sub(r"[:\-\.]", "", mac).lower()

    if len(mac_clean) != 12:
        raise ValueError(f"Invalid MAC address: {mac}")

    if not re.match(r"^[0-9a-f]{12}$", mac_clean):
        raise ValueError(f"Invalid MAC address: {mac}")

    # Format with hyphens
    return "-".join(mac_clean[i : i + 2] for i in range(0, 12, 2))


def deep_merge(base: dict[str, Any], override: dict[str, Any]) -> dict[str, Any]:
    """Deep merge two dictionaries, with override taking precedence.

    - Nested dicts are merged recursively
    - Lists are replaced (not concatenated)
    - Scalar values are replaced
    """
    result = base.copy()

    for key, value in override.items():
        if key in result and isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = deep_merge(result[key], value)
        else:
            result[key] = value

    return result


def load_toml(path: Path) -> dict[str, Any]:
    """Load a TOML file and return its contents as a dict."""
    with open(path, "rb") as f:
        return tomllib.load(f)


class ConfigLoader:
    """Loads and merges configuration from defaults and per-host files."""

    def __init__(self, config_dir: Path | str):
        self.config_dir = Path(config_dir)
        self.defaults_path = self.config_dir / "defaults.toml"
        self.hosts_dir = self.config_dir / "hosts"

    def load_defaults(self) -> dict[str, Any]:
        """Load the defaults.toml file."""
        if not self.defaults_path.exists():
            return {}
        return load_toml(self.defaults_path)

    def load_host_config(self, mac: str) -> dict[str, Any] | None:
        """Load the config file for a specific MAC address.

        Returns None if no host-specific config exists.
        """
        normalized_mac = normalize_mac(mac)
        host_path = self.hosts_dir / f"{normalized_mac}.toml"

        if not host_path.exists():
            return None

        return load_toml(host_path)

    def get_config_for_mac(self, mac: str) -> dict[str, Any]:
        """Get the merged configuration for a specific MAC address.

        Merges defaults with host-specific overrides.
        """
        defaults = self.load_defaults()
        host_config = self.load_host_config(mac)

        if host_config is None:
            return defaults

        return deep_merge(defaults, host_config)

    def list_hosts(self) -> list[str]:
        """List all configured host MAC addresses."""
        if not self.hosts_dir.exists():
            return []

        hosts = []
        for path in self.hosts_dir.glob("*.toml"):
            # Extract MAC from filename (without .toml extension)
            mac = path.stem
            hosts.append(mac)

        return sorted(hosts)
