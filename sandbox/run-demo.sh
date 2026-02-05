#!/usr/bin/env bash
# PXE Boot Testing Sandbox — Linux / macOS launcher
#
# Manages the full sandbox lifecycle:
#   ./run-demo.sh up      Start netboot VM + create PXE demo VM
#   ./run-demo.sh down    Destroy both VMs
#   ./run-demo.sh status  Show current state
#   ./run-demo.sh help    Print usage
#
# Environment variables:
#   PXE_BRIDGE       — host NIC for bridging (Vagrant prompts if unset)
#   PXE_DHCP_START   — first IP in DHCP range  (default: 192.168.1.200)
#   PXE_DHCP_END     — last IP in DHCP range   (default: 192.168.1.250)
#   DEMO_VM_NAME     — VirtualBox demo VM name  (default: pxe-sandbox-demo)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_VM_NAME="${DEMO_VM_NAME:-pxe-sandbox-demo}"
DEMO_VM_RAM=5120
DEMO_VM_CPUS=2
DEMO_VM_DISK_MB=20480

# ---------- helpers ----------

die()    { echo "ERROR: $*" >&2; exit 1; }
info()   { echo ">>> $*"; }

require_cmd() {
    command -v "$1" &>/dev/null || die "'$1' is required but not found in PATH."
}

# Resolve bridge adapter name for VBoxManage from Vagrant/env
resolve_bridge() {
    if [ -n "${PXE_BRIDGE:-}" ]; then
        echo "$PXE_BRIDGE"
        return
    fi

    # Try to read from the running netboot VM
    local bridged
    bridged=$(VBoxManage showvminfo pxe-sandbox-netboot --machinereadable 2>/dev/null \
        | grep '^bridgeadapter2=' \
        | cut -d'"' -f2) || true

    if [ -n "$bridged" ]; then
        echo "$bridged"
        return
    fi

    die "Cannot determine bridge adapter. Set PXE_BRIDGE or start netboot VM first."
}

demo_vm_exists() {
    VBoxManage showvminfo "$DEMO_VM_NAME" &>/dev/null 2>&1
}

# ---------- up ----------

cmd_up() {
    require_cmd vagrant
    require_cmd VBoxManage

    info "Starting netboot VM..."
    (cd "$SCRIPT_DIR" && vagrant up netboot)

    local bridge
    bridge=$(resolve_bridge)
    info "Using bridge adapter: $bridge"

    if demo_vm_exists; then
        info "Demo VM '$DEMO_VM_NAME' already exists — starting it."
        VBoxManage startvm "$DEMO_VM_NAME" --type gui 2>/dev/null || true
        return
    fi

    info "Creating demo VM '$DEMO_VM_NAME'..."

    # Create VM
    VBoxManage createvm --name "$DEMO_VM_NAME" --ostype "Linux_64" --register

    # Basic settings: RAM, CPUs, boot order (network first)
    VBoxManage modifyvm "$DEMO_VM_NAME" \
        --memory "$DEMO_VM_RAM" \
        --cpus "$DEMO_VM_CPUS" \
        --boot1 net \
        --boot2 disk \
        --boot3 none \
        --boot4 none

    # NIC: bridged, Intel PRO/1000 for best PXE ROM support
    VBoxManage modifyvm "$DEMO_VM_NAME" \
        --nic1 bridged \
        --bridgeadapter1 "$bridge" \
        --nictype1 82540EM \
        --nicpromisc1 allow-all

    # Storage: SATA controller + virtual disk
    local disk_path
    disk_path="$(VBoxManage showvminfo "$DEMO_VM_NAME" --machinereadable \
        | grep '^CfgFile=' | cut -d'"' -f2 | xargs dirname)/${DEMO_VM_NAME}.vdi"

    VBoxManage createmedium disk --filename "$disk_path" --size "$DEMO_VM_DISK_MB" --format VDI
    VBoxManage storagectl "$DEMO_VM_NAME" --name "SATA" --add sata --controller IntelAHCI
    VBoxManage storageattach "$DEMO_VM_NAME" \
        --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$disk_path"

    info "Starting demo VM (PXE boot)..."
    VBoxManage startvm "$DEMO_VM_NAME" --type gui

    echo ""
    echo "============================================"
    echo "  Demo VM started — PXE booting now"
    echo "============================================"
    echo "  The VM will:"
    echo "    1. Request DHCP lease from dnsmasq"
    echo "    2. Download netboot.xyz via TFTP"
    echo "    3. Show the netboot.xyz boot menu"
    echo ""
    echo "  Select: Linux Network Installs > Proxmox"
    echo "  The installer will fetch its answer file"
    echo "  from pxe-pilot automatically."
    echo "============================================"
}

# ---------- down ----------

cmd_down() {
    require_cmd VBoxManage

    if demo_vm_exists; then
        info "Powering off demo VM '$DEMO_VM_NAME'..."
        VBoxManage controlvm "$DEMO_VM_NAME" poweroff 2>/dev/null || true
        sleep 2
        info "Deleting demo VM '$DEMO_VM_NAME'..."
        VBoxManage unregistervm "$DEMO_VM_NAME" --delete 2>/dev/null || true
    else
        info "Demo VM '$DEMO_VM_NAME' does not exist."
    fi

    if [ -d "$SCRIPT_DIR/.vagrant" ]; then
        info "Destroying netboot VM..."
        (cd "$SCRIPT_DIR" && vagrant destroy -f)
    else
        info "No Vagrant state found."
    fi

    echo ">>> Sandbox cleaned up."
}

# ---------- status ----------

cmd_status() {
    require_cmd VBoxManage

    echo "=== Netboot VM ==="
    (cd "$SCRIPT_DIR" && vagrant status netboot 2>/dev/null) || echo "  (no Vagrant state)"
    echo ""

    echo "=== Demo VM ($DEMO_VM_NAME) ==="
    if demo_vm_exists; then
        local state
        state=$(VBoxManage showvminfo "$DEMO_VM_NAME" --machinereadable \
            | grep '^VMState=' | cut -d'"' -f2)
        echo "  State: $state"
    else
        echo "  Not created"
    fi
    echo ""

    echo "=== Docker containers (via netboot VM) ==="
    (cd "$SCRIPT_DIR" && vagrant ssh netboot -c "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" 2>/dev/null) \
        || echo "  (cannot reach netboot VM)"
}

# ---------- help ----------

cmd_help() {
    cat <<USAGE
PXE Boot Testing Sandbox

Usage: $0 <command>

Commands:
  up       Provision netboot VM and create a PXE-booting demo VM
  down     Destroy both VMs and clean up
  status   Show the state of sandbox VMs and containers
  help     Show this message

Environment variables:
  PXE_BRIDGE       Host NIC for bridged networking (prompted if unset)
  PXE_DHCP_START   First IP in DHCP range  (default: 192.168.1.200)
  PXE_DHCP_END     Last IP in DHCP range   (default: 192.168.1.250)
  DEMO_VM_NAME     Demo VM name            (default: pxe-sandbox-demo)

Prerequisites:
  - VirtualBox (with Extension Pack recommended)
  - Vagrant
  - A physical network adapter for bridging

See sandbox/README.md for full documentation.
USAGE
}

# ---------- main ----------

case "${1:-help}" in
    up)     cmd_up     ;;
    down)   cmd_down   ;;
    status) cmd_status ;;
    help)   cmd_help   ;;
    *)      die "Unknown command: $1 (try '$0 help')" ;;
esac
