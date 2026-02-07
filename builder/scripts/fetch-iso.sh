#!/usr/bin/env bash
# Downloads ISO from URL. Returns path to downloaded file.

fetch_iso() {
    local url="$1"
    local work_dir="$2"
    local skip_verify="$3"
    local filename
    filename=$(basename "$url")
    local dest="$work_dir/$filename"

    echo "==> Downloading ISO from $url" >&2

    wget -q --show-progress -O "$dest" "$url"

    if [[ "$skip_verify" != "true" ]]; then
        # Try to download SHA256SUMS from same directory
        local sha_url
        sha_url="$(dirname "$url")/SHA256SUMS"
        local sha_file="$work_dir/SHA256SUMS"

        echo "==> Checking for SHA256SUMS at $sha_url" >&2
        if wget -q -O "$sha_file" "$sha_url" 2>/dev/null; then
            echo "==> Verifying SHA256 checksum..." >&2
            (cd "$work_dir" && grep "$filename" SHA256SUMS | sha256sum -c -) >&2
        else
            echo "==> No SHA256SUMS found, skipping verification" >&2
        fi
    fi

    echo "$dest"
}
