# HTTP-only Deployment

Use pxe-pilot as an HTTP answer file server while providing your own TFTP/PXE infrastructure.

## When to use this

- You have existing PXE/TFTP infrastructure you want to keep
- You use a dedicated TFTP server (not netboot.xyz)
- You want maximum control over the boot process
- You need integration with existing automation

## Architecture

```
Machine boots
  ↓
Your DHCP server points to your TFTP server
  ↓
Your TFTP server serves your iPXE binary
  ↓
Your iPXE scripts chain to pxe-pilot menu
  ↓
User selects Proxmox version
  ↓
Proxmox installer boots, POSTs MACs to pxe-pilot
  ↓
pxe-pilot returns TOML answer file
  ↓
Proxmox installs automatically
```

pxe-pilot provides HTTP endpoints only. You control everything else.

## Prerequisites

- Working TFTP server (tftpd-hpa, dnsmasq, atftpd, etc.)
- iPXE binaries on your TFTP server
- Docker for pxe-pilot
- Ability to edit iPXE scripts

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

## Step 3: Start pxe-pilot

```bash
docker run -d \
  --name pxe-pilot \
  -p 8080:8080 \
  -v ./answers:/answers:ro \
  -v ./assets:/assets:ro \
  ghcr.io/wisherops/pxe-pilot-server:latest
```

**HTTP only**: No TFTP. Use port mapping, not host networking.

Verify:
```bash
curl http://localhost:8080/health
curl http://localhost:8080/menu.ipxe
```

## Step 4: Configure your TFTP server

Point DHCP to your existing TFTP server (not pxe-pilot). This part doesn't change.

Example for tftpd-hpa:
```bash
# /etc/default/tftpd-hpa
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/var/lib/tftpboot"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure"
```

Example for dnsmasq:
```bash
# /etc/dnsmasq.conf
enable-tftp
tftp-root=/var/lib/tftpboot
dhcp-boot=undionly.kpxe
```

## Step 5: Create iPXE menu script

On your TFTP server, create a menu that chains to pxe-pilot.

### Simple chain

`/var/lib/tftpboot/boot.ipxe`:
```ipxe
#!ipxe
# Direct chain to pxe-pilot
chain http://10.0.0.5:8080/menu.ipxe
```

### Custom menu with options

`/var/lib/tftpboot/menu.ipxe`:
```ipxe
#!ipxe

:main
menu PXE Boot Menu
item --gap Operating Systems
item ubuntu Ubuntu Server
item debian Debian
item proxmox Proxmox VE (pxe-pilot)
item --gap
item shell iPXE Shell
item exit Exit to BIOS
choose --default proxmox --timeout 10000 option && goto ${option}

:ubuntu
chain http://archive.ubuntu.com/ubuntu/dists/jammy/main/installer-amd64/current/legacy-images/netboot/ubuntu-installer/amd64/boot-screens/menu.cfg
goto main

:debian
chain http://ftp.debian.org/debian/dists/stable/main/installer-amd64/current/images/netboot/debian-installer/amd64/boot-screens/menu.cfg
goto main

:proxmox
chain http://10.0.0.5:8080/menu.ipxe
goto main

:shell
shell

:exit
exit
```

### Conditional chain

Only show Proxmox if pxe-pilot is reachable:

```ipxe
#!ipxe

# Test if pxe-pilot is available
chain --timeout 3000 http://10.0.0.5:8080/health && set pxe_pilot_ok 1 || set pxe_pilot_ok 0

:main
menu PXE Boot Menu
item --gap Proxmox VE
iseq ${pxe_pilot_ok} 1 && item proxmox Proxmox VE Automated Install || item proxmox_down Proxmox VE (unavailable)
choose option && goto ${option}

:proxmox
chain http://10.0.0.5:8080/menu.ipxe || goto main

:proxmox_down
echo pxe-pilot is not responding
sleep 3
goto main
```

## TFTP server examples

### tftpd-hpa (Debian/Ubuntu)

Install:
```bash
apt install tftpd-hpa
```

Configure `/etc/default/tftpd-hpa`:
```bash
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/var/lib/tftpboot"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure"
```

Add iPXE binaries:
```bash
cd /var/lib/tftpboot
wget http://boot.ipxe.org/undionly.kpxe
wget http://boot.ipxe.org/ipxe.efi
```

Create menu:
```bash
cat > /var/lib/tftpboot/boot.ipxe << 'EOF'
#!ipxe
chain http://10.0.0.5:8080/menu.ipxe
EOF
```

Restart:
```bash
systemctl restart tftpd-hpa
```

### dnsmasq

Install:
```bash
apt install dnsmasq
```

Configure `/etc/dnsmasq.conf`:
```
enable-tftp
tftp-root=/var/lib/tftpboot
dhcp-boot=undionly.kpxe

# UEFI support
dhcp-match=set:efi-x86_64,option:client-arch,7
dhcp-boot=tag:efi-x86_64,ipxe.efi
```

Add iPXE binaries and menu (same as tftpd-hpa above).

Restart:
```bash
systemctl restart dnsmasq
```

### atftpd (alternative)

Install:
```bash
apt install atftpd
```

Configure during install or edit `/etc/default/atftpd`:
```bash
USE_INETD=false
OPTIONS="--tftpd-timeout 300 --retry-timeout 5 --maxthread 100 --verbose=5 /srv/tftp"
```

Add iPXE binaries:
```bash
cd /srv/tftp
wget http://boot.ipxe.org/undionly.kpxe
wget http://boot.ipxe.org/ipxe.efi
```

Create menu:
```bash
cat > /srv/tftp/boot.ipxe << 'EOF'
#!ipxe
chain http://10.0.0.5:8080/menu.ipxe
EOF
```

Restart:
```bash
systemctl restart atftpd
```

## Integration patterns

### Ansible automation

Trigger installs programmatically:

```yaml
- name: Deploy Proxmox cluster
  hosts: localhost
  tasks:
    - name: Create host-specific answer files
      template:
        src: answer.toml.j2
        dest: "/answers/hosts/{{ item.mac }}.toml"
      loop: "{{ proxmox_nodes }}"

    - name: Wake machines via WOL
      wakeonlan:
        mac: "{{ item.mac }}"
      loop: "{{ proxmox_nodes }}"

    - name: Wait for installations
      uri:
        url: "http://10.0.0.5:8080/hosts/{{ item.mac }}"
        method: GET
      register: result
      until: result.status == 200
      retries: 3
      delay: 5
      loop: "{{ proxmox_nodes }}"
```

### Terraform integration

Manage answer files as code:

```hcl
resource "local_file" "proxmox_answer" {
  for_each = var.proxmox_nodes

  filename = "${path.module}/answers/hosts/${replace(each.value.mac, ":", "-")}.toml"
  content = templatefile("${path.module}/templates/answer.toml.tpl", {
    fqdn     = each.value.fqdn
    ip       = each.value.ip
    gateway  = each.value.gateway
    dns      = var.dns_servers
  })
}
```

### API-driven deployment

Use pxe-pilot's endpoints in scripts:

```bash
#!/bin/bash
# Deploy Proxmox node

MAC="aa-bb-cc-dd-ee-ff"
FQDN="pve01.example.com"
IP="10.0.0.10/24"

# Generate answer file
cat > "answers/hosts/${MAC}.toml" << EOF
[global]
fqdn = "${FQDN}"
...
[network]
source = "from-answer"
cidr = "${IP}"
...
EOF

# Verify configuration
curl -f "http://10.0.0.5:8080/hosts/${MAC}" || {
  echo "Answer file not found"
  exit 1
}

# Wake machine (requires wakeonlan tool)
wakeonlan "${MAC//-/:}"

# Wait for installation
echo "Waiting for ${FQDN} to install..."
until ssh -o ConnectTimeout=5 root@10.0.0.10 exit 2>/dev/null; do
  sleep 30
done

echo "Installation complete"
```

## Serving assets separately

For large deployments, serve boot assets from a CDN or separate HTTP server.

### Option 1: nginx for assets

Run nginx to serve assets:
```nginx
server {
    listen 80;
    server_name assets.example.com;

    location /assets/ {
        alias /var/www/assets/;
        autoindex off;
    }
}
```

Configure pxe-pilot:
```bash
docker run -d --name pxe-pilot \
  -p 8080:8080 \
  -v ./answers:/answers:ro \
  -e PXE_PILOT_ASSET_URL=http://assets.example.com \
  ghcr.io/wisherops/pxe-pilot-server:latest
```

Copy assets to nginx:
```bash
rsync -av assets/ /var/www/assets/
```

### Option 2: Object storage (S3, MinIO)

Upload assets to S3:
```bash
aws s3 sync assets/ s3://my-bucket/pxe-assets/
```

Make public or use CDN:
```bash
aws s3api put-bucket-acl --bucket my-bucket --acl public-read
```

Configure pxe-pilot:
```bash
docker run -d --name pxe-pilot \
  -p 8080:8080 \
  -v ./answers:/answers:ro \
  -e PXE_PILOT_ASSET_URL=https://my-bucket.s3.amazonaws.com/pxe-assets \
  ghcr.io/wisherops/pxe-pilot-server:latest
```

## High availability

### Load-balanced pxe-pilot

Run multiple instances behind haproxy:

```
backend pxe_pilot
    balance roundrobin
    server pxe1 10.0.0.5:8080 check
    server pxe2 10.0.0.6:8080 check
    server pxe3 10.0.0.7:8080 check
```

Share answer files via NFS:
```bash
# On each pxe-pilot host
docker run -d --name pxe-pilot \
  -p 8080:8080 \
  -v /mnt/nfs/answers:/answers:ro \
  -v /mnt/nfs/assets:/assets:ro \
  ghcr.io/wisherops/pxe-pilot-server:latest
```

### Redundant TFTP

Run multiple TFTP servers with DNS round-robin:
```
# DHCP option 66
next-server pxe.example.com

# DNS
pxe.example.com. IN A 10.0.0.5
pxe.example.com. IN A 10.0.0.6
```

## Troubleshooting

### TFTP works but pxe-pilot unreachable

Check network routing from TFTP server to pxe-pilot:
```bash
ping 10.0.0.5
curl http://10.0.0.5:8080/health
```

Check firewall on pxe-pilot host:
```bash
iptables -L -n | grep 8080
```

### iPXE chain fails

Check iPXE script syntax:
```bash
# Test script locally
ipxe-validate boot.ipxe
```

Check pxe-pilot logs:
```bash
docker logs pxe-pilot
```

Test chain manually from iPXE shell:
```
iPXE> dhcp
iPXE> chain http://10.0.0.5:8080/menu.ipxe
```

### Machines get wrong answer file

Check MAC address format:
```bash
# Machines send: AA:BB:CC:DD:EE:FF
# pxe-pilot expects: aa-bb-cc-dd-ee-ff
curl http://10.0.0.5:8080/hosts/aa-bb-cc-dd-ee-ff
```

Check docker logs to see what MAC was sent:
```bash
docker logs pxe-pilot | grep "MAC"
```

## Benefits of HTTP-only mode

**Maximum flexibility**: Use any TFTP server, any iPXE setup

**Separation of concerns**: Boot infrastructure separate from answer serving

**Easy integration**: Fits into existing automation

**No privileged container**: pxe-pilot doesn't need host networking or elevated privileges

**Cloud-friendly**: Run pxe-pilot anywhere with HTTP access

## Alternatives

**Want simpler setup?**
- See [Bare-bones deployment](bare-bones.md) for all-in-one pxe-pilot

**Want netboot.xyz integration?**
- See [With netboot.xyz](with-netboot.md) for unified boot menu

**Want to migrate to simpler deployment later?**
- Enable `BOOT_ENABLED=true` and point DHCP to pxe-pilot
- No answer file changes needed
