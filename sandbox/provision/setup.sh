#!/usr/bin/env bash
# pxe-pilot sandbox provisioner
#
# Runs inside the Vagrant VM during 'vagrant up' or 'vagrant provision'.
# Installs Docker, builds the pxe-pilot image from source, templates the
# dnsmasq config for the selected network mode, and starts both services.
#
# Environment (set by Vagrantfile):
#   PXE_MODE    — "isolated" or "bridged"
#   DHCP_START  — first IP in range (isolated mode only)
#   DHCP_END    — last IP in range  (isolated mode only)

set -euo pipefail

PXE_MODE="${PXE_MODE:-isolated}"
DHCP_START="${DHCP_START:-10.10.10.100}"
DHCP_END="${DHCP_END:-10.10.10.200}"
WORK_DIR="/opt/pxe-pilot-sandbox"

info() { echo ">>> $*"; }

# ── Detect PXE-serving IP and interface ──────────────────────────

if [ "$PXE_MODE" = "bridged" ]; then
    # Find the bridged/external interface IP
    # Skip: loopback, Vagrant NAT (10.0.2.x), Docker bridge
    PXE_IP=$(ip -4 addr show \
        | grep 'inet ' \
        | grep -v '127.0.0.1' \
        | grep -v '10.0.2.' \
        | grep -v 'docker' \
        | grep -v 'br-' \
        | head -1 \
        | awk '{print $2}' \
        | cut -d/ -f1)

    if [ -z "$PXE_IP" ]; then
        echo "ERROR: Could not detect bridged IP. Is the external switch connected?" >&2
        exit 1
    fi

    PXE_IFACE=$(ip -4 addr show | grep "$PXE_IP" | awk '{print $NF}')
    info "Bridged mode — detected IP: $PXE_IP on $PXE_IFACE"
else
    PXE_IP="10.10.10.1"
    PXE_IFACE="eth1"
    info "Isolated mode — using $PXE_IP on $PXE_IFACE"
fi

# ── Install Docker ───────────────────────────────────────────────

if ! command -v docker &>/dev/null; then
    info "Installing Docker..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg lsb-release

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
    usermod -aG docker vagrant
else
    info "Docker already installed."
fi

# ── Build pxe-pilot image ───────────────────────────────────────

info "Building pxe-pilot image from /vagrant/server ..."
docker build -t pxe-pilot:local /vagrant/server

# ── Create work directory + fake assets ──────────────────────────

mkdir -p "$WORK_DIR/assets"

if [ ! -d "$WORK_DIR/assets/proxmox-ve" ]; then
    info "Creating fake PXE assets for chain testing..."
    mkdir -p "$WORK_DIR/assets/proxmox-ve/8.4-1"
    echo "fake-kernel" > "$WORK_DIR/assets/proxmox-ve/8.4-1/vmlinuz"
    echo "fake-initrd" > "$WORK_DIR/assets/proxmox-ve/8.4-1/initrd"
fi

# ── Template dnsmasq.conf ────────────────────────────────────────

info "Writing dnsmasq.conf ($PXE_MODE mode)..."

if [ "$PXE_MODE" = "bridged" ]; then
    # ── Proxy DHCP ──
    # Only answers PXE boot requests. Your router keeps handling IP assignment.
    # Safe to run on a production network — never conflicts with existing DHCP.
    cat > "$WORK_DIR/dnsmasq.conf" <<EOF
# pxe-pilot sandbox — proxy DHCP (bridged mode)
# Only responds to PXE boot requests, never hands out IP addresses.
# Your router/existing DHCP server continues to manage IPs.

port=0
interface=${PXE_IFACE}
bind-interfaces

dhcp-range=${PXE_IP},proxy

# BIOS PXE clients → undionly.kpxe via TFTP from pxe-pilot
dhcp-match=set:bios,60,PXEClient:Arch:00000
pxe-service=tag:bios,x86PC,"pxe-pilot",undionly.kpxe,${PXE_IP}

# UEFI PXE clients → ipxe.efi via TFTP from pxe-pilot
dhcp-match=set:efi64,60,PXEClient:Arch:00007
pxe-service=tag:efi64,x86-64_EFI,"pxe-pilot",ipxe.efi,${PXE_IP}

dhcp-match=set:efi64-2,60,PXEClient:Arch:00009
pxe-service=tag:efi64-2,x86-64_EFI,"pxe-pilot",ipxe.efi,${PXE_IP}

log-dhcp
EOF

else
    # ── Full DHCP on isolated network ──
    # Hands out IPs + PXE boot info. Safe because the network is private.
    cat > "$WORK_DIR/dnsmasq.conf" <<EOF
# pxe-pilot sandbox — full DHCP (isolated mode)
# This network is private — no conflict with your real LAN.

interface=${PXE_IFACE}
bind-interfaces

# DHCP range on the isolated 10.10.10.0/24 network
dhcp-range=${DHCP_START},${DHCP_END},255.255.255.0,1h

# Default gateway — pxe-vm itself (NATs to internet via eth0)
dhcp-option=3,${PXE_IP}

# DNS — use the host's resolver
dhcp-option=6,8.8.8.8,8.8.4.4

# BIOS PXE clients → undionly.kpxe via TFTP from pxe-pilot
dhcp-match=set:bios,60,PXEClient:Arch:00000
dhcp-boot=tag:bios,undionly.kpxe,,${PXE_IP}

# UEFI PXE clients → ipxe.efi via TFTP from pxe-pilot
dhcp-match=set:efi64,60,PXEClient:Arch:00007
dhcp-boot=tag:efi64,ipxe.efi,,${PXE_IP}

dhcp-match=set:efi64-2,60,PXEClient:Arch:00009
dhcp-boot=tag:efi64-2,ipxe.efi,,${PXE_IP}

log-dhcp
EOF

    # Enable IP forwarding + NAT so demo VMs can reach the internet
    info "Enabling IP forwarding + NAT..."
    sysctl -w net.ipv4.ip_forward=1 >/dev/null

    # Persist across reboots
    grep -q 'net.ipv4.ip_forward=1' /etc/sysctl.conf \
        || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

    # NAT: masquerade traffic from isolated network going out via eth0
    iptables -t nat -C POSTROUTING -o eth0 -j MASQUERADE 2>/dev/null \
        || iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
fi

# ── docker-compose.yml ───────────────────────────────────────────

info "Writing docker-compose.yml..."
cat > "$WORK_DIR/docker-compose.yml" <<EOF
services:
  pxe-pilot:
    image: pxe-pilot:local
    network_mode: host
    restart: unless-stopped
    volumes:
      - /vagrant/sandbox/config:/answers:ro
      - ${WORK_DIR}/assets:/assets:ro
    environment:
      - PXE_PILOT_BOOT_ENABLED=true
      - PXE_PILOT_ASSET_URL=http://${PXE_IP}:8080

  dnsmasq:
    image: drpsychick/dnsmasq
    network_mode: host
    restart: unless-stopped
    cap_add:
      - NET_ADMIN
    volumes:
      - ${WORK_DIR}/dnsmasq.conf:/etc/dnsmasq.conf:ro
EOF

# ── Start services ───────────────────────────────────────────────

info "Starting pxe-pilot + dnsmasq..."
cd "$WORK_DIR"
docker compose down --remove-orphans 2>/dev/null || true
docker compose up -d

# Wait for pxe-pilot to be healthy
info "Waiting for pxe-pilot..."
for i in $(seq 1 15); do
    if curl -sf http://localhost:8080/health >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# ── Summary ──────────────────────────────────────────────────────

echo ""
echo "============================================"
echo "  pxe-pilot sandbox ready ($PXE_MODE mode)"
echo "============================================"
echo ""
echo "  pxe-pilot HTTP : http://${PXE_IP}:8080"
echo "  pxe-pilot TFTP : ${PXE_IP}:69/udp"
if [ "$PXE_MODE" = "isolated" ]; then
echo "  DHCP           : full (${DHCP_START} - ${DHCP_END})"
echo "  Network        : 10.10.10.0/24 (isolated)"
else
echo "  DHCP           : proxy (your router assigns IPs)"
echo "  Network        : your LAN"
fi
echo ""
echo "  SSH into VM    : vagrant ssh pxe-vm"
echo "  Health check   : curl http://${PXE_IP}:8080/health"
echo "  View menu      : curl http://${PXE_IP}:8080/menu.ipxe"
echo "  Container logs : vagrant ssh pxe-vm -c 'cd /opt/pxe-pilot-sandbox && docker compose logs'"
echo ""
echo "  Now run the demo VM launcher to PXE boot a test client."
echo "============================================"
