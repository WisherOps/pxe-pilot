# Deployment with netboot.xyz

Integrate pxe-pilot with netboot.xyz to add Proxmox automated installs to your existing PXE menu.

## When to use this

- You already run netboot.xyz
- You want to keep netboot.xyz for other operating systems
- You want a unified boot menu for everything
- You're comfortable editing netboot.xyz menus

## Architecture

```
Machine boots
  ↓
DHCP server points to netboot.xyz
  ↓
netboot.xyz TFTP serves iPXE binary
  ↓
netboot.xyz menu loads
  ↓
User selects "Proxmox (pxe-pilot)"
  ↓
Chains to pxe-pilot menu via HTTP
  ↓
User selects Proxmox version
  ↓
Proxmox installer boots, POSTs MACs to pxe-pilot
  ↓
pxe-pilot returns TOML answer file
  ↓
Proxmox installs automatically
```

netboot.xyz handles TFTP and initial boot menu. pxe-pilot provides Proxmox installer and answer files.

## Prerequisites

- Working netboot.xyz installation
- Docker for pxe-pilot
- Access to edit netboot.xyz menus

## Step 1: Build boot assets

```bash
mkdir -p assets

docker run --rm --privileged \
  -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso-url https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso \
  --answer-url http://10.0.0.5:8080/answer
```

Replace `10.0.0.5` with your pxe-pilot IP.

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

## Step 3: Start pxe-pilot (HTTP-only mode)

```bash
docker run -d \
  --name pxe-pilot \
  -p 8080:8080 \
  -v ./answers:/answers:ro \
  -v ./assets:/assets:ro \
  ghcr.io/wisherops/pxe-pilot-server:latest
```

**No TFTP**: netboot.xyz provides that. pxe-pilot only serves HTTP.

**Port mapping works**: No need for `--network host` since we're not running TFTP.

Verify:
```bash
curl http://localhost:8080/health
curl http://localhost:8080/menu.ipxe
```

## Step 4: Add pxe-pilot to netboot.xyz menu

You need to add a menu entry that chains to pxe-pilot.

### Option A: Custom menu (recommended)

Create `/config/menus/custom.ipxe` in your netboot.xyz volume:

```ipxe
#!ipxe
###
### Custom menu - Proxmox via pxe-pilot
###

:custom
menu Custom Options
item --gap Proxmox VE Automated Install
item proxmox_pilot Proxmox (pxe-pilot)
item --gap
item return Return to main menu
choose --default return --timeout 10000 option && goto ${option}

:proxmox_pilot
chain http://10.0.0.5:8080/menu.ipxe || goto custom

:return
chain utils.ipxe
```

Replace `10.0.0.5` with your pxe-pilot IP.

netboot.xyz automatically includes `custom.ipxe` if it exists.

### Option B: Edit main menu

If running netboot.xyz from source, edit `menus/main.ipxe`:

```ipxe
item proxmox Proxmox VE (pxe-pilot)
```

Add handler:
```ipxe
:proxmox
chain http://10.0.0.5:8080/menu.ipxe || goto main_menu
```

### Option C: Dynamic menu via HTTP

If your netboot.xyz uses `menu.ipxe.cfg` for customization:

```
# Add to menu.ipxe.cfg
item proxmox Proxmox VE Automated Install
set proxmox_menu http://10.0.0.5:8080/menu.ipxe
```

Check your netboot.xyz documentation for the exact method.

## Step 5: Test the integration

1. PXE boot a machine
2. You should see netboot.xyz menu
3. Select "Proxmox (pxe-pilot)" or your custom menu item
4. pxe-pilot menu appears with available Proxmox versions
5. Select version, machine installs automatically

## netboot.xyz deployment types

### Self-hosted netboot.xyz

If you run netboot.xyz in Docker:

```bash
docker run -d \
  --name netbootxyz \
  --network host \
  -e MENU_VERSION=2.0.76 \
  -v ./netboot-config:/config \
  -v ./netboot-assets:/assets \
  ghcr.io/netbootxyz/netbootxyz:latest
```

Add `custom.ipxe` to `./netboot-config/menus/`:

```bash
cat > netboot-config/menus/custom.ipxe << 'EOF'
#!ipxe
:custom
menu Custom Menu
item proxmox Proxmox VE (pxe-pilot)
choose option && goto ${option}

:proxmox
chain http://10.0.0.5:8080/menu.ipxe || goto custom
EOF
```

Restart netboot.xyz:
```bash
docker restart netbootxyz
```

### netboot.xyz on dedicated hardware

If netboot.xyz runs on dedicated server (Pi, NUC, etc.), mount the config directory and edit menus there.

Common locations:
- Docker: `/config/menus/`
- Bare metal: `/etc/netbootxyz/menus/`

### netboot.xyz from ISO

If you boot netboot.xyz from ISO media, you can't easily customize menus. Consider:
1. Switch to self-hosted netboot.xyz (Docker or bare metal)
2. Use HTTP-only deployment and skip netboot.xyz integration

## Advanced: Conditional menu

Show pxe-pilot option only if available:

```ipxe
#!ipxe
:custom
menu Custom Options
item --gap Proxmox VE Automated Install
iseq ${platform} efi && set pxe_pilot_available true || set pxe_pilot_available false
iseq ${pxe_pilot_available} true && item proxmox Proxmox (pxe-pilot) || item proxmox_unavailable Proxmox (unavailable)
choose option && goto ${option}

:proxmox
chain --timeout 3000 http://10.0.0.5:8080/menu.ipxe || goto proxmox_failed

:proxmox_failed
echo Failed to load pxe-pilot menu
sleep 3
goto custom

:proxmox_unavailable
echo pxe-pilot not available on this platform
sleep 3
goto custom
```

## Multiple pxe-pilot instances

Run separate instances for different purposes:

```bash
# Production Proxmox
docker run -d --name pxe-pilot-prod \
  -p 8080:8080 \
  -v ./answers-prod:/answers:ro \
  -v ./assets-prod:/assets:ro \
  ghcr.io/wisherops/pxe-pilot-server:latest

# Development Proxmox
docker run -d --name pxe-pilot-dev \
  -p 8081:8080 \
  -v ./answers-dev:/answers:ro \
  -v ./assets-dev:/assets:ro \
  ghcr.io/wisherops/pxe-pilot-server:latest
```

Add both to netboot.xyz menu:

```ipxe
item proxmox_prod Proxmox Production
item proxmox_dev Proxmox Development

:proxmox_prod
chain http://10.0.0.5:8080/menu.ipxe || goto custom

:proxmox_dev
chain http://10.0.0.5:8081/menu.ipxe || goto custom
```

## Behind a reverse proxy

If pxe-pilot runs behind nginx or traefik:

```bash
docker run -d --name pxe-pilot \
  -p 8080:8080 \
  -v ./answers:/answers:ro \
  -v ./assets:/assets:ro \
  -e PXE_PILOT_ASSET_URL=https://pxe.example.com \
  ghcr.io/wisherops/pxe-pilot-server:latest
```

Update netboot.xyz menu:
```ipxe
:proxmox
chain https://pxe.example.com/menu.ipxe || goto custom
```

See [Configuration Reference](../configuration.md) for proxy settings.

## Troubleshooting

### netboot.xyz menu doesn't show pxe-pilot option

Check custom menu syntax:
```bash
cat netboot-config/menus/custom.ipxe
```

Look for syntax errors (missing `#!ipxe` header, typos in `:labels`).

Restart netboot.xyz:
```bash
docker restart netbootxyz
```

Test menu directly:
```bash
curl http://10.0.0.5/custom.ipxe
```

### Chains to pxe-pilot but menu is empty

Check pxe-pilot has assets:
```bash
curl http://10.0.0.5:8080/menu.ipxe
```

If empty, verify assets exist:
```bash
ls -la assets/proxmox-ve/
```

### Chain fails with timeout

Check network connectivity:
```bash
# From netboot.xyz container
docker exec -it netbootxyz ping 10.0.0.5
```

Check pxe-pilot is reachable:
```bash
curl http://10.0.0.5:8080/health
```

Firewall blocking? Open TCP port 8080.

### Works from some machines, not others

Check if it's BIOS vs UEFI:
- BIOS machines may handle HTTP differently than UEFI
- Try setting `PXE_PILOT_ASSET_URL` explicitly

Check client logs in netboot.xyz for errors.

## Benefits of this approach

**Unified boot experience**: One menu for everything (Linux distros, Windows, Proxmox)

**Flexibility**: Keep netboot.xyz's infrastructure, add Proxmox automation

**Separation of concerns**: netboot.xyz handles PXE, pxe-pilot handles Proxmox configs

**Easy updates**: Update pxe-pilot independently without touching netboot.xyz

## Alternatives

**Want simpler deployment without netboot.xyz?**
- See [Bare-bones deployment](bare-bones.md) for pxe-pilot-only setup

**Want to use your own TFTP server?**
- See [HTTP-only mode](http-only.md) for maximum flexibility

**Want to migrate away from netboot.xyz later?**
- Switch to bare-bones deployment by enabling `BOOT_ENABLED=true`
- Update DHCP to point to pxe-pilot
- No answer file changes needed
