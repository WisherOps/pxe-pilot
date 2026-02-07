#!/usr/bin/env bash
# sandbox/provision/build-assets.sh
#
# Downloads a Proxmox ISO and runs the builder to create real PXE assets.
# Run inside pxe-vm:  vagrant ssh pxe-vm -c 'sudo /vagrant/sandbox/provision/build-assets.sh'
#
# Environment:
#   ISO_URL         — Proxmox ISO URL (default: proxmox-ve_9.1-1)
#   COMPRESS_LEVEL  — zstd level 1-19 (default: 1 for fast testing)

set -euo pipefail

ISO_URL="${ISO_URL:-https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso}"
COMPRESS_LEVEL="${COMPRESS_LEVEL:-1}"
WORK_DIR="/opt/pxe-pilot-sandbox"
ISO_FILE="$WORK_DIR/$(basename "$ISO_URL")"

info() { echo ">>> $*"; }

# Build the builder image
info "Building pxe-pilot-builder image..."
docker build -t pxe-pilot-builder:local /vagrant/builder

# Download ISO if not already present
if [ -f "$ISO_FILE" ]; then
    info "ISO already exists: $ISO_FILE (skipping download)"
else
    info "Downloading $ISO_URL ..."
    curl -L -o "$ISO_FILE" "$ISO_URL"
fi

# Run the builder
info "Running builder (compress level: $COMPRESS_LEVEL)..."
docker run --rm \
    -v "$WORK_DIR/assets:/output" \
    -v "$ISO_FILE:/input/proxmox.iso:ro" \
    -e "COMPRESS_LEVEL=$COMPRESS_LEVEL" \
    pxe-pilot-builder:local

# Restart pxe-pilot to pick up new assets
info "Restarting pxe-pilot..."
cd "$WORK_DIR"
docker compose restart pxe-pilot

# Verify
sleep 2
info "Menu now shows:"
curl -s localhost:8080/menu.ipxe

echo ""
info "Done. Recreate the demo VM with 8GB RAM for a real install."
