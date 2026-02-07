#!/usr/bin/env bash
# pxe-pilot sandbox — Linux / macOS launcher
#
# Manages the full sandbox lifecycle with VirtualBox:
#   ./run-demo.sh up      Start pxe-vm + create PXE demo VM
#   ./run-demo.sh down    Destroy both VMs and clean up
#   ./run-demo.sh status  Show current state
#   ./run-demo.sh help    Print usage
#
# Environment variables:
#   PXE_MODE         — "isolated" (default) or "bridged"
#   PXE_BRIDGE       — host NIC name for bridged mode (Vagrant prompts if unset)
#   PXE_DHCP_START   — first IP in DHCP range  (isolated, default: 10.10.10.100)
#   PXE_DHCP_END     — last IP in DHCP range   (isolated, default: 10.10.10.200)
#   DEMO_VM_NAME     — VirtualBox demo VM name  (default: pxe-pilot-demo)
#   DEMO_VM_RAM      — demo VM RAM in MB        (default: 2048, use 8192 for real installs)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_VM_NAME="${DEMO_VM_NAME:-pxe-pilot-demo}"
DEMO_VM_RAM="${DEMO_VM_RAM:-2048}"
DEMO_VM_CPUS=2
DEMO_VM_DISK_MB=20480
PXE_MODE="${PXE_MODE:-isolated}"

# ── helpers ──────────────────────────────────────────────────────

die()  { echo "ERROR: $*" >&2; exit 1; }
info() { echo ">>> $*"; }

require_cmd() {
    command -v "$1" &>/dev/null || die "'$1' is required but not found in PATH."
}

demo_vm_exists() {
    VBoxManage showvminfo "$DEMO_VM_NAME" &>/dev/null 2>&1
}

# Detect which bridge adapter the netboot VM is using
resolve_bridge() {
    if [ -n "${PXE_BRIDGE:-}" ]; then
        echo "$PXE_BRIDGE"
        return
    fi

    # Try to read from the running pxe-vm
    local bridged
    bridged=$(VBoxManage showvminfo pxe-pilot-sandbox --machinereadable 2>/dev/null \
        | grep '^bridgeadapter2=' \
        | cut -d'"' -f2) || true

    if [ -n "$bridged" ]; then
        echo "$bridged"
        return
    fi

    die "Cannot determine bridge adapter. Set PXE_BRIDGE or start pxe-vm first."
}

# ── up ───────────────────────────────────────────────────────────

cmd_up() {
    require_cmd vagrant
    require_cmd VBoxManage

    info "Starting pxe-vm ($PXE_MODE mode)..."
    export PXE_MODE
    (cd "$SCRIPT_DIR" && vagrant up pxe-vm)

    if demo_vm_exists; then
        info "Demo VM '$DEMO_VM_NAME' already exists — starting it."
        VBoxManage startvm "$DEMO_VM_NAME" --type gui 2>/dev/null || true
        return
    fi

    info "Creating demo VM '$DEMO_VM_NAME' (${DEMO_VM_RAM}MB RAM)..."

    # Create VM
    VBoxManage createvm --name "$DEMO_VM_NAME" --ostype "Linux_64" --register

    # RAM, CPUs, boot order (network first)
    VBoxManage modifyvm "$DEMO_VM_NAME" \
        --memory "$DEMO_VM_RAM" \
        --cpus "$DEMO_VM_CPUS" \
        --boot1 net \
        --boot2 disk \
        --boot3 none \
        --boot4 none

    # NIC: connect to the same network as pxe-vm's NIC2
    if [ "$PXE_MODE" = "bridged" ]; then
        local bridge
        bridge=$(resolve_bridge)
        info "Using bridge adapter: $bridge"
        VBoxManage modifyvm "$DEMO_VM_NAME" \
            --nic1 bridged \
            --bridgeadapter1 "$bridge" \
            --nictype1 82540EM \
            --nicpromisc1 allow-all
    else
        VBoxManage modifyvm "$DEMO_VM_NAME" \
            --nic1 intnet \
            --intnet1 "pxe-pilot-sandbox" \
            --nictype1 82540EM \
            --nicpromisc1 allow-all
    fi

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
    echo ""
    echo "  Mode:   $PXE_MODE"
    echo "  RAM:    ${DEMO_VM_RAM}MB"
    echo ""
    echo "  The VM will:"
    echo "    1. Get DHCP lease (+ PXE boot info)"
    echo "    2. Download iPXE via TFTP from pxe-pilot"
    echo "    3. iPXE loads the boot menu over HTTP"
    echo "    4. Select a Proxmox version to install"
    echo ""
    echo "  SSH into pxe-vm:"
    echo "    cd sandbox && vagrant ssh pxe-vm"
    echo ""
    echo "  Check health:"
    echo "    vagrant ssh pxe-vm -c 'curl -s localhost:8080/health'"
    echo "============================================"
}

# ── down ─────────────────────────────────────────────────────────

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
        info "Destroying pxe-vm..."
        (cd "$SCRIPT_DIR" && vagrant destroy -f)
    else
        info "No Vagrant state found."
    fi

    echo ">>> Sandbox cleaned up."
}

# ── status ───────────────────────────────────────────────────────

cmd_status() {
    echo "=== pxe-vm ==="
    (cd "$SCRIPT_DIR" && vagrant status pxe-vm 2>/dev/null) || echo "  (no Vagrant state)"
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

    echo "=== Docker containers (via pxe-vm) ==="
    (cd "$SCRIPT_DIR" && vagrant ssh pxe-vm -c \
        "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" 2>/dev/null) \
        || echo "  (cannot reach pxe-vm)"
}

# ── help ─────────────────────────────────────────────────────────

cmd_help() {
    cat <<USAGE
pxe-pilot sandbox — test the full PXE boot chain

Usage: $0 <command>

Commands:
  up       Provision pxe-vm and create a PXE-booting demo VM
  down     Destroy both VMs and clean up
  status   Show the state of sandbox VMs and containers
  help     Show this message

Environment variables:
  PXE_MODE         Network mode: "isolated" (default) or "bridged"
  PXE_BRIDGE       Host NIC for bridged mode (prompted if unset)
  PXE_DHCP_START   First IP in DHCP range  (isolated, default: 10.10.10.100)
  PXE_DHCP_END     Last IP in DHCP range   (isolated, default: 10.10.10.200)
  DEMO_VM_NAME     Demo VM name            (default: pxe-pilot-demo)
  DEMO_VM_RAM      Demo VM RAM in MB       (default: 2048, use 8192 for real installs)

Network modes:
  isolated   Private intnet (10.10.10.0/24), full DHCP, zero network risk.
             Best for safe testing and CI.

  bridged    Bridged to your LAN, proxy DHCP (only PXE, no IP assignment).
             Best for testing with real hardware or when you need internet
             access from the demo VM without NAT.

Prerequisites:
  - VirtualBox (Extension Pack recommended for better PXE ROM)
  - Vagrant

Examples:
  $0 up                                          # Isolated mode (safe default)
  PXE_MODE=bridged PXE_BRIDGE=enp0s3 $0 up       # Bridged to host NIC
  DEMO_VM_RAM=8192 $0 up                          # More RAM for real installs
  $0 down                                         # Tear everything down

See sandbox/README.md for full documentation.
USAGE
}

# ── main ─────────────────────────────────────────────────────────

case "${1:-help}" in
    up)     cmd_up ;;
    down)   cmd_down ;;
    status) cmd_status ;;
    help)   cmd_help ;;
    *)      die "Unknown command: $1 (try '$0 help')" ;;
esac
