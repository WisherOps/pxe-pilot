# Configuration Reference

All configuration happens via environment variables passed to the Docker container.

## Server Configuration

### Core Settings

| Variable | Default | Description |
|----------|---------|-------------|
| `PXE_PILOT_PORT` | `8080` | HTTP listen port |
| `PXE_PILOT_ANSWERS_DIR` | `/answers` | Directory containing TOML answer files |
| `PXE_PILOT_ASSETS_DIR` | `/assets` | Directory containing PXE boot assets (vmlinuz, initrd) |
| `PXE_PILOT_LOG_LEVEL` | `info` | Log level: `debug`, `info`, `warn`, `error` |

### Boot Mode (TFTP + iPXE binaries)

| Variable | Default | Description |
|----------|---------|-------------|
| `PXE_PILOT_BOOT_ENABLED` | `false` | Enable built-in TFTP server and iPXE binaries |
| `PXE_PILOT_TFTP_PORT` | `69` | TFTP listen port (only when `BOOT_ENABLED=true`) |

When `BOOT_ENABLED=true`:
- Starts TFTP server on port 69
- Serves bundled iPXE binaries (`undionly.kpxe` for BIOS, `ipxe.efi` for UEFI)
- Enables `/boot.ipxe` endpoint
- Requires `--network host` for UDP port access

When `BOOT_ENABLED=false` (default):
- HTTP-only mode
- Use your own TFTP server (netboot.xyz, standalone TFTP, etc.)
- `/menu.ipxe` still works for dynamic menus

### Asset URLs

| Variable | Default | Description |
|----------|---------|-------------|
| `PXE_PILOT_ASSET_URL` | Auto-detected | Base URL for assets in iPXE menu entries |

If not set, auto-detects from request headers:
- Uses `Host` header and `X-Forwarded-Proto` if behind a proxy
- Falls back to `http://localhost:8080`

Set explicitly when:
- Behind a reverse proxy
- Using a CDN for assets
- Clients access via different hostname than request headers indicate

Example:
```bash
-e PXE_PILOT_ASSET_URL=http://10.0.0.5:8080
```

### Proxy Support

| Variable | Default | Description |
|----------|---------|-------------|
| `PXE_PILOT_TRUSTED_PROXIES` | None | CIDR ranges to trust `X-Forwarded-For` from |

Only needed when behind a reverse proxy and you need real client IPs in logs.

Example:
```bash
-e PXE_PILOT_TRUSTED_PROXIES=172.16.0.0/12,10.0.0.0/8
```

## Volume Mounts

### Required

```bash
-v ./answers:/answers:ro
```

Contains TOML answer files. Structure:
```
answers/
├── default.toml        # Fallback for unmatched MACs
└── hosts/
    ├── aa-bb-cc-dd-ee-ff.toml
    └── ab-cd-ef-01-23-45.toml
```

Mount read-only (`:ro`) for safety.

### Optional

```bash
-v ./assets:/assets:ro
```

Contains PXE boot assets built by pxe-pilot-builder. Required for:
- `/menu.ipxe` dynamic menu generation
- Serving boot files via `/assets/*`

Structure created by builder:
```
assets/
└── {product}/
    └── {version}/
        ├── vmlinuz
        └── initrd
```

## Network Mode

### Host Network (recommended for TFTP)

```bash
--network host
```

Required when `BOOT_ENABLED=true` because TFTP uses UDP port 69.

Pros:
- Direct port access
- Simpler networking

Cons:
- Container shares host network stack
- Port conflicts possible

### Bridge Network (HTTP-only)

```bash
-p 8080:8080
```

Works when `BOOT_ENABLED=false` and you provide your own TFTP.

Pros:
- Network isolation
- Port mapping flexibility

Cons:
- Cannot run TFTP (UDP doesn't work with port mapping well)

## Example Configurations

### Minimal (TFTP + HTTP)

```bash
docker run -d --name pxe-pilot --network host \
  -v ./answers:/answers:ro \
  -v ./assets:/assets:ro \
  -e PXE_PILOT_BOOT_ENABLED=true \
  ghcr.io/wisherops/pxe-pilot-server:latest
```

### HTTP-only (with netboot.xyz)

```bash
docker run -d --name pxe-pilot \
  -p 8080:8080 \
  -v ./answers:/answers:ro \
  -v ./assets:/assets:ro \
  ghcr.io/wisherops/pxe-pilot-server:latest
```

### Behind reverse proxy

```bash
docker run -d --name pxe-pilot \
  -p 8080:8080 \
  -v ./answers:/answers:ro \
  -v ./assets:/assets:ro \
  -e PXE_PILOT_ASSET_URL=https://pxe.example.com/assets \
  -e PXE_PILOT_TRUSTED_PROXIES=172.16.0.0/12 \
  ghcr.io/wisherops/pxe-pilot-server:latest
```

### Debug mode

```bash
docker run -d --name pxe-pilot --network host \
  -v ./answers:/answers:ro \
  -v ./assets:/assets:ro \
  -e PXE_PILOT_LOG_LEVEL=debug \
  -e PXE_PILOT_BOOT_ENABLED=true \
  ghcr.io/wisherops/pxe-pilot-server:latest
```

Check logs:
```bash
docker logs -f pxe-pilot
```
