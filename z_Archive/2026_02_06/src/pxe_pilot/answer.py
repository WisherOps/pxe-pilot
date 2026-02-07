"""Answer file generation for Proxmox automated installation."""

from typing import Any

import tomli_w


class AnswerFileError(Exception):
    """Error generating answer file."""

    pass


# Required fields for a valid Proxmox answer file
REQUIRED_FIELDS = {
    "global": ["keyboard", "country", "timezone"],
    "network": ["address", "gateway"],
    "disk": ["filesystem", "target"],
}


def validate_config(config: dict[str, Any]) -> list[str]:
    """Validate that all required fields are present.

    Returns a list of missing fields (empty if valid).
    """
    missing = []

    for section, fields in REQUIRED_FIELDS.items():
        if section not in config:
            for field in fields:
                missing.append(f"{section}.{field}")
        else:
            for field in fields:
                if field not in config[section]:
                    missing.append(f"{section}.{field}")

    # hostname can be at root level
    if "hostname" not in config and "hostname" not in config.get("global", {}):
        missing.append("hostname")

    return missing


def generate_answer_toml(config: dict[str, Any], strict: bool = True) -> str:
    """Generate a Proxmox answer.toml from the merged configuration.

    Args:
        config: Merged configuration dictionary
        strict: If True, raise error on missing required fields

    Returns:
        TOML string for Proxmox answer file

    Raises:
        AnswerFileError: If strict=True and required fields are missing
    """
    if strict:
        missing = validate_config(config)
        if missing:
            raise AnswerFileError(f"Missing required fields: {', '.join(missing)}")

    # Build the answer file structure
    # Proxmox expects specific sections: [global], [network], [disk]
    answer = {}

    # Global section
    answer["global"] = {}
    if "global" in config:
        answer["global"].update(config["global"])

    # Add hostname to global if at root level
    if "hostname" in config:
        answer["global"]["hostname"] = config["hostname"]

    # Ensure required global fields
    for field in ["keyboard", "country", "timezone"]:
        if field in config and field not in answer["global"]:
            answer["global"][field] = config[field]

    # Network section
    if "network" in config:
        answer["network"] = config["network"].copy()

    # Disk section
    if "disk" in config:
        answer["disk"] = config["disk"].copy()

    # Root password handling
    if "root_password" in config:
        answer["global"]["root_password"] = config["root_password"]
    elif "root_password_hash" in config:
        answer["global"]["root_password_hash"] = config["root_password_hash"]
    elif "global" in config:
        if "root_password" in config["global"]:
            answer["global"]["root_password"] = config["global"]["root_password"]
        elif "root_password_hash" in config["global"]:
            answer["global"]["root_password_hash"] = config["global"]["root_password_hash"]

    # Post-installation section (optional)
    if "post_installation" in config:
        answer["post_installation"] = config["post_installation"].copy()

    return tomli_w.dumps(answer)
