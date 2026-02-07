"""pxe-pilot: HTTP answer file server for Proxmox automated installations."""

import os
import logging
import subprocess
from pathlib import Path

from fastapi import FastAPI, Request, Response
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

# ── Configuration ──────────────────────────────────────────────
ANSWERS_DIR = Path(os.getenv("PXE_PILOT_ANSWERS_DIR", "/answers"))
ASSETS_DIR = Path(os.getenv("PXE_PILOT_ASSETS_DIR", "/assets"))
ASSET_URL = os.getenv("PXE_PILOT_ASSET_URL", "")
LOG_LEVEL = os.getenv("PXE_PILOT_LOG_LEVEL", "info").upper()
BOOT_ENABLED = os.getenv("PXE_PILOT_BOOT_ENABLED", "false").lower() == "true"
TFTP_PORT = int(os.getenv("PXE_PILOT_TFTP_PORT", "69"))
IPXE_DIR = Path("/app/ipxe")
PORT = int(os.getenv("PXE_PILOT_PORT", "8080"))

PRODUCT_NAMES = {
    "proxmox-ve": "Proxmox VE",
    "proxmox-bs": "Proxmox BS",
    "proxmox-mg": "Proxmox MG",
}
KERNEL_OPTS = "vga=791 video=vesafb:ywrap,mtrr ramdisk_size=16777216 rw quiet splash=silent proxmox-start-auto-installer"

logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO))
logger = logging.getLogger("pxe-pilot")

app = FastAPI(title="pxe-pilot", docs_url=None, redoc_url=None)


# ── Helper functions ───────────────────────────────────────────


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


def scan_assets() -> dict[str, list[str]]:
    """Scan assets directory for available products and versions.

    Returns dict of product -> sorted list of versions (newest first).
    """
    products = {}
    if not ASSETS_DIR.is_dir():
        return products

    for product_dir in sorted(ASSETS_DIR.iterdir()):
        if not product_dir.is_dir():
            continue
        versions = []
        for version_dir in product_dir.iterdir():
            if not version_dir.is_dir():
                continue
            # Must have both vmlinuz and initrd
            if (version_dir / "vmlinuz").is_file() and (version_dir / "initrd").is_file():
                versions.append(version_dir.name)
        if versions:
            # Sort versions descending (newest first)
            versions.sort(
                key=lambda v: [int(x) for x in v.replace("-", ".").split(".") if x.isdigit()],
                reverse=True,
            )
            products[product_dir.name] = versions

    return products


def get_asset_base_url(request: Request) -> str:
    """Determine base URL for assets, from config or request."""
    if ASSET_URL:
        return ASSET_URL.rstrip("/")
    # Auto-detect from request
    host = request.headers.get("host", "localhost:8080")
    scheme = request.headers.get("x-forwarded-proto", "http")
    return f"{scheme}://{host}"


# ── Endpoints ──────────────────────────────────────────────────


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
        "boot_enabled": BOOT_ENABLED,
    }


@app.get("/hosts")
async def list_hosts() -> dict:
    """List all configured hosts and default status."""
    hosts_dir = ANSWERS_DIR / "hosts"
    default_exists = (ANSWERS_DIR / "default.toml").is_file()

    hosts = []
    if hosts_dir.is_dir():
        for f in sorted(hosts_dir.glob("*.toml")):
            hosts.append(f.stem)  # aa-bb-cc-dd-ee-ff

    return {
        "default_exists": default_exists,
        "host_count": len(hosts),
        "hosts": hosts,
    }


@app.get("/hosts/{mac}")
async def get_host(mac: str) -> Response:
    """View the TOML that a specific MAC would receive."""
    normalized = normalize_mac(mac)
    host_file = ANSWERS_DIR / "hosts" / f"{normalized}.toml"

    if host_file.is_file():
        return Response(
            content=host_file.read_text(),
            media_type="application/toml",
            headers={"X-PXE-Pilot-Source": f"hosts/{normalized}.toml"},
        )

    default_file = ANSWERS_DIR / "default.toml"
    if default_file.is_file():
        return Response(
            content=default_file.read_text(),
            media_type="application/toml",
            headers={"X-PXE-Pilot-Source": "default.toml"},
        )

    return JSONResponse(
        status_code=404,
        content={"error": f"No config found for {normalized} and no default.toml"},
    )


@app.get("/boot.ipxe")
async def boot_ipxe() -> Response:
    """Initial iPXE bootstrap script. Chains to /menu.ipxe."""
    script = "#!ipxe\nchain /menu.ipxe\n"
    return Response(content=script, media_type="text/plain")


@app.get("/menu.ipxe")
async def menu_ipxe(request: Request) -> Response:
    """Dynamic iPXE menu generated from available assets."""
    products = scan_assets()
    base_url = get_asset_base_url(request)

    lines = ["#!ipxe", "", "menu pxe-pilot: Select Installation"]

    if not products:
        lines.append("item --gap -- No boot assets found.")
        lines.append("item --gap -- Run pxe-pilot-builder to create assets.")
        lines.append("item exit Exit to iPXE shell")
        lines.append("choose selected || goto exit")
        lines.append("")
        lines.append(":exit")
        lines.append("shell")
        return Response(content="\n".join(lines) + "\n", media_type="text/plain")

    # Menu items
    for product, versions in products.items():
        display_name = PRODUCT_NAMES.get(product, product)
        lines.append(f"item --gap -- === {display_name} ===")
        for version in versions:
            item_id = f"{product}-{version}"
            lines.append(f"item {item_id} {display_name} {version}")

    lines.append("item --gap --")
    lines.append("item exit Exit to iPXE shell")
    lines.append("choose selected && goto ${selected} || goto exit")
    lines.append("")

    # Boot targets
    for product, versions in products.items():
        for version in versions:
            item_id = f"{product}-{version}"
            lines.append(f":{item_id}")
            lines.append(f"kernel {base_url}/assets/{product}/{version}/vmlinuz {KERNEL_OPTS}")
            lines.append(f"initrd {base_url}/assets/{product}/{version}/initrd")
            lines.append("boot || goto menu")
            lines.append("")

    lines.append(":exit")
    lines.append("shell")

    return Response(content="\n".join(lines) + "\n", media_type="text/plain")


# ── Static file serving ───────────────────────────────────────

if ASSETS_DIR.is_dir():
    app.mount("/assets", StaticFiles(directory=str(ASSETS_DIR)), name="assets")

# ── TFTP + Startup ────────────────────────────────────────────


def start_tftp():
    """Start py3tftp as a subprocess serving iPXE binaries."""
    if not IPXE_DIR.is_dir():
        logger.error("iPXE directory not found at %s", IPXE_DIR)
        return None
    logger.info("Starting TFTP server on port %d serving %s", TFTP_PORT, IPXE_DIR)
    proc = subprocess.Popen(
        ["py3tftp", "--host", "0.0.0.0", "--port", str(TFTP_PORT)],
        cwd=str(IPXE_DIR),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    return proc


if __name__ == "__main__":
    import uvicorn

    tftp_proc = None
    if BOOT_ENABLED:
        logger.info("Boot mode enabled — starting TFTP server")
        tftp_proc = start_tftp()
    else:
        logger.info("Boot mode disabled (set PXE_PILOT_BOOT_ENABLED=true to enable)")

    try:
        uvicorn.run("server:app", host="0.0.0.0", port=PORT, log_level=LOG_LEVEL.lower())
    finally:
        if tftp_proc:
            logger.info("Shutting down TFTP server")
            tftp_proc.terminate()
            tftp_proc.wait()
