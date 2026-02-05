# pxe-pilot

A composable PXE boot config engine for automated Proxmox VE installs using TOML configs.

## Overview

pxe-pilot serves per-host answer files for Proxmox automated installation. It integrates with [netboot.xyz](https://netboot.xyz) for boot delivery, providing a **config engine** that dynamically generates answer files based on the requesting host's MAC address.

```
netboot.xyz (DHCP/TFTP/iPXE)  -->  Proxmox installer  -->  pxe-pilot (answer file)
```

## Features

- **TOML-based configuration** - Human-readable config files
- **Per-host customization** - Override defaults for each host by MAC address
- **Simple HTTP API** - Proxmox installer fetches answer file via POST
- **Docker-ready** - Deploy as container or standalone
- **Stateless** - No database required, config files are the source of truth

## Quick Start

### 1. Install

```bash
# Using pip
pip install pxe-pilot

# Or using uv
uv pip install pxe-pilot

# Or run from source
git clone https://github.com/WisherOps/pxe-pilot.git
cd pxe-pilot
pip install -e .
```

### 2. Configure

Create your config directory:

```bash
mkdir -p config/hosts
```

Create `config/defaults.toml`:

```toml
[global]
keyboard = "en-us"
country = "us"
timezone = "America/New_York"

[network]
dns = "1.1.1.1"

[disk]
filesystem = "zfs"
```

Create a host config `config/hosts/aa-bb-cc-dd-ee-ff.toml`:

```toml
hostname = "pve-node-01"

[network]
address = "10.0.0.10/24"
gateway = "10.0.0.1"

[disk]
target = "/dev/sda"
```

### 3. Run

```bash
# Start the server
pxe-pilot serve --config-dir ./config --port 8080

# Or with environment variables
CONFIG_DIR=./config PORT=8080 pxe-pilot serve
```

### 4. Configure netboot.xyz

See [docs/netboot-setup.md](docs/netboot-setup.md) for netboot.xyz configuration instructions.

## Docker

```bash
docker run -d \
  -p 8080:8080 \
  -v $(pwd)/config:/config \
  ghcr.io/wisherops/pxe-pilot:latest
```

Or with docker-compose:

```yaml
services:
  pxe-pilot:
    image: ghcr.io/wisherops/pxe-pilot:latest
    ports:
      - "8080:8080"
    volumes:
      - ./config:/config
```

## Configuration

### defaults.toml

Global defaults applied to all hosts:

```toml
[global]
keyboard = "en-us"
country = "us"
timezone = "America/New_York"
root_password_hash = "$5$rounds=5000$..."  # SHA-256 hash

[network]
dns = "1.1.1.1"

[disk]
filesystem = "zfs"  # or ext4, xfs
```

### hosts/<mac>.toml

Per-host overrides (MAC address as filename, lowercase with hyphens):

```toml
hostname = "pve-node-01"

[network]
address = "10.0.0.10/24"
gateway = "10.0.0.1"
dns = "10.0.0.1"  # Override default DNS

[disk]
target = "/dev/nvme0n1"
```

## API

### POST /answer

Proxmox installer posts system info, receives answer file.

**Request:**
```json
{
  "network_interfaces": [
    {"mac": "AA:BB:CC:DD:EE:FF", "name": "eth0"}
  ]
}
```

**Response:**
```toml
[global]
keyboard = "en-us"
country = "us"
timezone = "America/New_York"

[network]
address = "10.0.0.10/24"
gateway = "10.0.0.1"
dns = "1.1.1.1"

[disk]
filesystem = "zfs"
target = "/dev/sda"
```

### GET /health

Health check endpoint.

## Development

```bash
# Clone and install dev dependencies
git clone https://github.com/WisherOps/pxe-pilot.git
cd pxe-pilot
pip install -e ".[dev]"

# Run tests
pytest

# Run linter
ruff check .

# Run formatter
ruff format .
```

## Architecture

pxe-pilot is designed to work with netboot.xyz for the complete PXE boot chain:

1. **netboot.xyz** handles DHCP, TFTP, and iPXE menu
2. **Proxmox installer** boots and requests answer file
3. **pxe-pilot** identifies host by MAC, merges configs, returns answer.toml
4. **Proxmox** installs automatically with the provided configuration

## License

MIT License - see [LICENSE](LICENSE)
