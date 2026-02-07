#!/usr/bin/env bash
set -euo pipefail

# Defaults
ISO_PATH=""
ISO_URL=""
PRODUCT=""
VERSION=""
ANSWER_URL=""
OUTPUT_DIR="/output"
ZSTD_LEVEL="19"
CERT_FP=""
SKIP_VERIFY=false
WORK_DIR="/work"

usage() {
    cat <<EOF
Usage: pxe-pilot-builder [OPTIONS]

Options:
  --iso PATH              Path to local Proxmox ISO (inside container)
  --iso-url URL           URL to download Proxmox ISO
  --product NAME          Product name: proxmox-ve, proxmox-bs (auto-detected from ISO)
  --version VERSION       Version string, e.g. 9.1-1 (auto-detected from ISO)
  --answer-url URL        URL the installer will POST to (required)
  --output DIR            Output directory (default: /output)
  --zstd-level N          Compression level 1-19 (default: 19)
  --cert-fingerprint FP   TLS cert fingerprint for HTTPS answer URLs
  --skip-verify           Skip ISO checksum verification
  --help                  Show this help
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)          ISO_PATH="$2"; shift 2 ;;
        --iso-url)      ISO_URL="$2"; shift 2 ;;
        --product)      PRODUCT="$2"; shift 2 ;;
        --version)      VERSION="$2"; shift 2 ;;
        --answer-url)   ANSWER_URL="$2"; shift 2 ;;
        --output)       OUTPUT_DIR="$2"; shift 2 ;;
        --zstd-level)   ZSTD_LEVEL="$2"; shift 2 ;;
        --cert-fingerprint) CERT_FP="$2"; shift 2 ;;
        --skip-verify)  SKIP_VERIFY=true; shift ;;
        --help)         usage ;;
        *)              echo "Unknown option: $1"; usage ;;
    esac
done

# Validation
if [[ -z "$ANSWER_URL" ]]; then
    echo "ERROR: --answer-url is required"
    exit 1
fi

if [[ -z "$ISO_PATH" && -z "$ISO_URL" ]]; then
    echo "ERROR: Either --iso or --iso-url is required"
    exit 1
fi

# Create work directory
mkdir -p "$WORK_DIR"

# Step 1: Get the ISO
if [[ -n "$ISO_URL" ]]; then
    source /scripts/fetch-iso.sh
    ISO_PATH=$(fetch_iso "$ISO_URL" "$WORK_DIR" "$SKIP_VERIFY")
fi

if [[ ! -f "$ISO_PATH" ]]; then
    echo "ERROR: ISO not found at $ISO_PATH"
    exit 1
fi

echo "==> Using ISO: $ISO_PATH"

# Auto-detect product and version from ISO filename
ISO_FILENAME=$(basename "$ISO_PATH")
if [[ -z "$PRODUCT" ]]; then
    source /scripts/detect-product.sh
    PRODUCT=$(detect_product "$ISO_FILENAME")
fi
if [[ -z "$VERSION" ]]; then
    source /scripts/detect-product.sh
    VERSION=$(detect_version "$ISO_FILENAME")
fi

echo "==> Product: $PRODUCT"
echo "==> Version: $VERSION"

# Step 2: Prepare ISO with proxmox-auto-install-assistant
source /scripts/prepare-iso.sh
PREPARED_ISO=$(prepare_iso "$ISO_PATH" "$ANSWER_URL" "$CERT_FP" "$WORK_DIR")
echo "==> Prepared ISO: $PREPARED_ISO"

# Step 3: Extract kernel and repack initrd
source /scripts/extract-pxe.sh
extract_pxe "$PREPARED_ISO" "$WORK_DIR" "$ZSTD_LEVEL"

# Step 4: Publish to output directory
source /scripts/publish.sh
publish "$WORK_DIR" "$OUTPUT_DIR" "$PRODUCT" "$VERSION"

echo "==> Done! Assets at: $OUTPUT_DIR/$PRODUCT/$VERSION/"
echo "    vmlinuz: $(du -h "$OUTPUT_DIR/$PRODUCT/$VERSION/vmlinuz" | cut -f1)"
echo "    initrd:  $(du -h "$OUTPUT_DIR/$PRODUCT/$VERSION/initrd" | cut -f1)"
