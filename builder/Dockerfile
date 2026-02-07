FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    wget gnupg2 cpio zstd ca-certificates xorriso \
    && rm -rf /var/lib/apt/lists/*

# Add Proxmox repo for proxmox-auto-install-assistant
RUN wget -qO /etc/apt/trusted.gpg.d/proxmox-release-bookworm.gpg \
    http://download.proxmox.com/debian/proxmox-release-bookworm.gpg \
    && echo "deb http://download.proxmox.com/debian/pve bookworm pve-no-subscription" \
    > /etc/apt/sources.list.d/pve.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends proxmox-auto-install-assistant \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
COPY scripts/ /scripts/
RUN chmod +x /entrypoint.sh /scripts/*.sh

ENTRYPOINT ["/entrypoint.sh"]
