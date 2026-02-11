# Builder Guide

The pxe-pilot builder prepares Proxmox ISOs for PXE boot.

It downloads or uses a local ISO, runs Proxmox's auto-install-assistant to configure HTTP answer fetching, extracts the kernel and initrd, embeds the ISO in the initrd, and outputs versioned boot assets.

## Quick usage

```bash
docker run --rm --privileged \
  -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso-url https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso \
  --answer-url http://10.0.0.5:8080/answer
```

This creates `assets/proxmox-ve/9.1-1/vmlinuz` and `initrd`.

## Command-line options

### Required

You must provide **one** of these:

| Option | Description |
|--------|-------------|
| `--iso PATH` | Path to local ISO (inside container) |
| `--iso-url URL` | URL to download ISO |

And this:

| Option | Description |
|--------|-------------|
| `--answer-url URL` | URL where Proxmox installer will POST MACs |

### Optional

| Option | Default | Description |
|--------|---------|-------------|
| `--product NAME` | Auto-detected | `proxmox-ve`, `proxmox-bs`, `proxmox-mg` |
| `--version VER` | Auto-detected | Version string (e.g., `9.1-1`) |
| `--output DIR` | `/output` | Output directory inside container |
| `--zstd-level N` | `19` | Compression level 1-19 (higher = smaller, slower) |
| `--cert-fingerprint FP` | None | TLS cert fingerprint for HTTPS answer URLs |
| `--skip-verify` | false | Skip ISO SHA256 checksum verification |

## Output structure

```
/output/
└── {product}/
    └── {version}/
        ├── vmlinuz
        └── initrd
```

Example: `/output/proxmox-ve/9.1-1/vmlinuz`

Product and version auto-detect from ISO filename. Override with `--product` and `--version`.

## Examples

### Download ISO automatically

```bash
docker run --rm --privileged \
  -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso-url https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso \
  --answer-url http://10.0.0.5:8080/answer
```

### Use local ISO

```bash
docker run --rm --privileged \
  -v ./isos/proxmox-ve_9.1-1.iso:/isos/proxmox.iso:ro \
  -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso /isos/proxmox.iso \
  --answer-url http://10.0.0.5:8080/answer
```

### Build multiple versions

```bash
# PVE 9.1
docker run --rm --privileged -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso-url https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso \
  --answer-url http://10.0.0.5:8080/answer

# PVE 8.4
docker run --rm --privileged -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso-url https://enterprise.proxmox.com/iso/proxmox-ve_8.4-1.iso \
  --answer-url http://10.0.0.5:8080/answer

# Proxmox Backup Server
docker run --rm --privileged -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso-url https://enterprise.proxmox.com/iso/proxmox-backup-server_3.3-1.iso \
  --answer-url http://10.0.0.5:8080/answer
```

Result:
```
assets/
├── proxmox-ve/
│   ├── 8.4-1/
│   │   ├── vmlinuz
│   │   └── initrd
│   └── 9.1-1/
│       ├── vmlinuz
│       └── initrd
└── proxmox-bs/
    └── 3.3-1/
        ├── vmlinuz
        └── initrd
```

The server's `/menu.ipxe` endpoint auto-discovers all versions and generates the boot menu.

### HTTPS answer URL with self-signed cert

```bash
# Get certificate fingerprint
openssl x509 -in cert.pem -fingerprint -sha256 -noout | tr -d ":"

# Pass to builder
docker run --rm --privileged -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso-url https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso \
  --answer-url https://pxe.example.com/answer \
  --cert-fingerprint "8C3558AEF51C4EDE20442C1EBA447724EAC28C5050724E8E2BE56892F481E90A"
```

### Fast builds for testing

```bash
docker run --rm --privileged -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso-url https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso \
  --answer-url http://10.0.0.5:8080/answer \
  --zstd-level 3
```

Level 3 builds in ~30 seconds vs ~5 minutes at level 19. The initrd is larger but functionally identical.

## Why `--privileged`?

The builder mounts ISO files using loop devices (`mount -o loop`). Docker blocks loop device creation by default.

This is safe because the builder:
- Runs once and exits
- Has no network exposure
- Only processes files you provide
- Writes to a volume you mount

## Build process

1. **Fetch ISO** - Downloads from URL (if `--iso-url`) or uses local path
2. **Verify** - Checks SHA256 checksum (unless `--skip-verify`)
3. **Prepare** - Runs `proxmox-auto-install-assistant prepare-iso --fetch-from http`
4. **Extract** - Mounts prepared ISO, copies kernel as `vmlinuz`
5. **Repack initrd** - Decompresses initrd, embeds ISO as `/proxmox.iso`, recompresses at specified level
6. **Publish** - Places files in `/output/{product}/{version}/`

## Requirements

- Docker with loop device support (most Linux hosts)
- 8GB+ free disk space during build
- Target machines need 8GB+ RAM to load the ~1.5GB initrd during PXE boot

## Troubleshooting

**Error: "loop device not available"**
- Add `--privileged` flag
- Check host kernel has loop device support: `lsmod | grep loop`

**Build is very slow**
- Lower `--zstd-level` to 3-5 for testing
- Use level 19 for production

**Auto-detection picks wrong version**
- Override with `--version`
- ISO filename must match Proxmox naming: `proxmox-ve_X.Y-Z.iso`

**SHA256 verification fails**
- Check ISO isn't corrupted
- Use `--skip-verify` to bypass (not recommended)
