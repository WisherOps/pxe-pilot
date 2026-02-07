#Requires -RunAsAdministrator
<#
.SYNOPSIS
    pxe-pilot sandbox -- Windows / Hyper-V launcher.

.DESCRIPTION
    Manages the full sandbox lifecycle on Windows with Hyper-V:
      - Provisions the pxe-vm via Vagrant (Docker + pxe-pilot + dnsmasq)
      - Creates a blank Gen2 Hyper-V VM that PXE boots from the network

    Supports two network modes:
      bridged  -- VM joins your real LAN via an external switch.
                 dnsmasq runs proxy DHCP (safe, doesn't hand out IPs).
      isolated -- Uses a private Hyper-V switch (10.10.10.0/24).
                 dnsmasq runs full DHCP. Zero risk to your network.

.PARAMETER Action
    up      Start pxe-vm + create PXE demo VM
    down    Destroy both VMs and clean up
    status  Show current state of VMs and containers

.PARAMETER NetworkMode
    "bridged" (default) -- uses your external switch, proxy DHCP
    "isolated" -- creates a private switch, full DHCP

.PARAMETER SwitchName
    Hyper-V external switch name for bridged mode (default: External-LAN).
    Ignored in isolated mode -- a private switch is created automatically.

.PARAMETER DemoVmName
    Name of the PXE demo VM (default: pxe-pilot-demo)

.PARAMETER DemoVmMemoryMB
    RAM for the demo VM in MB (default: 2048).
    Use 8192 for real Proxmox installs.

.EXAMPLE
    .\start.ps1 -Action up
    .\start.ps1 -Action up -NetworkMode isolated
    .\start.ps1 -Action up -SwitchName "My External Switch"
    .\start.ps1 -Action up -DemoVmMemoryMB 8192
    .\start.ps1 -Action down
    .\start.ps1 -Action status
#>

param(
    [Parameter(Mandatory, Position = 0)]
    [ValidateSet("up", "down", "clean", "status")]
    [string]$Action,

    [ValidateSet("bridged", "isolated")]
    [string]$NetworkMode = "bridged",

    [string]$SwitchName = "External-LAN",
    [string]$DemoVmName = "pxe-pilot-demo",
    [int]$DemoVmMemoryMB = 2048
)

$ErrorActionPreference = "Stop"
$env:VAGRANT_PREFERRED_POWERSHELL = "powershell"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DemoDiskPath = Join-Path $ScriptDir "$DemoVmName.vhdx"
$PrivateSwitchName = "pxe-pilot-isolated"

function Write-Info { param([string]$Msg) Write-Host ">>> $Msg" -ForegroundColor Cyan }

# ── Resolve which Hyper-V switch to use ──

function Get-PxeSwitch {
    if ($NetworkMode -eq "isolated") {
        # Create private switch if it doesn't exist
        $sw = Get-VMSwitch -Name $PrivateSwitchName -ErrorAction SilentlyContinue
        if (-not $sw) {
            Write-Info "Creating Hyper-V private switch '$PrivateSwitchName'..."
            New-VMSwitch -Name $PrivateSwitchName -SwitchType Private | Out-Null
        }
        return $PrivateSwitchName
    }
    else {
        # Verify the external switch exists
        $sw = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
        if (-not $sw) {
            throw "Hyper-V switch '$SwitchName' not found. Create an External switch or use -NetworkMode isolated."
        }
        return $SwitchName
    }
}

# ── up ───────────────────────────────────────────────────────────

function Invoke-Up {
    # Prerequisites
    if (-not (Get-Command vagrant -ErrorAction SilentlyContinue)) {
        throw "Vagrant is required but not found in PATH."
    }
    if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
        throw "Hyper-V PowerShell module not available. Enable Hyper-V."
    }

    $targetSwitch = Get-PxeSwitch

    # Set environment for Vagrant + provisioner
    $env:PXE_MODE = $NetworkMode
    $env:PXE_HYPERV_SWITCH = $targetSwitch

    # Start pxe-vm via Vagrant
    Write-Info "Starting pxe-vm ($NetworkMode mode on switch '$targetSwitch')..."
    Push-Location $ScriptDir
    try {
        vagrant up pxe-vm --provider=hyperv
        if ($LASTEXITCODE -ne 0) {
            throw "Vagrant failed (exit code $LASTEXITCODE). Check output above."
        }
    }
    finally {
        Pop-Location
    }

    # Check if demo VM already exists
    $existing = Get-VM -Name $DemoVmName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Info "Demo VM '$DemoVmName' already exists -- starting it."
        if ($existing.State -ne "Running") {
            Start-VM -Name $DemoVmName
        }
        vmconnect.exe localhost $DemoVmName
        return
    }

    # Create demo VM -- Gen2 UEFI, PXE first boot, on the same switch
    Write-Info "Creating demo VM '$DemoVmName'..."

    $memoryBytes = [int64]$DemoVmMemoryMB * 1MB
    New-VHD -Path $DemoDiskPath -SizeBytes 20GB -Dynamic | Out-Null

    New-VM -Name $DemoVmName `
        -MemoryStartupBytes $memoryBytes `
        -Generation 2 `
        -VHDPath $DemoDiskPath `
        -SwitchName $targetSwitch | Out-Null

    Set-VM -Name $DemoVmName -ProcessorCount 2

    # Disable Secure Boot (required for iPXE)
    Set-VMFirmware -VMName $DemoVmName -EnableSecureBoot Off

    # Set boot order: network adapter first
    $nic = Get-VMNetworkAdapter -VMName $DemoVmName
    Set-VMFirmware -VMName $DemoVmName -FirstBootDevice $nic

    Write-Info "Starting demo VM (PXE boot)..."
    Start-VM -Name $DemoVmName
    vmconnect.exe localhost $DemoVmName

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  Demo VM started -- PXE booting now"         -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Mode:    $NetworkMode"
    Write-Host "  Switch:  $targetSwitch"
    Write-Host "  RAM:     $DemoVmMemoryMB MB"
    Write-Host ""
    Write-Host "  The VM will:"
    Write-Host "    1. Get DHCP lease + PXE boot info"
    Write-Host "    2. Download iPXE via TFTP from pxe-pilot"
    Write-Host "    3. iPXE loads the boot menu over HTTP"
    Write-Host "    4. Select a Proxmox version to install"
    Write-Host ""
    Write-Host "  SSH into pxe-vm:"
    Write-Host "    cd sandbox; vagrant ssh pxe-vm"
    Write-Host ""
    Write-Host "  Check health:"
    Write-Host "    vagrant ssh pxe-vm -c 'curl -s localhost:8080/health'"
    Write-Host "============================================" -ForegroundColor Green
}

# ── down ─────────────────────────────────────────────────────────

function Invoke-Down {
    # Remove demo VM
    $vm = Get-VM -Name $DemoVmName -ErrorAction SilentlyContinue
    if ($vm) {
        Write-Info "Stopping demo VM '$DemoVmName'..."
        if ($vm.State -eq "Running") {
            Stop-VM -Name $DemoVmName -Force -TurnOff
        }
        Write-Info "Removing demo VM '$DemoVmName'..."
        Remove-VM -Name $DemoVmName -Force
    }
    else {
        Write-Info "Demo VM '$DemoVmName' does not exist."
    }

    # Remove demo disk
    if (Test-Path $DemoDiskPath) {
        Remove-Item $DemoDiskPath -Force
    }

    # Destroy pxe-vm via Vagrant
    $vagrantDir = Join-Path $ScriptDir ".vagrant"
    if (Test-Path $vagrantDir) {
        Write-Info "Destroying pxe-vm..."
        Push-Location $ScriptDir
        try {
            vagrant destroy -f
        }
        finally {
            Pop-Location
        }
    }
    else {
        Write-Info "No Vagrant state found."
    }

    # Remove private switch if we created it
    $sw = Get-VMSwitch -Name $PrivateSwitchName -ErrorAction SilentlyContinue
    if ($sw -and $sw.SwitchType -eq "Private") {
        Write-Info "Removing private switch '$PrivateSwitchName'..."
        Remove-VMSwitch -Name $PrivateSwitchName -Force
    }

    Write-Host ">>> Sandbox cleaned up."
}

# ── clean ────────────────────────────────────────────────────────

function Invoke-Clean {
    Write-Info "Resetting sandbox -- keeping Vagrant box..."

    # Run down first to destroy VMs + switch
    try { Invoke-Down } catch { }

    # Remove Vagrant state directory
    $vagrantDir = Join-Path $ScriptDir ".vagrant"
    if (Test-Path $vagrantDir) {
        Write-Info "Removing .vagrant directory..."
        Remove-Item $vagrantDir -Recurse -Force
    }

    # Remove any leftover AVHDX differencing disks
    Get-ChildItem $ScriptDir -Filter "*.avhdx" -ErrorAction SilentlyContinue |
    ForEach-Object { Remove-Item $_.FullName -Force }

    Write-Host ""
    Write-Host ">>> Sandbox reset. Run '.\start.ps1 -Action up' to start fresh."
    Write-Host "    (Vagrant box cached -- next 'up' will skip the download)" -ForegroundColor DarkGray
}

# ── status ───────────────────────────────────────────────────────

function Invoke-Status {
    Write-Host "=== pxe-vm ===" -ForegroundColor Yellow
    Push-Location $ScriptDir
    try {
        vagrant status pxe-vm 2>$null
    }
    catch {
        Write-Host "  (no Vagrant state)"
    }
    Pop-Location
    Write-Host ""

    Write-Host "=== Demo VM ($DemoVmName) ===" -ForegroundColor Yellow
    $vm = Get-VM -Name $DemoVmName -ErrorAction SilentlyContinue
    if ($vm) {
        Write-Host "  State: $($vm.State)"
        Write-Host "  RAM:   $([math]::Round($vm.MemoryStartup / 1MB)) MB"
    }
    else {
        Write-Host "  Not created"
    }
    Write-Host ""

    Write-Host "=== Docker containers (via pxe-vm) ===" -ForegroundColor Yellow
    Push-Location $ScriptDir
    try {
        vagrant ssh pxe-vm -c "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" 2>$null
    }
    catch {
        Write-Host "  (cannot reach pxe-vm)"
    }
    Pop-Location
}

# ── main ─────────────────────────────────────────────────────────

switch ($Action) {
    "up" { Invoke-Up }
    "down" { Invoke-Down }
    "clean" { Invoke-Clean }
    "status" { Invoke-Status }
}
