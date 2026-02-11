# pxe-pilot

![CI Status](https://github.com/WisherOps/pxe-pilot/workflows/CI/badge.svg)

HTTP answer file server for Proxmox VE automated installations.

Proxmox 8.2+ supports fetching answer files over HTTP during automated installs.
The installer POSTs its MAC addresses to a URL and expects a TOML answer file in response.
pxe-pilot is that URL.

## How it works

```
Machine PXE boots → Proxmox installer starts → installer POSTs MACs to pxe-pilot → pxe-pilot returns TOML → Proxmox installs
```

Lookup logic:

1. Check `answers/hosts/{mac}.toml` for each MAC in the request
2. First match wins
3. No match → return `answers/default.toml`
4. No default → 404

No config merging. No validation. Drop a TOML file, it gets served.

## Quick start

```bash
# Create answer files
mkdir -p answers/hosts
cat > answers/default.toml << 'EOF'
[global]
keyboard = "en-us"
country = "us"
fqdn = "pxe-node.local"
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

# Run
docker run -d \
  -p 8080:8080 \
  -v ./answers:/answers:ro \
  ghcr.io/wisherops/pxe-pilot:latest

# Verify
curl http://localhost:8080/health
```

## Adding a host-specific config

```bash
# Filename is the MAC address, lowercase, dashes
cp answers/default.toml answers/hosts/aa-bb-cc-dd-ee-ff.toml
# Edit with host-specific values
# No restart needed — picked up on next request
```

## Endpoints

| Method | Path      | Description                                |
| ------ | --------- | ------------------------------------------ |
| POST   | `/answer` | Proxmox installer hits this. Returns TOML. |
| GET    | `/health` | Health check with config summary.          |

## Configuration

| Variable                | Default    | Description                      |
| ----------------------- | ---------- | -------------------------------- |
| `PXE_PILOT_PORT`        | `8080`     | Listen port                      |
| `PXE_PILOT_ANSWERS_DIR` | `/answers` | TOML files location              |
| `PXE_PILOT_LOG_LEVEL`   | `info`     | `debug`, `info`, `warn`, `error` |

## Development

```bash
# Open in devcontainer (VS Code / Codespaces), then:
pytest server/tests/ -v
ruff check server/
```

## License

TBD
