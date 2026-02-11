# Quickstart Guide

Get pxe-pilot running in 10 minutes and PXE boot your first Proxmox node.

## Prerequisites

- Docker installed
- Network with DHCP server you control (router, pfSense, OPNsense, etc.)
- Target machine with 8GB+ RAM
- Proxmox ISO or URL to download one

## Step 1: Build PXE boot assets

The builder takes a Proxmox ISO and creates PXE boot files:

```bash
mkdir -p assets

docker run --rm --privileged \
  -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso-url https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso \
  --answer-url http://10.0.0.5:8080/answer
```

Replace `10.0.0.5` with the IP where you'll run pxe-pilot.

This creates:
```
assets/
└── proxmox-ve/
    └── 9.1-1/
        ├── vmlinuz
        └── initrd
```

## Step 2: Create answer file

```bash
mkdir -p answers

cat > answers/default.toml << 'EOF'
[global]
keyboard = "en-us"
country = "us"
fqdn = "pve-node.local"
mailto = "admin@example.com"
timezone = "America/Los_Angeles"
root-password = "changeme"
reboot-on-error = true

[network]
source = "from-dhcp"

[disk-setup]
filesystem = "ext4"
disk_list = ["sda"]
EOF
```

This is the configuration every machine will receive unless you create host-specific files.

## Step 3: Start pxe-pilot

```bash
docker run -d \
  --name pxe-pilot \
  --network host \
  -v ./answers:/answers:ro \
  -v ./assets:/assets:ro \
  -e PXE_PILOT_BOOT_ENABLED=true \
  ghcr.io/wisherops/pxe-pilot-server:latest
```

`--network host` is required for TFTP (UDP port 69).

Verify it's running:
```bash
curl http://localhost:8080/health
```

## Step 4: Configure DHCP

Tell your DHCP server where to find pxe-pilot. This varies by platform:

### pfSense / OPNsense

Services → DHCP Server → (your LAN)
- Next Server: `10.0.0.5`
- Default BIOS file name: `undionly.kpxe`
- UEFI 64-bit file name: `ipxe.efi`

### Home router with DHCP options

- Option 66 (next-server): `10.0.0.5`
- Option 67 (bootfile-name): `undionly.kpxe` (BIOS) or `ipxe.efi` (UEFI)

### dnsmasq

```
dhcp-boot=undionly.kpxe,pxe-pilot,10.0.0.5
```

## Step 5: PXE boot a machine

1. Boot target machine
2. Enter BIOS/UEFI
3. Enable PXE boot (often called "Network Boot")
4. Set boot order: Network first
5. Save and reboot

The machine boots iPXE, shows the pxe-pilot menu, you select the version, Proxmox installs automatically.

## Next steps

- **Host-specific configs**: See [Answer Files](answer-files.md)
- **Multiple versions**: Run the builder again with different ISOs
- **Different deployment**: See [Deployment Scenarios](deployment/)
- **Configuration options**: See [Configuration Reference](configuration.md)

## Troubleshooting

**Machine boots but doesn't PXE:**
- Check DHCP options are correct
- Verify network boot is enabled in BIOS/UEFI

**Gets an IP but no menu:**
- Check pxe-pilot is reachable: `curl http://10.0.0.5:8080/health`
- Check TFTP is running: `docker logs pxe-pilot | grep TFTP`

**Menu appears but no versions:**
- Verify assets exist: `ls -la assets/proxmox-ve/`
- Check `/menu.ipxe`: `curl http://10.0.0.5:8080/menu.ipxe`

**Installer boots but errors:**
- Check answer file: `curl http://10.0.0.5:8080/hosts/aa-bb-cc-dd-ee-ff`
- Review Proxmox answer file format
