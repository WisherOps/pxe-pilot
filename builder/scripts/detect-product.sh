#!/usr/bin/env bash
# Detect product name and version from Proxmox ISO filename.
# Expected patterns:
#   proxmox-ve_9.1-1.iso
#   proxmox-backup-server_3.3-1.iso
#   proxmox-mail-gateway_8.1-1.iso

detect_product() {
    local filename="$1"
    if [[ "$filename" =~ ^proxmox-ve ]]; then
        echo "proxmox-ve"
    elif [[ "$filename" =~ ^proxmox-backup-server ]]; then
        echo "proxmox-bs"
    elif [[ "$filename" =~ ^proxmox-mail-gateway ]]; then
        echo "proxmox-mg"
    else
        echo "unknown"
    fi
}

detect_version() {
    local filename="$1"
    # Extract version: everything between _ and .iso
    local version
    version=$(echo "$filename" | sed -n 's/.*_\([0-9].*\)\.iso/\1/p')
    if [[ -z "$version" ]]; then
        echo "unknown"
    else
        echo "$version"
    fi
}
