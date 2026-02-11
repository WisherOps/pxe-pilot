# pxe-pilot Sandbox

Test the full PXE boot chain end-to-end: DHCP → TFTP → iPXE menu → kernel download → answer file delivery.

## Architecture

```
Host Machine
  │
  ├── Vagrant ──► pxe-vm (Ubuntu 22.04)
  │                 └── Docker (network_mode: host)
  │                       ├── pxe-pilot   :8080 (HTTP API + menu) + :69/udp (TFTP + iPXE)
  │                       └── dnsmasq     :67/udp (DHCP with PXE boot options)
  │
  └── Hyper-V / VBox ──► demo VM (blank, PXE boot only)
                           └── DHCP → TFTP(iPXE) → HTTP menu → kernel + initrd → /answer
```

## Network Modes

|          | **Isolated** (default for VBox) | **Bridged** (default for Hyper-V)              |
| -------- | ------------------------------- | ---------------------------------------------- |
| Network  | Private 10.10.10.0/24           | Your real LAN                                  |
| DHCP     | Full — dnsmasq assigns IPs      | Proxy — your router assigns IPs                |
| Internet | NAT via pxe-vm                  | Direct via your router                         |
| Risk     | **Zero** — completely sandboxed | **Low** — proxy DHCP only talks to PXE clients |
| Best for | Safe testing, CI, demos         | Real hardware, Hyper-V                         |

## Prerequisites

### Windows (Hyper-V)

- [Hyper-V](https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/) enabled
- [Vagrant](https://www.vagrantup.com/)
- An External virtual switch for bridged mode (default name: `External-LAN`)

### Linux / macOS (VirtualBox)

- [VirtualBox](https://www.virtualbox.org/) (Extension Pack recommended for PXE ROM support)
- [Vagrant](https://www.vagrantup.com/)

## Quick Start

### Windows (elevated PowerShell)

```powershell
cd sandbox

# Bridged mode (default) — uses your External-LAN switch
.\start.ps1 -Action up

# Isolated mode — private switch, no network risk
.\start.ps1 -Action up -NetworkMode isolated

# Custom external switch name
.\start.ps1 -Action up -SwitchName "My External Switch"

# More RAM for real Proxmox installs
.\start.ps1 -Action up -DemoVmMemoryMB 8192
```

### Linux / macOS

```bash
cd sandbox

# Isolated mode (default) — safest option
./run-demo.sh up

# Bridged mode — join your LAN
PXE_MODE=bridged PXE_BRIDGE=enp0s3 ./run-demo.sh up

# More RAM for real Proxmox installs
DEMO_VM_RAM=8192 ./run-demo.sh up
```

## What Happens

1. Vagrant creates **pxe-vm** (Ubuntu 22.04) and provisions it:
   - Installs Docker
   - Pulls `ghcr.io/wisherops/pxe-pilot-server:latest` from GitHub Container Registry
   - Starts pxe-pilot (HTTP + TFTP) and dnsmasq (DHCP) via docker-compose
   - Creates fake PXE assets for chain testing

2. The launcher creates a blank **demo VM** that PXE boots:
   - Gets a DHCP lease + PXE boot file info from dnsmasq
   - Downloads `ipxe.efi` (UEFI) or `undionly.kpxe` (BIOS) via TFTP
   - iPXE chains to `http://<pxe-vm>:8080/boot.ipxe` → `/menu.ipxe`
   - Menu shows available Proxmox versions
   - Selecting a version downloads vmlinuz + initrd over HTTP

With fake assets, the chain validates up to the kernel download (which fails gracefully since the kernel is fake). With real assets from the builder, it performs a full Proxmox installation.

## Configuration

### Windows Parameters

| Parameter         | Default          | Description                                |
| ----------------- | ---------------- | ------------------------------------------ |
| `-NetworkMode`    | `bridged`        | `bridged` or `isolated`                    |
| `-SwitchName`     | `External-LAN`   | Hyper-V external switch (bridged mode)     |
| `-DemoVmName`     | `pxe-pilot-demo` | Demo VM name                               |
| `-DemoVmMemoryMB` | `2048`           | Demo VM RAM (use `8192` for real installs) |

### Linux / macOS Environment Variables

| Variable         | Default          | Description                       |
| ---------------- | ---------------- | --------------------------------- |
| `PXE_MODE`       | `isolated`       | `bridged` or `isolated`           |
| `PXE_BRIDGE`     | _(prompted)_     | Host NIC for bridged mode         |
| `PXE_DHCP_START` | `10.10.10.100`   | First IP in DHCP range (isolated) |
| `PXE_DHCP_END`   | `10.10.10.200`   | Last IP in DHCP range (isolated)  |
| `DEMO_VM_NAME`   | `pxe-pilot-demo` | VirtualBox demo VM name           |
| `DEMO_VM_RAM`    | `2048`           | Demo VM RAM in MB                 |

## Using Real PXE Assets

By default the sandbox creates fake assets (tiny placeholder files) for chain testing. To test a real Proxmox installation:

1. Start the sandbox: `.\start.ps1 -Action up` (or `./run-demo.sh up`)
2. SSH into pxe-vm: `vagrant ssh pxe-vm`
3. Run the builder with a real ISO:

```bash
# Download Proxmox VE ISO (or copy it in)
cd /opt/pxe-pilot-sandbox

# Run the builder container
docker run --rm \
    -v ./assets:/output \
    -v /path/to/proxmox-ve_8.4-1.iso:/input/proxmox.iso:ro \
    pxe-pilot-builder:local

# Restart pxe-pilot to pick up the new assets
docker compose restart pxe-pilot
```

4. Recreate the demo VM with more RAM:

```powershell
.\start.ps1 -Action down
.\start.ps1 -Action up -DemoVmMemoryMB 8192
```

## Commands

### Windows

```powershell
.\start.ps1 -Action up       # Start everything
.\start.ps1 -Action down     # Destroy everything
.\start.ps1 -Action status   # Check state
```

### Linux / macOS

```bash
./run-demo.sh up       # Start everything
./run-demo.sh down     # Destroy everything
./run-demo.sh status   # Check state
./run-demo.sh help     # Show usage
```

## Verifying the Setup

```bash
# SSH into pxe-vm
cd sandbox && vagrant ssh pxe-vm

# Check containers are running
docker ps

# Test pxe-pilot health
curl -s http://localhost:8080/health | python3 -m json.tool

# View the iPXE menu
curl -s http://localhost:8080/menu.ipxe

# Check iPXE binaries are being served
ls -la /opt/pxe-pilot-sandbox/
docker exec pxe-pilot-sandbox-pxe-pilot-1 ls -la /app/ipxe/

# Check dnsmasq is running
docker logs pxe-pilot-sandbox-dnsmasq-1

# Exit
exit
```

## Teardown

```powershell
.\start.ps1 -Action down     # Windows
```

```bash
./run-demo.sh down            # Linux / macOS
```

This removes both VMs, virtual disks, and (in isolated mode) the private Hyper-V switch.

## Troubleshooting

### Demo VM doesn't get a DHCP lease

- **Isolated mode:** Check dnsmasq logs: `vagrant ssh pxe-vm -c "cd /opt/pxe-pilot-sandbox && docker compose logs dnsmasq"`
- **Bridged mode:** Make sure your router's DHCP is working. Proxy DHCP only adds PXE boot info — your router still assigns IPs.
- Verify both VMs are on the same switch/network.

### Demo VM gets IP but doesn't PXE boot

- Hyper-V Gen2 VMs must have **Secure Boot disabled** (the launcher does this automatically).
- VirtualBox needs the Extension Pack for best PXE ROM support.
- Check that pxe-pilot's TFTP is running: `vagrant ssh pxe-vm -c "docker exec pxe-pilot-sandbox-pxe-pilot-1 netstat -ulnp"`

### iPXE loads but menu fails

- Check the HTTP endpoint: `vagrant ssh pxe-vm -c "curl -s localhost:8080/menu.ipxe"`
- If the menu is empty, verify assets exist in `/opt/pxe-pilot-sandbox/assets/`.

### Bridged mode — proxy DHCP not responding

- Ensure dnsmasq can see PXE broadcast traffic. Check: `vagrant ssh pxe-vm -c "cd /opt/pxe-pilot-sandbox && docker compose logs dnsmasq"`
- Some corporate networks filter DHCP broadcasts between VLANs.

### Re-provisioning

To rebuild the image and restart services without recreating the VM:

```bash
cd sandbox && vagrant provision pxe-vm
```
