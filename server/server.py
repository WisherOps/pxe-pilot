"""pxe-pilot: HTTP answer file server for Proxmox automated installations."""

import os
import logging
from pathlib import Path

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse

# Configuration from environment
ANSWERS_DIR = Path(os.getenv("PXE_PILOT_ANSWERS_DIR", "/answers"))
LOG_LEVEL = os.getenv("PXE_PILOT_LOG_LEVEL", "info").upper()

logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO))
logger = logging.getLogger("pxe-pilot")

app = FastAPI(title="pxe-pilot", docs_url=None, redoc_url=None)


def normalize_mac(mac: str) -> str:
    """Normalize MAC address to aa-bb-cc-dd-ee-ff format."""
    mac = mac.lower().strip()
    if ":" in mac:
        mac = mac.replace(":", "-")
    if len(mac) == 12 and "-" not in mac:
        mac = "-".join(mac[i : i + 2] for i in range(0, 12, 2))
    return mac


def find_answer(macs: list[str]) -> tuple[str | None, str | None]:
    """Find answer file for given MAC addresses.

    Returns (toml_content, matched_mac) or (default_content, None) or (None, None).
    """
    hosts_dir = ANSWERS_DIR / "hosts"

    for mac in macs:
        normalized = normalize_mac(mac)
        host_file = hosts_dir / f"{normalized}.toml"
        if host_file.is_file():
            logger.info("Matched host file for MAC %s", normalized)
            return host_file.read_text(), normalized

    default_file = ANSWERS_DIR / "default.toml"
    if default_file.is_file():
        logger.info("No host match for MACs %s, serving default", macs)
        return default_file.read_text(), None

    logger.warning("No answer file found for MACs %s and no default.toml", macs)
    return None, None


@app.post("/answer")
async def answer(request: Request) -> Response:
    """Proxmox installer POSTs here. Returns TOML answer file."""
    try:
        body = await request.json()
    except Exception:
        logger.error("Failed to parse request body as JSON")
        return JSONResponse(status_code=400, content={"error": "Invalid JSON in request body"})

    network_interfaces = body.get("network_interfaces", [])
    macs = [iface.get("mac", "") for iface in network_interfaces if iface.get("mac")]

    if not macs:
        logger.warning("No MAC addresses found in request body")
        return JSONResponse(
            status_code=400,
            content={"error": "No MAC addresses found in request body"},
        )

    logger.debug("Received answer request with MACs: %s", macs)

    content, matched_mac = find_answer(macs)

    if content is None:
        return JSONResponse(
            status_code=404,
            content={"error": "No answer file found for provided MACs"},
        )

    return Response(content=content, media_type="application/toml")


@app.get("/health")
async def health() -> dict:
    """Health check endpoint."""
    default_exists = (ANSWERS_DIR / "default.toml").is_file()
    hosts_dir = ANSWERS_DIR / "hosts"
    host_count = len(list(hosts_dir.glob("*.toml"))) if hosts_dir.is_dir() else 0

    return {
        "status": "ok",
        "answers_dir": str(ANSWERS_DIR),
        "default_exists": default_exists,
        "host_count": host_count,
    }
