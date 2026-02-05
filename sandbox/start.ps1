#Requires -RunAsAdministrator
<#
.SYNOPSIS
    PXE Boot Testing Sandbox -- Windows / Hyper-V launcher.

.DESCRIPTION
    Manages the full sandbox lifecycle on Windows with Hyper-V:
      - Provisions the netboot VM via Vagrant
      - Creates a blank Gen2 Hyper-V VM that PXE boots from the network

.PARAMETER Action
    up      Start netboot VM + create PXE demo VM
    down    Destroy both VMs
    clean   Full reset: destroy VMs, remove Vagrant state and cached boxes
    status  Show current state

.PARAMETER DhcpStart
    First IP in the DHCP range (default: 192.168.1.200)

.PARAMETER DhcpEnd
    Last IP in the DHCP range (default: 192.168.1.250)

.PARAMETER SwitchName
    Hyper-V external virtual switch name (default: External-LAN)

.PARAMETER DemoVmName
    Name of the PXE demo VM (default: pxe-sandbox-demo)

.EXAMPLE
    .\start.ps1 -Action up
    .\start.ps1 -Action down
    .\start.ps1 -Action up -DhcpStart 10.0.0.200 -DhcpEnd 10.0.0.250 -SwitchName "My Switch"
#>

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateSet("up", "down", "clean", "status")]
    [string]$Action,

    [string]$DhcpStart = "192.168.1.200",
    [string]$DhcpEnd   = "192.168.1.250",
    [string]$SwitchName = "External-LAN",
    [string]$DemoVmName = "pxe-sandbox-demo"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DemoDiskPath = Join-Path $ScriptDir "$DemoVmName.vhdx"

function Write-Info { param([string]$Message) Write-Host ">>> $Message" -ForegroundColor Cyan }

# ---------- up ----------

function Invoke-Up {
    # Verify prerequisites
    if (-not (Get-Command vagrant -ErrorAction SilentlyContinue)) {
        throw "Vagrant is required but not found in PATH."
    }
    if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
        throw "Hyper-V PowerShell module not available. Enable Hyper-V."
    }

    # Check virtual switch exists
    $switch = Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue
    if (-not $switch) {
        throw "Hyper-V virtual switch '$SwitchName' not found. Create an External switch first."
    }

    # Start netboot VM via Vagrant
    Write-Info "Starting netboot VM..."
    $env:PXE_DHCP_START = $DhcpStart
    $env:PXE_DHCP_END   = $DhcpEnd
    $env:PXE_HYPERV_SWITCH = $SwitchName
    Push-Location $ScriptDir
    try {
        vagrant up netboot --provider=hyperv
        if ($LASTEXITCODE -ne 0) {
            throw "Vagrant failed (exit code $LASTEXITCODE). Fix the issue above and retry."
        }
    } finally {
        Pop-Location
    }

    # Check if demo VM already exists
    $existingVm = Get-VM -Name $DemoVmName -ErrorAction SilentlyContinue
    if ($existingVm) {
        Write-Info "Demo VM '$DemoVmName' already exists -- starting it."
        if ($existingVm.State -ne "Running") {
            Start-VM -Name $DemoVmName
        }
        vmconnect.exe localhost $DemoVmName
        return
    }

    # Create demo VM
    Write-Info "Creating demo VM '$DemoVmName'..."

    # Create virtual disk
    New-VHD -Path $DemoDiskPath -SizeBytes 20GB -Dynamic | Out-Null

    # Create Gen 2 VM
    New-VM -Name $DemoVmName `
        -MemoryStartupBytes 5GB `
        -Generation 2 `
        -VHDPath $DemoDiskPath `
        -SwitchName $SwitchName | Out-Null

    # Configure VM
    Set-VM -Name $DemoVmName -ProcessorCount 2
    Set-VMFirmware -VMName $DemoVmName -EnableSecureBoot Off

    # Set boot order: network first
    $netAdapter = Get-VMNetworkAdapter -VMName $DemoVmName
    Set-VMFirmware -VMName $DemoVmName -FirstBootDevice $netAdapter

    Write-Info "Starting demo VM (PXE boot)..."
    Start-VM -Name $DemoVmName

    # Open console
    vmconnect.exe localhost $DemoVmName

    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  Demo VM started -- PXE booting now"         -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  The VM will:"
    Write-Host "    1. Request DHCP lease from dnsmasq"
    Write-Host "    2. Download netboot.xyz via TFTP"
    Write-Host "    3. Show the netboot.xyz boot menu"
    Write-Host ""
    Write-Host "  Select: Linux Network Installs > Proxmox"
    Write-Host "  The installer will fetch its answer file"
    Write-Host "  from pxe-pilot automatically."
    Write-Host "============================================" -ForegroundColor Green
}

# ---------- down ----------

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
    } else {
        Write-Info "Demo VM '$DemoVmName' does not exist."
    }

    # Remove demo disk
    if (Test-Path $DemoDiskPath) {
        Remove-Item $DemoDiskPath -Force
    }

    # Destroy netboot VM
    $vagrantDir = Join-Path $ScriptDir ".vagrant"
    if (Test-Path $vagrantDir) {
        Write-Info "Destroying netboot VM..."
        Push-Location $ScriptDir
        try {
            vagrant destroy -f
        } finally {
            Pop-Location
        }
    } else {
        Write-Info "No Vagrant state found."
    }

    Write-Host ">>> Sandbox cleaned up."
}

# ---------- clean ----------

function Invoke-Clean {
    Write-Info "Full sandbox reset..."

    # Run down first to destroy VMs
    try { Invoke-Down } catch { }

    # Remove Vagrant state
    $vagrantDir = Join-Path $ScriptDir ".vagrant"
    if (Test-Path $vagrantDir) {
        Write-Info "Removing .vagrant directory..."
        Remove-Item $vagrantDir -Recurse -Force
    }

    # Remove cached box
    Write-Info "Removing cached Vagrant box (if any)..."
    Push-Location $ScriptDir
    try {
        vagrant box remove generic/ubuntu2204 --all --force 2>$null
    } catch { }
    Pop-Location

    Write-Host ""
    Write-Host ">>> Sandbox fully reset. Run '.\start.ps1 -Action up' to start fresh."
}

# ---------- status ----------

function Invoke-Status {
    Write-Host "=== Netboot VM ===" -ForegroundColor Yellow
    Push-Location $ScriptDir
    try {
        vagrant status netboot 2>$null
    } catch {
        Write-Host "  (no Vagrant state)"
    }
    Pop-Location
    Write-Host ""

    Write-Host "=== Demo VM ($DemoVmName) ===" -ForegroundColor Yellow
    $vm = Get-VM -Name $DemoVmName -ErrorAction SilentlyContinue
    if ($vm) {
        Write-Host "  State: $($vm.State)"
    } else {
        Write-Host "  Not created"
    }
    Write-Host ""

    Write-Host "=== Docker containers (via netboot VM) ===" -ForegroundColor Yellow
    Push-Location $ScriptDir
    try {
        vagrant ssh netboot -c "docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'" 2>$null
    } catch {
        Write-Host "  (cannot reach netboot VM)"
    }
    Pop-Location
}

# ---------- main ----------

switch ($Action) {
    "up"     { Invoke-Up }
    "down"   { Invoke-Down }
    "clean"  { Invoke-Clean }
    "status" { Invoke-Status }
}
