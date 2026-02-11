#!/usr/bin/env bash
# Build real PXE assets from Proxmox ISO using the published builder
#
# Usage:
#   vagrant ssh pxe-vm -c 'bash /vagrant/sandbox/provision/build-assets.sh'
#
# Environment variables:
#   ISO_URL          — Proxmox ISO to download (default: proxmox-ve_9.1-1)
#   ANSWER_URL       — URL for answer file server (optional, auto-detected)
#   ZSTD_LEVEL       — Compression level 1-22 (default: 1 for fast testing)
#   SKIP_VERIFY      — Set to "true" to skip ISO checksum verification

set -euo pipefail

WORK_DIR="/opt/pxe-pilot-sandbox"
ISO_URL="${ISO_URL:-https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso}"
ANSWER_URL="${ANSWER_URL:-}"
ZSTD_LEVEL="${ZSTD_LEVEL:-1}"
SKIP_VERIFY="${SKIP_VERIFY:-false}"

info() { echo ">>> $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }

# Check write permissions on work directory
if [ ! -w "$WORK_DIR" ]; then
    error "No write permission on $WORK_DIR. Try: sudo chown -R vagrant:vagrant $WORK_DIR"
fi

# Detect ANSWER_URL from running pxe-pilot container if not set
if [ -z "$ANSWER_URL" ]; then
    PXE_IP=$(docker inspect pxe-pilot-sandbox-pxe-pilot-1 2>/dev/null \
        --format '{{range .Config.Env}}{{println .}}{{end}}' \
        | grep PXE_PILOT_ASSET_URL \
        | cut -d= -f2 \
        | cut -d: -f2 \
        | tr -d '/' || echo "")

    if [ -n "$PXE_IP" ]; then
        ANSWER_URL="http://${PXE_IP}:8080/answer"
    else
        # Fallback to common defaults
        if ip addr show eth1 &>/dev/null; then
            ANSWER_URL="http://10.10.10.1:8080/answer"  # Isolated mode
        else
            error "Could not detect answer URL. Set ANSWER_URL environment variable."
        fi
    fi
fi

info "Building real PXE assets..."
info "  ISO URL:     $ISO_URL"
info "  Answer URL:  $ANSWER_URL"
info "  ZSTD Level:  $ZSTD_LEVEL"
info "  Output:      $WORK_DIR/assets"

# Build command
CMD=(
    docker run --rm --privileged
    -v "$WORK_DIR/assets:/output"
    ghcr.io/wisherops/pxe-pilot-builder:latest
    --iso-url "$ISO_URL"
    --answer-url "$ANSWER_URL"
    --zstd-level "$ZSTD_LEVEL"
)

if [ "$SKIP_VERIFY" = "true" ]; then
    CMD+=(--skip-verify)
fi

# Run builder
"${CMD[@]}"

# Restart pxe-pilot to pick up new assets
info "Restarting pxe-pilot..."
cd "$WORK_DIR"
docker compose restart pxe-pilot

# Verify
sleep 2
info "Menu now shows:"
curl -s localhost:8080/menu.ipxe || curl -s http://10.10.10.1:8080/menu.ipxe

echo ""
info "Done! Recreate the demo VM with 8GB+ RAM for a real Proxmox install."
