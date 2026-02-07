#!/usr/bin/env bash
# Extracts kernel and repacks initrd with ISO embedded.
# This is the core logic from morph027/pve-iso-2-pxe adapted for our use.

extract_pxe() {
    local iso_path="$1"
    local work_dir="$2"
    local zstd_level="$3"

    local mount_dir="$work_dir/iso-mount"
    local initrd_dir="$work_dir/initrd-work"

    mkdir -p "$mount_dir" "$initrd_dir"

    # Mount the prepared ISO
    echo "==> Mounting ISO..." >&2
    mount -o loop,ro "$iso_path" "$mount_dir"

    # Extract kernel
    echo "==> Extracting kernel..." >&2
    cp "$mount_dir/boot/linux26" "$work_dir/vmlinuz"

    # Extract and decompress initrd
    echo "==> Extracting initrd..." >&2
    local initrd_src="$mount_dir/boot/initrd.img"
    if [[ ! -f "$initrd_src" ]]; then
        initrd_src="$mount_dir/boot/initrd"
    fi

    (cd "$initrd_dir" && zstdcat "$initrd_src" | cpio -idm 2>/dev/null)

    # Unmount ISO
    umount "$mount_dir"

    # Embed the prepared ISO into initrd as /proxmox.iso
    echo "==> Embedding ISO into initrd..." >&2
    cp "$iso_path" "$initrd_dir/proxmox.iso"

    # Repack initrd with zstd compression
    echo "==> Repacking initrd (zstd level $zstd_level, this may take a while)..." >&2
    (cd "$initrd_dir" && find . | cpio -o -H newc 2>/dev/null | zstd -"$zstd_level" -T0 > "$work_dir/initrd")

    echo "==> Kernel: $(du -h "$work_dir/vmlinuz" | cut -f1)" >&2
    echo "==> Initrd: $(du -h "$work_dir/initrd" | cut -f1)" >&2

    # Cleanup
    rm -rf "$mount_dir" "$initrd_dir"
}
