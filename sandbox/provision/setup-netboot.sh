#!/usr/bin/env bash
# Provision the netboot VM: install Docker, detect bridged IP, generate
# dnsmasq config, and start the Docker Compose stack.
set -euo pipefail

SANDBOX_DIR="/opt/pxe-sandbox"
PROVISION_SRC="/vagrant/provision"

# ---------- defaults (overridable via env) ----------
DHCP_RANGE_START="${PXE_DHCP_START:-192.168.1.200}"
DHCP_RANGE_END="${PXE_DHCP_END:-192.168.1.250}"

# ---------- install Docker ----------
if ! command -v docker &>/dev/null; then
    echo ">>> Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker vagrant
    systemctl enable --now docker
else
    echo ">>> Docker already installed."
fi

# ---------- detect bridged IP ----------
detect_bridge_ip() {
    local iface ip
    for iface in $(ls /sys/class/net); do
        # Skip loopback, VirtualBox NAT, Docker/veth interfaces
        case "$iface" in
            lo|docker*|veth*|br-*) continue ;;
        esac

        ip=$(ip -4 addr show "$iface" | grep -oP 'inet \K[\d.]+' || true)
        [ -z "$ip" ] && continue

        # Skip VirtualBox NAT subnet (10.0.2.x)
        if [[ "$ip" == 10.0.2.* ]]; then
            continue
        fi

        echo "$iface $ip"
        return 0
    done
    return 1
}

echo ">>> Detecting bridged network interface..."
read -r BRIDGE_IFACE BRIDGE_IP < <(detect_bridge_ip) || {
    echo "ERROR: Could not detect bridged interface." >&2
    echo "Make sure the VM has a bridged (public_network) adapter." >&2
    exit 1
}

echo "    Interface: $BRIDGE_IFACE"
echo "    IP:        $BRIDGE_IP"

# ---------- prepare working directory ----------
mkdir -p "$SANDBOX_DIR/config/hosts"

# Copy sandbox configs
cp "$PROVISION_SRC/sandbox-config/defaults.toml" "$SANDBOX_DIR/config/defaults.toml"

# Copy host configs if any exist (ignore .gitkeep)
find "$PROVISION_SRC/sandbox-config/hosts" -name '*.toml' -exec \
    cp {} "$SANDBOX_DIR/config/hosts/" \; 2>/dev/null || true

# ---------- generate dnsmasq.conf from template ----------
echo ">>> Generating dnsmasq.conf..."
export BRIDGE_IFACE BRIDGE_IP DHCP_RANGE_START DHCP_RANGE_END
envsubst < "$PROVISION_SRC/dnsmasq.conf.tpl" > "$SANDBOX_DIR/dnsmasq.conf"

# ---------- copy compose file ----------
cp "$PROVISION_SRC/docker-compose.sandbox.yml" "$SANDBOX_DIR/docker-compose.sandbox.yml"

# ---------- write .env for reference ----------
cat > "$SANDBOX_DIR/.env" <<ENVFILE
BRIDGE_IFACE=$BRIDGE_IFACE
BRIDGE_IP=$BRIDGE_IP
DHCP_RANGE_START=$DHCP_RANGE_START
DHCP_RANGE_END=$DHCP_RANGE_END
ENVFILE

# ---------- start the stack ----------
echo ">>> Starting Docker Compose stack..."
cd "$SANDBOX_DIR"
docker compose -f docker-compose.sandbox.yml up -d --build

# ---------- summary ----------
echo ""
echo "============================================"
echo "  PXE Sandbox Ready"
echo "============================================"
echo "  Netboot VM IP:    $BRIDGE_IP"
echo "  DHCP range:       $DHCP_RANGE_START – $DHCP_RANGE_END"
echo ""
echo "  Services:"
echo "    pxe-pilot API:  http://$BRIDGE_IP:8080/health"
echo "    netboot.xyz UI: http://$BRIDGE_IP:3000"
echo "    TFTP:           $BRIDGE_IP:69/udp"
echo "    DHCP:           $BRIDGE_IP:67/udp"
echo "============================================"
