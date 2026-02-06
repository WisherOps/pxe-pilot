# PXE Boot Testing Sandbox

A self-contained environment to test the full PXE boot chain: DHCP, TFTP, netboot.xyz menu, and pxe-pilot answer file delivery.

## Architecture

```
Host Machine
  │
  ├── Vagrant ──► netboot VM (Ubuntu 22.04, bridged NIC)
  │                 └── Docker (network_mode: host)
  │                       ├── pxe-pilot     :8080  (answer files)
  │                       ├── netbootxyz    :69/udp (TFTP), :3000 (web UI), :80 (assets)
  │                       └── dnsmasq       :67/udp (DHCP + PXE options)
  │
  └── VBoxManage / New-VM ──► demo VM (blank, PXE boot only)
                                 └── boots from network → DHCP → TFTP → netboot.xyz menu
```

Both VMs bridge to your host's physical network. The netboot VM's Docker uses `network_mode: host` so DHCP/TFTP broadcast protocols work natively.

## Prerequisites

### Linux / macOS

- [VirtualBox](https://www.virtualbox.org/) (Extension Pack recommended for better PXE support)
- [Vagrant](https://www.vagrantup.com/)
- A physical network adapter (Wi-Fi or Ethernet)

### Windows

- [Hyper-V](https://learn.microsoft.com/en-us/virtualization/hyper-v-on-windows/) enabled
- [Vagrant](https://www.vagrantup.com/)
- An External virtual switch in Hyper-V Manager (default name: `External-LAN`)

## Quick Start

### Linux / macOS

```bash
cd sandbox
./run-demo.sh up
```

### Windows (elevated PowerShell)

```powershell
cd sandbox
.\start.ps1 -Action up
```

This will:

1. Create and provision the **netboot VM** (Ubuntu 22.04 with Docker)
2. Build and start the three Docker containers (pxe-pilot, netbootxyz, dnsmasq)
3. Create a blank **demo VM** that PXE boots from the network
4. The demo VM gets a DHCP lease, downloads netboot.xyz via TFTP, and shows the boot menu

## Configuration

### Environment Variables (Linux/macOS)

| Variable | Default | Description |
|----------|---------|-------------|
| `PXE_BRIDGE` | *(prompted)* | Host NIC for bridged networking |
| `PXE_DHCP_START` | `192.168.1.200` | First IP in DHCP range |
| `PXE_DHCP_END` | `192.168.1.250` | Last IP in DHCP range |
| `DEMO_VM_NAME` | `pxe-sandbox-demo` | VirtualBox demo VM name |

### Parameters (Windows)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-SwitchName` | `External-LAN` | Hyper-V external virtual switch |
| `-DhcpStart` | `192.168.1.200` | First IP in DHCP range |
| `-DhcpEnd` | `192.168.1.250` | Last IP in DHCP range |
| `-DemoVmName` | `pxe-sandbox-demo` | Hyper-V demo VM name |

### Example: Custom DHCP Range

```bash
PXE_DHCP_START=10.0.0.200 PXE_DHCP_END=10.0.0.250 ./run-demo.sh up
```

```powershell
.\start.ps1 -Action up -DhcpStart 10.0.0.200 -DhcpEnd 10.0.0.250
```

## Commands

### Linux / macOS

```bash
./run-demo.sh up       # Start everything
./run-demo.sh down     # Destroy everything
./run-demo.sh status   # Check state of VMs and containers
./run-demo.sh help     # Show usage
```

### Windows

```powershell
.\start.ps1 -Action up
.\start.ps1 -Action down
.\start.ps1 -Action status
```

## Verifying the Setup

Once `up` completes, check that services are running:

```bash
# SSH into the netboot VM
cd sandbox && vagrant ssh netboot

# Check containers
docker ps

# Test pxe-pilot
curl http://localhost:8080/health

# Check dnsmasq logs
docker logs dnsmasq

# Exit VM
exit
```

From your host (replace `<netboot-ip>` with the VM's bridged IP shown during provisioning):

```bash
curl http://<netboot-ip>:8080/health          # pxe-pilot API
open http://<netboot-ip>:3000                  # netboot.xyz web UI
```

## Sandbox Config Files

The sandbox uses its own test configuration in `provision/sandbox-config/`:

- `defaults.toml` — global defaults (en-us, UTC, ext4, test password)
- `hosts/*.toml` — per-host overrides (add your own here)

These are copied into the netboot VM at provision time. To update after changing them:

```bash
cd sandbox && vagrant provision netboot
```

## Teardown

```bash
./run-demo.sh down     # Linux/macOS
.\start.ps1 -Action down   # Windows
```

This removes both VMs and all associated disks.

## Troubleshooting

### Demo VM doesn't get a DHCP lease

- Make sure the DHCP range doesn't overlap with your existing network's DHCP server
- Check dnsmasq logs: `vagrant ssh netboot -c "docker logs dnsmasq"`
- Verify promiscuous mode: the netboot VM needs `--nicpromisc2 allow-all` (set automatically)

### Bridge IP detection fails

The provisioner skips loopback, VirtualBox NAT (`10.0.2.x`), and Docker interfaces. If your bridged adapter isn't detected:

```bash
PXE_BRIDGE="eth0" vagrant provision netboot
```

### VirtualBox PXE boot shows "No bootable medium"

- Install the [VirtualBox Extension Pack](https://www.virtualbox.org/wiki/Downloads) for better PXE ROM support
- The demo VM uses `82540EM` (Intel PRO/1000) which has the best PXE compatibility

### netboot.xyz menu loads but installers fail

The demo VM needs internet access to download OS installers. Since it's bridged to your physical network, it should get internet via your router. Verify:

- Your router provides a default gateway and DNS
- The DHCP range IPs can reach the internet

### Re-provisioning

To re-detect the network and restart containers without recreating the VM:

```bash
cd sandbox && vagrant provision netboot
```
