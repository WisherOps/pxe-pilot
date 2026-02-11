# Answer Files

Answer files tell Proxmox how to install itself. pxe-pilot serves TOML files based on MAC address.

## How it works

1. Proxmox installer POSTs its network interfaces to `/answer`
2. pxe-pilot extracts MAC addresses from the request
3. Checks `answers/hosts/{mac}.toml` for each MAC (first match wins)
4. No match → return `answers/default.toml`
5. No default → return HTTP 404

No merging. No validation. Simple file lookup.

## File structure

```
answers/
├── default.toml               # Fallback config
└── hosts/
    ├── aa-bb-cc-dd-ee-ff.toml  # Host-specific
    ├── 00-11-22-33-44-55.toml  # Another host
    └── de-ad-be-ef-ca-fe.toml  # Another host
```

## MAC address format

pxe-pilot normalizes all MACs to lowercase with dashes: `aa-bb-cc-dd-ee-ff`

Input formats recognized:
- `AA:BB:CC:DD:EE:FF` → `aa-bb-cc-dd-ee-ff`
- `AA-BB-CC-DD-EE-FF` → `aa-bb-cc-dd-ee-ff`
- `aabbccddeeff` → `aa-bb-cc-dd-ee-ff`

## Answer file format

TOML, following Proxmox's answer file specification.

Minimum working example:

```toml
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
```

## Common configurations

### Static IP

```toml
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
```

### ZFS RAID1

```toml
[global]
keyboard = "en-us"
country = "us"
fqdn = "pve-storage.local"
mailto = "admin@example.com"
timezone = "America/Los_Angeles"
root-password = "changeme"

[network]
source = "from-dhcp"

[disk-setup]
filesystem = "zfs"
zfs.raid = "raid1"
disk_list = ["sda", "sdb"]
```

### ext4 with custom disk

```toml
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
disk_list = ["nvme0n1"]
```

## Managing answer files

### Add a new host

```bash
# Copy default as template
cp answers/default.toml answers/hosts/aa-bb-cc-dd-ee-ff.toml

# Edit with host-specific settings
vim answers/hosts/aa-bb-cc-dd-ee-ff.toml
```

No restart needed. pxe-pilot reads files on each request.

### Remove a host config

```bash
rm answers/hosts/aa-bb-cc-dd-ee-ff.toml
```

Host falls back to `default.toml` on next boot.

### View what a host would receive

```bash
curl http://10.0.0.5:8080/hosts/aa-bb-cc-dd-ee-ff
```

Returns the TOML that MAC would get, or 404 if no config exists.

### List all configured hosts

```bash
curl http://10.0.0.5:8080/hosts
```

Returns JSON:
```json
{
  "default_exists": true,
  "host_count": 3,
  "hosts": [
    "aa-bb-cc-dd-ee-ff",
    "00-11-22-33-44-55",
    "de-ad-be-ef-ca-fe"
  ]
}
```

## Best practices

**Use `default.toml` for:**
- Uniform configs across nodes
- Testing (PXE boot unknown MACs to try configs)

**Use host-specific files for:**
- Different hostnames
- Different IP addresses
- Different disk layouts
- Different ZFS RAID levels

**Testing configs:**
1. Create `answers/test.toml` with your config
2. Copy it to `default.toml`: `cp answers/test.toml answers/default.toml`
3. PXE boot a machine
4. If it works, create host-specific files
5. If it fails, check Proxmox console for errors

**Security:**
- Mount answers volume read-only: `-v ./answers:/answers:ro`
- Use strong root passwords
- Change passwords after first boot
- Consider storing answers outside the container and mounting only during installs

## Proxmox answer file reference

Full specification: [Proxmox VE Automated Installation](https://pve.proxmox.com/pve-docs/pve-admin-guide.html#chapter_installation)

Key sections:
- `[global]` - Keyboard, locale, timezone, credentials
- `[network]` - DHCP or static IP configuration
- `[disk-setup]` - Filesystem type, RAID, disk selection

pxe-pilot doesn't validate TOML content. Proxmox installer validates during install. Invalid configs result in install failure shown on the console.

## Troubleshooting

**Machine gets 404 from /answer:**
- Check MAC address: Boot machine, note MAC from BIOS
- Normalize it: `aa-bb-cc-dd-ee-ff` format
- Verify file exists: `ls answers/hosts/aa-bb-cc-dd-ee-ff.toml`
- Or create `default.toml`: `cp examples/default.toml answers/default.toml`

**Installer boots but fails:**
- TOML syntax error (check with TOML validator)
- Invalid Proxmox configuration (check console for specific error)
- Disk doesn't exist (`disk_list` references non-existent disk)
- Network config invalid (bad CIDR, unreachable gateway)

**Want to see what's happening:**
```bash
docker logs -f pxe-pilot
```

You'll see MAC addresses from each request and which file was served.
