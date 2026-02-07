#!/usr/bin/env bash
# Copies built assets to versioned output directory.

publish() {
    local work_dir="$1"
    local output_dir="$2"
    local product="$3"
    local version="$4"

    local dest="$output_dir/$product/$version"
    mkdir -p "$dest"

    echo "==> Publishing to $dest" >&2
    cp "$work_dir/vmlinuz" "$dest/vmlinuz"
    cp "$work_dir/initrd" "$dest/initrd"
}
