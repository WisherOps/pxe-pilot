# Bare-bones Deployment

This is the simplest deployment: pxe-pilot provides both TFTP and HTTP in one container.

## When to use this

- You have no existing PXE infrastructure
- You want the simplest possible setup
- You're okay with pxe-pilot handling TFTP directly
- You're deploying on a single network segment

## Architecture

```
Machine boots
  ↓
DHCP server points to pxe-pilot IP
  ↓
pxe-pilot TFTP serves iPXE binary (port 69)
  ↓
iPXE loads pxe-pilot menu via HTTP (port 8080)
  ↓
User selects Proxmox version
  ↓
Proxmox installer boots, POSTs MACs to pxe-pilot
  ↓
pxe-pilot returns TOML answer file
  ↓
Proxmox installs automatically
```

Everything runs on one machine, one container.

## Prerequisites

- Docker with host networking support
- UDP port 69 (TFTP) available
- TCP port 8080 (HTTP) available
- Control over DHCP server (router, pfSense, etc.)

## Step 1: Build boot assets

```bash
mkdir -p assets

docker run --rm --privileged \
  -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso-url https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso \
  --answer-url http://10.0.0.5:8080/answer
```

Replace `10.0.0.5` with the IP where you'll run pxe-pilot.

## Step 2: Create answer files

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

[network]
source = "from-dhcp"

[disk-setup]
filesystem = "ext4"
disk_list = ["sda"]
EOF
```

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

**Why `--network host`?**

TFTP uses UDP port 69. Docker's port mapping doesn't work well with UDP. Host networking gives the container direct access to the host's network interfaces.

Verify it's running:
```bash
curl http://localhost:8080/health
docker logs pxe-pilot | grep TFTP
```

You should see: `INFO:     TFTP server started on port 69`

## Step 4: Configure DHCP

Tell your DHCP server where to find the PXE boot files.

### pfSense / OPNsense

Services → DHCP Server → (your LAN interface)

Add these settings:
- **Next Server**: `10.0.0.5` (your pxe-pilot IP)
- **Default BIOS file name**: `undionly.kpxe`
- **UEFI 64-bit file name**: `ipxe.efi`

Save and apply.

### Home router (if it supports DHCP options)

Look for "DHCP Options" or "Advanced Settings":
- **Option 66** (next-server): `10.0.0.5`
- **Option 67** (boot-file): `undionly.kpxe` (for BIOS) or `ipxe.efi` (for UEFI)

### dnsmasq

Add to `/etc/dnsmasq.conf` or `/etc/dnsmasq.d/pxe.conf`:

```
dhcp-boot=undionly.kpxe,pxe-pilot,10.0.0.5
```

For UEFI support:
```
dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-match=set:efi-x86_64,option:client-arch,9
dhcp-boot=tag:efi-x86_64,ipxe.efi,pxe-pilot,10.0.0.5
dhcp-boot=undionly.kpxe,pxe-pilot,10.0.0.5
```

Restart dnsmasq: `systemctl restart dnsmasq`

### Windows DHCP Server

1. Open DHCP Manager
2. Expand your server → IPv4 → Scope Options
3. Right-click → Configure Options
4. Check **066 Boot Server Host Name**: Enter `10.0.0.5`
5. Check **067 Bootfile Name**: Enter `undionly.kpxe`

For UEFI, create vendor class:
1. IPv4 → Policies → New Policy
2. Add condition: Vendor Class equals `PXEClient:Arch:00007`
3. Set bootfile to `ipxe.efi`

## Step 5: Test PXE boot

1. Boot target machine
2. Enter BIOS/UEFI setup (usually F2, F12, or DEL)
3. Enable network boot (may be called "PXE Boot" or "Network Stack")
4. Set boot order: Network first
5. Save and exit

The machine should:
1. Get IP from DHCP
2. Download iPXE binary via TFTP
3. Show pxe-pilot menu with available Proxmox versions
4. Let you select and boot into installer
5. Install automatically using your answer file

## Adding more versions

Build another version:
```bash
docker run --rm --privileged -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso-url https://enterprise.proxmox.com/iso/proxmox-ve_8.4-1.iso \
  --answer-url http://10.0.0.5:8080/answer
```

No restart needed. The menu regenerates on each request.

Check what's available:
```bash
curl http://10.0.0.5:8080/menu.ipxe
```

## Host-specific configurations

Create answer files for specific MAC addresses:

```bash
# Machine aa:bb:cc:dd:ee:ff gets static IP
cat > answers/hosts/aa-bb-cc-dd-ee-ff.toml << 'EOF'
[global]
keyboard = "en-us"
country = "us"
fqdn = "pve01.example.com"
mailto = "admin@example.com"
timezone = "America/Los_Angeles"
root-password = "supersecret"

[network]
source = "from-answer"
cidr = "10.0.0.10/24"
dns = "10.0.0.1"
gateway = "10.0.0.1"

[disk-setup]
filesystem = "zfs"
zfs.raid = "raid10"
disk_list = ["sda", "sdb", "sdc", "sdd"]
EOF
```

No restart needed. Files are read on each boot.

## Troubleshooting

### Machine doesn't PXE boot

Check BIOS/UEFI:
- Network boot enabled?
- Network boot in boot order?
- Legacy/UEFI mode matches your boot file (undionly.kpxe = BIOS, ipxe.efi = UEFI)?

Check DHCP:
- Does the machine get an IP address?
- Are DHCP options 66 and 67 set correctly?
- Try `dhcpdump` or packet capture to see DHCP response

### Gets IP but no menu

Check pxe-pilot:
```bash
docker logs pxe-pilot
```

Look for TFTP requests. You should see file requests for `undionly.kpxe` or `ipxe.efi`.

Test HTTP directly:
```bash
curl http://10.0.0.5:8080/menu.ipxe
```

Check firewall:
- UDP port 69 open?
- TCP port 8080 open?

### Menu appears but empty

Check assets exist:
```bash
ls -la assets/
```

You should see `proxmox-ve/9.1-1/vmlinuz` and `initrd`.

Check menu generation:
```bash
curl http://10.0.0.5:8080/menu.ipxe
```

### Installer boots but 404 on answer

Check answer files exist:
```bash
ls -la answers/
```

Note the MAC address from boot console, normalize it:
```bash
# Example: AA:BB:CC:DD:EE:FF → aa-bb-cc-dd-ee-ff
curl http://10.0.0.5:8080/hosts/aa-bb-cc-dd-ee-ff
```

If you get 404, either create that host file or ensure `default.toml` exists.

### Installer fails with error

Check the Proxmox console for specific error. Common issues:
- Disk doesn't exist (`disk_list` references wrong disk)
- Invalid TOML syntax
- Network configuration invalid (bad CIDR, unreachable gateway)

Validate TOML:
```bash
# Install tomli or use online validator
python3 -c "import tomli; tomli.loads(open('answers/default.toml').read())"
```

## Security considerations

### Network isolation

pxe-pilot should run on a trusted network segment:
- Management VLAN
- Isolated homelab network
- Not directly on the internet

### Answer file security

Mount read-only:
```bash
-v ./answers:/answers:ro
```

Use strong passwords in answer files. Change them after first boot:
```bash
ssh root@10.0.0.10
passwd
```

### Temporary deployment

For one-time installs:
1. Start pxe-pilot
2. Run installs
3. Stop and remove container
4. Store answer files securely offline

## Performance

### TFTP is slow

TFTP is inherently slow. The iPXE binaries are small (~100KB), so this is usually fine.

If it's a problem:
- Use gigabit network
- Ensure no network congestion
- Consider HTTP-only deployment with faster TFTP server

### Many simultaneous installs

pxe-pilot handles multiple concurrent installations. Each machine:
1. Downloads iPXE binary once (~100KB)
2. Downloads kernel and initrd once (~1.5GB total)
3. POSTs to `/answer` once (receives ~1KB TOML)

Bottleneck is usually:
- Network bandwidth (1.5GB download per machine)
- Disk I/O if serving from slow storage

For large deployments (10+ simultaneous):
- Use SSD for assets
- Gigabit or faster network
- Consider caching reverse proxy for assets

## Alternatives

**Want to add more boot options?**
- See [With netboot.xyz](with-netboot.md) to integrate with netboot.xyz

**Want to separate TFTP and HTTP?**
- See [HTTP-only mode](http-only.md) to use your own TFTP server

**Want to run behind reverse proxy?**
- See [Configuration Reference](../configuration.md) for `ASSET_URL` and proxy settings
