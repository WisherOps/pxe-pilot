#!/usr/bin/env bash
# Prepares ISO for HTTP answer fetch using proxmox-auto-install-assistant.

prepare_iso() {
    local iso_path="$1"
    local answer_url="$2"
    local cert_fp="$3"
    local work_dir="$4"

    local prepared_iso="$work_dir/prepared.iso"

    echo "==> Preparing ISO for HTTP answer fetch..." >&2
    echo "    Answer URL: $answer_url" >&2

    local cmd=(
        proxmox-auto-install-assistant prepare-iso
        "$iso_path"
        --fetch-from http
        --url "$answer_url"
    )

    if [[ -n "$cert_fp" ]]; then
        echo "    Cert fingerprint: $cert_fp" >&2
        cmd+=(--cert-fingerprint "$cert_fp")
    fi

    cmd+=(--output "$prepared_iso")

    "${cmd[@]}" >&2

    echo "$prepared_iso"
}
