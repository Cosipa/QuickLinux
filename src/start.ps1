# Linux Installer for Windows 11 UEFI Systems - Enhanced Edition with Auto-Restart
# PowerShell GUI Version - Fixed unit conversions for proper partition placement
# Run as Administrator: powershell -ExecutionPolicy Bypass -File linux_installer.ps1
# Distributions: Linux Mint 22.3 "Zena" (Cinnamon Edition), CachyOS Desktop, Ubuntu 24.04.4 LTS, Kubuntu 24.04.4 LTS, Debian Live 13.3.0 KDE, Fedora 43 KDE
# Optional rEFInd boot manager on a dedicated FAT32 partition with ext4 driver
# Optional ext4 boot partition (12 GB) via WSL instead of FAT32 (7 GB) - requires WSL + rEFInd

#Requires -Version 5.1

# ─── Auto-elevate to Administrator ────────────────────────────────────────────
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        Start-Process powershell.exe -ArgumentList @(
            "-ExecutionPolicy", "Bypass",
            "-File", "`"$PSCommandPath`""
        ) -Verb RunAs
    } catch {
        Write-Host "ERROR: Administrator privileges are required to run QuickLinux." -ForegroundColor Red
        Write-Host "Please right-click the script and select 'Run as Administrator'."
        Read-Host "Press Enter to exit"
    }
    exit
}
# Add required assemblies
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
# Global variables
$script:MinPartitionSizeGB = 7
$script:MinLinuxSizeGB = 20
$script:RefindUrl = "https://sourceforge.net/projects/refind/files/0.14.2/refind-bin-0.14.2.zip/download"
$script:RefindFilename = "refind-bin-0.14.2.zip"
$script:RefindSizeMB = 100  # 100 MB FAT32 partition for rEFInd
$script:RefindSha256 = "410c7828c4fec2f2179bd956073522415831d27c00416381b8f71153c190a311"  # refind-bin-0.14.2.zip
$script:MinPartitionSizeGBExt4 = 12  # 12 GB ext4 boot partition (requires WSL + rEFInd)

# ─── constants ───────────────────────────────────────────────────────────────
$script:IsoCacheDays       = 30
$script:DownloadTimeoutMin = 60
$script:RetryAttempts      = 4
$script:RetryDelaySec      = 15
$script:CountdownSeconds   = 60
$script:PartitionAlignMB   = 1
$script:PartitionBufferMB  = 16
$script:GapThresholdMB     = 1
$script:PartitionToleranceMB = 100
# ─── Distro Data Table (loaded from JSON) ─────────────────────────────────────
function Get-DistroData {
    $raw = $null

    # Try 0: embedded JSON from compilation
    if ($script:DistrosJson) {
        try {
            $raw = $script:DistrosJson | ConvertFrom-Json
        } catch {}
    }

    $jsonPath = $null
    if (-not $raw) {
        # Try 1: distros.json in same directory as script
        $sameDir = Join-Path $PSScriptRoot "distros.json"
        if (Test-Path $sameDir) { $jsonPath = $sameDir }

        # Try 2: distros.json in parent directory (repo layout)
        if (-not $jsonPath) {
            $parentDir = Join-Path $PSScriptRoot "..\distros.json"
            try {
                $resolved = (Resolve-Path $parentDir -ErrorAction Stop).Path
                if (Test-Path $resolved) { $jsonPath = $resolved }
            } catch {}
        }

        # Try 3: Download from GitHub
        if (-not $jsonPath) {
            $jsonPath = Download-DistroConfig
        }

        # All attempts failed
        if (-not $jsonPath -or -not (Test-Path $jsonPath)) {
            $result = Show-MissingConfigDialog
            if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
                Start-Process "https://github.com/Cosipa/QuickLinux#troubleshooting"
            }
            exit 1
        }

        $raw = Get-Content $jsonPath -Raw | ConvertFrom-Json
    }

    $distros = [ordered]@{
    }
    foreach ($key in $raw.PSObject.Properties.Name) {
        $d = $raw.$key
        $distros[$key] = [ordered]@{
            Name           = $d.name
            RadioLabel     = $d.radio_label
            ExpectedSize   = $d.expected_size
            Mirrors        = @($d.mirrors)
            Checksum       = $d.checksum
            IsoFilename    = $d.iso_filename
            DownloadPage   = $d.download_page
            DownloadMsg    = $d.download_msg
            Keyword        = $d.keyword
            ValidationFile = ($d.validation_file -replace '/', '\')
            IsHybrid       = [bool]$d.is_hybrid
        }
    }
    return $distros
}
$script:Distros = $null
$script:IsoPath = ""
$script:CustomIsoPath = ""
$script:IsRunning = $false
$script:CancelRequested = $false
$script:MaxAvailableGB = 10000
$script:IsoDownloaded = $false
$script:AdvancedVisible = $false
