# pxe-pilot

![CI Status](https://github.com/WisherOps/pxe-pilot/actions/workflows/ci.yml/badge.svg)

Automated Proxmox VE installations via PXE boot. Drop a TOML file, PXE boot a machine, get a working Proxmox cluster.

## What it does

**pxe-pilot** is two Docker images:

- **Server** (`ghcr.io/wisherops/pxe-pilot-server`) - HTTP server that receives MAC addresses from the Proxmox installer and returns the correct TOML answer file
- **Builder** (`ghcr.io/wisherops/pxe-pilot-builder`) - CLI tool that prepares Proxmox ISOs for PXE boot

The Proxmox installer boots over PXE, asks pxe-pilot for its configuration, installs automatically.

## Quick start

```bash
# 1. Build PXE boot assets from a Proxmox ISO
docker run --rm --privileged -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso-url https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso \
  --answer-url http://10.0.0.5:8080/answer

# 2. Create your answer file
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

# 3. Start the server
docker run -d --name pxe-pilot --network host \
  -v ./answers:/answers:ro \
  -v ./assets:/assets:ro \
  -e PXE_PILOT_BOOT_ENABLED=true \
  ghcr.io/wisherops/pxe-pilot-server:latest

# 4. Configure your DHCP server
#    Option 66 (next-server): 10.0.0.5
#    Option 67 (boot-file):   undionly.kpxe (BIOS) or ipxe.efi (UEFI)

# 5. PXE boot a machine
```

The machine boots, installs Proxmox automatically, reboots into your new node.

## Features

- **Zero manual input** - Boot a machine, walk away
- **MAC-based targeting** - Different configs per machine
- **Multi-version support** - Boot PVE 8.4, 9.1, or PBS from one menu
- **Dynamic menus** - New versions appear automatically when built
- **Built-in TFTP** - No netboot.xyz required (but works with it)
- **Small images** - Server is ~50MB, builder handles ISO processing

## Architecture

```
Machine PXE boots
  ↓
DHCP tells it where to find pxe-pilot
  ↓
pxe-pilot TFTP serves iPXE binary
  ↓
iPXE loads pxe-pilot menu (auto-generated from assets/)
  ↓
User selects Proxmox version
  ↓
Proxmox installer boots, POSTs MAC addresses to pxe-pilot
  ↓
pxe-pilot returns the right TOML (host-specific or default)
  ↓
Proxmox installs automatically
```

## Documentation

- **[Quickstart Guide](docs/quickstart.md)** - Get running in 10 minutes
- **[Configuration Reference](docs/configuration.md)** - All environment variables and options
- **[Builder Guide](docs/builder.md)** - Prepare Proxmox ISOs for PXE boot
- **[Answer Files](docs/answer-files.md)** - Create and manage TOML configurations
- **Deployment Scenarios:**
  - [Bare-bones (recommended)](docs/deployment/bare-bones.md) - pxe-pilot only, no netboot.xyz
  - [With netboot.xyz](docs/deployment/with-netboot.md) - Integrate with existing netboot.xyz
  - [HTTP-only mode](docs/deployment/http-only.md) - Use your own TFTP/PXE infrastructure

## Requirements

- Docker
- Network with DHCP server you control
- 8GB+ RAM on target machines (to load PXE boot assets)

## How answer files work

No merging. No validation. Simple file lookup:

1. Proxmox installer POSTs its MAC addresses
2. pxe-pilot checks `answers/hosts/{mac}.toml` for each MAC
3. First match wins
4. No match → return `answers/default.toml`
5. No default → return 404

File format is TOML (Proxmox's answer file format). You provide the content, pxe-pilot serves it.

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | `/answer` | Proxmox installer hits this, receives TOML |
| GET | `/menu.ipxe` | Dynamic iPXE menu (auto-generated from assets) |
| GET | `/boot.ipxe` | Initial boot script (chains to menu) |
| GET | `/hosts` | List all configured MACs |
| GET | `/hosts/{mac}` | View what a MAC would receive |
| GET | `/health` | Health check |
| Static | `/assets/*` | Boot assets (vmlinuz, initrd) |

## Development

```bash
# Run tests
cd server && pytest tests/ -v --cov=. --cov-report=term-missing

# Run linting
ruff check server/
ruff format --check server/

# Open in dev container (matches CI environment)
# See .devcontainer/README.md
```

## License

TBD
