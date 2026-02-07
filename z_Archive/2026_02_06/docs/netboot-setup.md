# netboot.xyz Setup Guide

This guide explains how to set up [netboot.xyz](https://netboot.xyz) to work with pxe-pilot for automated Proxmox VE installations.

## Architecture Overview

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   PXE Client    │────>│  netboot.xyz    │────>│   pxe-pilot     │
│   (bare metal)  │     │  (boot menu)    │     │  (answer file)  │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        │  1. DHCP/TFTP         │  2. iPXE menu        │
        │  (get boot files)     │  (select Proxmox)    │
        │                       │                      │
        │                       │  3. Boot kernel      │
        │                       │                      │
        └───────────────────────┴──────────────────────┘
                                        │
                                4. POST to pxe-pilot
                                   (get answer.toml)
```

## Option 1: Docker Deployment (Recommended)

### netboot.xyz Container

```yaml
# docker-compose.yml
services:
  netbootxyz:
    image: ghcr.io/netbootxyz/netbootxyz:latest
    container_name: netbootxyz
    network_mode: host  # Required for DHCP/TFTP
    volumes:
      - ./netboot/config:/config
      - ./netboot/assets:/assets
    environment:
      - MENU_VERSION=2.0.76
    restart: unless-stopped

  pxe-pilot:
    image: ghcr.io/wisherops/pxe-pilot:latest
    container_name: pxe-pilot
    ports:
      - "8080:8080"
    volumes:
      - ./config:/config:ro
    restart: unless-stopped
```

### DHCP Configuration

netboot.xyz needs to provide boot information via DHCP. You have several options:

#### A. Use netboot.xyz's Built-in DHCP (Simple)

If you don't have an existing DHCP server:

```yaml
# In docker-compose.yml
services:
  netbootxyz:
    # ... other settings ...
    environment:
      - DHCP_RANGE_START=10.0.0.100
      - DHCP_RANGE_END=10.0.0.200
      - DHCP_GATEWAY=10.0.0.1
      - DHCP_DNS=10.0.0.1
```

#### B. Configure Existing DHCP Server (Recommended for Production)

Add these options to your existing DHCP server:

**For dnsmasq:**
```conf
# /etc/dnsmasq.conf
dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-boot=tag:efi-x86_64,netboot.xyz.efi,,10.0.0.5
dhcp-boot=netboot.xyz.kpxe,,10.0.0.5
```

**For ISC DHCP:**
```conf
# /etc/dhcp/dhcpd.conf
option arch code 93 = unsigned integer 16;

if option arch = 00:07 {
    filename "netboot.xyz.efi";
} else {
    filename "netboot.xyz.kpxe";
}
next-server 10.0.0.5;  # netboot.xyz server IP
```

**For pfSense/OPNsense:**
- Services > DHCP Server > [interface]
- TFTP Server: `10.0.0.5`
- Network boot:
  - Enable: Yes
  - Next Server: `10.0.0.5`
  - Default BIOS filename: `netboot.xyz.kpxe`
  - UEFI 64-bit filename: `netboot.xyz.efi`

## Option 2: VM/Bare Metal Deployment

### Install netboot.xyz

```bash
# Download netboot.xyz assets
mkdir -p /srv/tftp
cd /srv/tftp
wget https://boot.netboot.xyz/ipxe/netboot.xyz.kpxe
wget https://boot.netboot.xyz/ipxe/netboot.xyz.efi
```

### Configure dnsmasq

```bash
# Install dnsmasq
apt install dnsmasq

# Configure /etc/dnsmasq.conf
interface=eth0
bind-interfaces
dhcp-range=10.0.0.100,10.0.0.200,12h

# PXE boot
enable-tftp
tftp-root=/srv/tftp

dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-boot=tag:efi-x86_64,netboot.xyz.efi
dhcp-boot=netboot.xyz.kpxe
```

## Configuring Proxmox Boot with pxe-pilot

### Custom iPXE Menu (Optional)

To automatically boot Proxmox with pxe-pilot, create a custom menu:

```bash
# /config/menus/local/custom.ipxe
#!ipxe

:proxmox
set pxe_pilot_url http://10.0.0.5:8080
kernel https://boot.netboot.xyz/ipxe/proxmox/vmlinuz proxmox-start-auto-install proxmox-auto-install-cfg-url=${pxe_pilot_url}/answer
initrd https://boot.netboot.xyz/ipxe/proxmox/initrd.img
boot
```

### Proxmox Kernel Parameters

The Proxmox installer needs these kernel parameters to fetch the answer file:

```
proxmox-start-auto-install proxmox-auto-install-cfg-url=http://10.0.0.5:8080/answer
```

Where:
- `proxmox-start-auto-install` - Enables automated installation mode
- `proxmox-auto-install-cfg-url` - URL to fetch the answer file (your pxe-pilot server)

## Testing the Setup

### 1. Verify netboot.xyz is Running

```bash
# Check TFTP
tftp 10.0.0.5 -c get netboot.xyz.kpxe

# Check the menu loads
curl http://10.0.0.5:3000  # netboot.xyz web UI
```

### 2. Verify pxe-pilot is Running

```bash
# Health check
curl http://10.0.0.5:8080/health

# List configured hosts
curl http://10.0.0.5:8080/hosts

# Test answer file generation
curl -X POST http://10.0.0.5:8080/answer \
  -H "Content-Type: application/json" \
  -d '{"network_interfaces": [{"mac": "AA:BB:CC:DD:EE:FF"}]}'
```

### 3. Test PXE Boot

1. Create a test VM with PXE boot enabled
2. Set boot order: Network first
3. Start VM and watch for netboot.xyz menu
4. Select Proxmox VE
5. Verify installer fetches answer file from pxe-pilot logs

## Troubleshooting

### Client doesn't get DHCP

- Check DHCP server is running and has correct range
- Verify client is on same network/VLAN
- Check firewall allows DHCP (UDP 67/68)

### Client gets DHCP but no boot file

- Verify TFTP server is running (UDP 69)
- Check next-server/filename options in DHCP
- Test TFTP manually: `tftp <server> -c get netboot.xyz.kpxe`

### netboot.xyz menu loads but Proxmox fails

- Verify Proxmox ISO assets are available
- Check kernel parameters include pxe-pilot URL
- Verify pxe-pilot is reachable from boot environment

### Proxmox boots but no answer file

- Check pxe-pilot logs for incoming requests
- Verify MAC address matches config file
- Test answer endpoint manually with curl

## Network Requirements

| Service | Port | Protocol | Direction |
|---------|------|----------|-----------|
| DHCP | 67, 68 | UDP | Bidirectional |
| TFTP | 69 | UDP | Client → Server |
| HTTP (netboot.xyz) | 3000 | TCP | Client → Server |
| HTTP (pxe-pilot) | 8080 | TCP | Client → Server |

## Security Considerations

- **Network Segmentation**: Run PXE services on a dedicated management VLAN
- **Answer File Security**: Answer files may contain sensitive data (passwords)
- **HTTPS**: Consider using HTTPS for pxe-pilot in production
- **MAC Filtering**: Only known MACs should receive answer files
