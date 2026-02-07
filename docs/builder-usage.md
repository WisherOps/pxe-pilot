# Builder Usage

The pxe-pilot builder takes a Proxmox ISO and produces PXE boot assets
(vmlinuz + initrd) configured to fetch answer files from your pxe-pilot server.

## Prerequisites

- Docker
- A Proxmox ISO (downloaded or available via URL)
- A running pxe-pilot server (or know the URL it will be at)

## Quick Start
```bash
# Create output directory
mkdir -p assets

# Build from a local ISO
docker run --rm --privileged \
  -v /path/to/proxmox-ve_9.1-1.iso:/isos/proxmox-ve_9.1-1.iso:ro \
  -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso /isos/proxmox-ve_9.1-1.iso \
  --answer-url http://10.0.0.5:8080/answer

# Or download the ISO automatically
docker run --rm --privileged \
  -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso-url https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso \
  --answer-url http://10.0.0.5:8080/answer
```

## Output
```
assets/
└── proxmox-ve/
    └── 9.1-1/
        ├── vmlinuz    # ~11MB kernel
        └── initrd     # ~1.5GB initrd with embedded ISO
```

The output is versioned by product and version, auto-detected from the ISO filename.
Run the builder multiple times to support multiple versions side by side.

## Options

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `--iso PATH` | One of --iso or --iso-url | | Path to local ISO inside container |
| `--iso-url URL` | One of --iso or --iso-url | | URL to download ISO |
| `--answer-url URL` | Yes | | URL the Proxmox installer will POST to |
| `--product NAME` | No | Auto-detected | `proxmox-ve`, `proxmox-bs`, `proxmox-mg` |
| `--version VERSION` | No | Auto-detected | Version string, e.g. `9.1-1` |
| `--output DIR` | No | `/output` | Output directory inside container |
| `--zstd-level N` | No | `19` | Compression level 1-19 |
| `--cert-fingerprint FP` | No | | TLS cert fingerprint for HTTPS answer URLs |
| `--skip-verify` | No | | Skip ISO SHA256 checksum verification |

## Why --privileged?

The builder uses `mount -o loop` to mount the ISO inside the container.
Docker blocks loop device creation by default. `--privileged` grants the
necessary kernel access.

This is safe because the builder is a run-once CLI tool — it processes the
ISO, writes output, and exits. There is no network exposure.

## Multiple Versions
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

## HTTPS Answer URLs

If your pxe-pilot server is behind HTTPS with a self-signed certificate,
provide the certificate fingerprint:
```bash
# Get your cert fingerprint
openssl x509 -in cert.pem -fingerprint -sha256 -noout | tr -d ":"

# Pass it to the builder
docker run --rm --privileged -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso-url https://enterprise.proxmox.com/iso/proxmox-ve_9.1-1.iso \
  --answer-url https://pxe.example.com/answer \
  --cert-fingerprint "8C3558AEF51C4EDE20442C1EBA447724EAC28C5050724E8E2BE56892F481E90A"
```

## Faster Builds

The default zstd compression level is 19 (maximum). For faster builds
during testing, lower it:
```bash
docker run --rm --privileged -v ./assets:/output \
  ghcr.io/wisherops/pxe-pilot-builder:latest \
  --iso /isos/proxmox-ve_9.1-1.iso \
  --answer-url http://10.0.0.5:8080/answer \
  --zstd-level 3
```

Level 3 builds in ~30 seconds vs ~5 minutes at level 19. The initrd will
be larger but functionally identical.

## Memory Requirements

The target machine booting these assets needs **8GB+ RAM** to load the
~1.5GB initrd into memory during PXE boot.
