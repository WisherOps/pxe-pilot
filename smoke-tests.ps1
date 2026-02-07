#!/usr/bin/env pwsh
<#
.SYNOPSIS
    pxe-pilot smoke test runbook.

.DESCRIPTION
    Manual spot-checks organized into collapsible regions.
    Run the whole file, or highlight a region in VS Code / ISE and press F8.

    Prerequisites:
      - Docker running
      - Image built:  docker build -t pxe-pilot:local ./server

.NOTES
    Temp assets are created in .smoke-test-assets/ (gitignored).
    Container name: pxe-pilot-smoke
#>

$here = if ($PSScriptRoot) { $PSScriptRoot } else { Get-Location }

$Port = 8080
$Image = "pxe-pilot:local"
$Container = "pxe-pilot-smoke"
$Base = "http://localhost:$Port"
$Answers = Join-Path $here "examples" "answers"
$Assets = Join-Path $here ".smoke-test-assets"

#region Setup — Build image & create fake assets
Write-Host "`n>>> Setup <<<" -ForegroundColor Cyan

# Build image
docker build -t $Image ./server

# Create fake PXE assets
New-Item -ItemType Directory -Path (Join-Path $Assets "proxmox-ve" "9.1-1") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Assets "proxmox-ve" "8.4-1") -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $Assets "proxmox-bs" "3.3-1") -Force | Out-Null
Set-Content (Join-Path $Assets "proxmox-ve" "9.1-1" "vmlinuz") "fake-kernel-9.1"
Set-Content (Join-Path $Assets "proxmox-ve" "9.1-1" "initrd")  "fake-initrd-9.1"
Set-Content (Join-Path $Assets "proxmox-ve" "8.4-1" "vmlinuz") "fake-kernel-8.4"
Set-Content (Join-Path $Assets "proxmox-ve" "8.4-1" "initrd")  "fake-initrd-8.4"
Set-Content (Join-Path $Assets "proxmox-bs" "3.3-1" "vmlinuz") "fake-kernel-bs"
Set-Content (Join-Path $Assets "proxmox-bs" "3.3-1" "initrd")  "fake-initrd-bs"

# Incomplete version (should be skipped by menu)
New-Item -ItemType Directory -Path (Join-Path $Assets "proxmox-ve" "7.0-1") -Force | Out-Null
Set-Content (Join-Path $Assets "proxmox-ve" "7.0-1" "vmlinuz") "kernel-only"

Write-Host "Done. Fake assets in $Assets" -ForegroundColor Green
#endregion

#region Start — Run container (boot disabled)
Write-Host "`n>>> Start container (boot disabled) <<<" -ForegroundColor Cyan

docker rm -f $Container 2>$null | Out-Null

docker run -d --rm `
  --name $Container `
  -p "${Port}:8080" `
  -v "${Answers}:/answers:ro" `
  -v "${Assets}:/assets:ro" `
  $Image

Write-Host "Waiting for server..." -NoNewline
$timeout = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $timeout) {
  try { $null = Invoke-RestMethod "$Base/health" -ErrorAction Stop; break }
  catch { Start-Sleep -Milliseconds 500 }
}
Write-Host " Ready." -ForegroundColor Green
#endregion

#region Health — GET /health
Write-Host "`n>>> Health <<<" -ForegroundColor Cyan

Write-Host "`n-- GET /health"
Invoke-RestMethod "$Base/health" | ConvertTo-Json

# Expect: status=ok, boot_enabled=false, default_exists=true, host_count=1
#endregion

#region Answer — POST /answer (known MAC, unknown MAC, edge cases)
Write-Host "`n>>> Answer Lookup <<<" -ForegroundColor Cyan

Write-Host "`n-- Known MAC → host-specific config"
Invoke-RestMethod -Method POST "$Base/answer" `
  -ContentType "application/json" `
  -Body '{"network_interfaces": [{"mac": "aa:bb:cc:dd:ee:ff"}]}'
# Expect: America/New_York, hostname, zfs

Write-Host "`n-- Unknown MAC → default config"
Invoke-RestMethod -Method POST "$Base/answer" `
  -ContentType "application/json" `
  -Body '{"network_interfaces": [{"mac": "11:22:33:44:55:66"}]}'
# Expect: UTC, from-dhcp, ext4

Write-Host "`n-- Multiple MACs, second one matches"
Invoke-RestMethod -Method POST "$Base/answer" `
  -ContentType "application/json" `
  -Body '{"network_interfaces": [{"mac": "11:11:11:11:11:11"}, {"mac": "aa:bb:cc:dd:ee:ff"}]}'
# Expect: host-specific (America/New_York)

Write-Host "`n-- Empty MACs → 400"
try {
  Invoke-RestMethod -Method POST "$Base/answer" `
    -ContentType "application/json" `
    -Body '{"network_interfaces": []}'
}
catch { Write-Host "Status: $($_.Exception.Response.StatusCode.value__) (expected 400)" -ForegroundColor Yellow }

Write-Host "`n-- Bad JSON → 400"
try {
  Invoke-RestMethod -Method POST "$Base/answer" `
    -ContentType "application/json" `
    -Body 'not-json'
}
catch { Write-Host "Status: $($_.Exception.Response.StatusCode.value__) (expected 400)" -ForegroundColor Yellow }
#endregion

#region Hosts — GET /hosts, GET /hosts/{mac}
Write-Host "`n>>> Host Inspection <<<" -ForegroundColor Cyan

Write-Host "`n-- GET /hosts"
Invoke-RestMethod "$Base/hosts" | ConvertTo-Json
# Expect: hosts list with aa-bb-cc-dd-ee-ff, default_exists=true

Write-Host "`n-- GET /hosts/{mac} — known host (colon format)"
Invoke-RestMethod "$Base/hosts/aa:bb:cc:dd:ee:ff"
# Expect: host-specific TOML, X-PXE-Pilot-Source: host

Write-Host "`n-- GET /hosts/{mac} — known host (dash format)"
Invoke-RestMethod "$Base/hosts/aa-bb-cc-dd-ee-ff"
# Expect: same host-specific TOML

Write-Host "`n-- GET /hosts/{mac} — uppercase MAC"
Invoke-RestMethod "$Base/hosts/AA:BB:CC:DD:EE:FF"
# Expect: same host-specific TOML

Write-Host "`n-- GET /hosts/{mac} — unknown host (falls back to default)"
Invoke-RestMethod "$Base/hosts/ff-ff-ff-ff-ff-ff"
# Expect: default TOML

Write-Host "`n-- GET /hosts/{mac} — check headers"
$resp = Invoke-WebRequest "$Base/hosts/aa:bb:cc:dd:ee:ff" -UseBasicParsing
Write-Host "Content-Type: $($resp.Headers['Content-Type'])"
Write-Host "X-PXE-Pilot-Source: $($resp.Headers['X-PXE-Pilot-Source'])"
# Expect: text/plain; charset=utf-8, source=host
#endregion

#region Menu — GET /boot.ipxe, GET /menu.ipxe
Write-Host "`n>>> iPXE Menu <<<" -ForegroundColor Cyan

Write-Host "`n-- GET /boot.ipxe (bootstrap chain)"
Invoke-RestMethod "$Base/boot.ipxe"
# Expect: #!ipxe, chain /menu.ipxe

Write-Host "`n-- GET /menu.ipxe (dynamic menu)"
Invoke-RestMethod "$Base/menu.ipxe"
# Expect:
#   - Proxmox VE 9.1-1 (listed first — newest)
#   - Proxmox VE 8.4-1
#   - Proxmox BS 3.3-1
#   - NOT 7.0-1 (incomplete — missing initrd)
#   - kernel/initrd URLs point to /assets/...
#   - proxmox-start-auto-installer in kernel args
#endregion

#region Assets — Static file serving
Write-Host "`n>>> Static Assets <<<" -ForegroundColor Cyan

Write-Host "`n-- GET /assets/proxmox-ve/9.1-1/vmlinuz"
Invoke-RestMethod "$Base/assets/proxmox-ve/9.1-1/vmlinuz"
# Expect: fake-kernel-9.1

Write-Host "`n-- GET /assets/proxmox-bs/3.3-1/initrd"
Invoke-RestMethod "$Base/assets/proxmox-bs/3.3-1/initrd"
# Expect: fake-initrd-bs

Write-Host "`n-- GET /assets/nonexistent → 404"
try {
  Invoke-RestMethod "$Base/assets/proxmox-ve/99.9-9/vmlinuz"
}
catch { Write-Host "Status: $($_.Exception.Response.StatusCode.value__) (expected 404)" -ForegroundColor Yellow }
#endregion

#region Boot — Restart with BOOT_ENABLED=true, check TFTP
Write-Host "`n>>> Boot Mode (TFTP) <<<" -ForegroundColor Cyan

docker rm -f $Container 2>$null | Out-Null

docker run -d --rm `
  --name $Container `
  -p "${Port}:8080" `
  -p "69:69/udp" `
  -v "${Answers}:/answers:ro" `
  -v "${Assets}:/assets:ro" `
  -e "PXE_PILOT_BOOT_ENABLED=true" `
  $Image

Write-Host "Waiting for server..." -NoNewline
$timeout = (Get-Date).AddSeconds(15)
while ((Get-Date) -lt $timeout) {
  try { $null = Invoke-RestMethod "$Base/health" -ErrorAction Stop; break }
  catch { Start-Sleep -Milliseconds 500 }
}
Write-Host " Ready." -ForegroundColor Green

Write-Host "`n-- GET /health (boot enabled)"
Invoke-RestMethod "$Base/health" | ConvertTo-Json
# Expect: boot_enabled=true

Write-Host "`n-- TFTP test (requires tftp client)"
Write-Host "   Run manually:  tftp -i localhost GET undionly.kpxe" -ForegroundColor DarkGray
Write-Host "   Then:          ls -la undionly.kpxe  (should be >60KB)" -ForegroundColor DarkGray

Write-Host "`n-- Verify TFTP is listening"
docker exec $Container netstat -ulnp | Select-String "69"
# Expect: udp 0.0.0.0:69

Write-Host "`n-- Verify iPXE binaries exist"
docker exec $Container ls -la /app/ipxe/
# Expect: undionly.kpxe (~70KB) and ipxe.efi (~1MB)

Write-Host "`n-- All other endpoints still work in boot mode"
Invoke-RestMethod "$Base/health" | Select-Object status, boot_enabled
Invoke-RestMethod "$Base/menu.ipxe" | Select-String "Proxmox"
#endregion

#region Logs — View container logs
Write-Host "`n>>> Container Logs <<<" -ForegroundColor Cyan
docker logs $Container --tail 30
#endregion

#region Cleanup — Stop container and remove temp assets
Write-Host "`n>>> Cleanup <<<" -ForegroundColor Cyan

docker rm -f $Container 2>$null | Out-Null
Remove-Item -Recurse -Force $Assets -ErrorAction SilentlyContinue

Write-Host "Container stopped. Temp assets removed." -ForegroundColor Green
#endregionS
