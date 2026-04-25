function Test-WslAvailable {
    try {
        $wslOutput = & wsl --list --quiet 2>&1
        if ($LASTEXITCODE -ne 0) { return $false }
        $distros = @($wslOutput | ForEach-Object { ($_ -replace "`0", "").Trim() } | Where-Object { $_ })
        return ($distros.Count -gt 0)
    } catch {
        return $false
    }
}
function Install-WslDistro {
    # Install just a WSL distro -- called only after WSL features are confirmed installed (flag file exists)
    Log-Message "Installing WSL Ubuntu distribution..."
    Set-Status "Installing WSL Ubuntu distribution (this may take a few minutes)..."
    $form.Refresh()

    $distroOutput = & wsl --install -d Ubuntu --no-launch 2>&1
    $distroExit = $LASTEXITCODE
    # Convert ErrorRecord objects to strings for reliable pattern matching
    $distroLines = @($distroOutput | ForEach-Object { ("$_" -replace "`0", "").Trim() } | Where-Object { $_ })
    foreach ($line in $distroLines) {
        Log-Message "  WSL: $line"
    }

    # Check for errors indicating Hyper-V/VMP still not functional
    $featureMissing = $distroLines | Where-Object {
        $_ -match "HCS_E_HYPERV_NOT_INSTALLED|Virtual Machine Platform|not supported with your current|EnableVirtualization|0x80370102"
    }
    if ($featureMissing) {
        Log-Message "WSL2 virtualization is not available on this system." -Error
        Log-Message "  Ensure hardware virtualization (VT-x/AMD-V) is enabled in BIOS/UEFI."
        Log-Message "  If running in a VM, enable nested virtualization and fully power off/restart the VM."
        return $false
    }

    Start-Sleep -Seconds 5

    if (Test-WslAvailable) {
        Log-Message "WSL Ubuntu distribution installed successfully."
        return $true
    }

    # Distro may need initialization -- try launching it briefly
    Log-Message "Initializing WSL distribution..."
    & wsl -e true 2>&1 | Out-Null
    Start-Sleep -Seconds 5

    if (Test-WslAvailable) {
        Log-Message "WSL is now available."
        return $true
    }

    Log-Message "Failed to install WSL Ubuntu distribution." -Error
    return $false
}
function Get-WslDefaultDistro {
    try {
        $distros = @(& wsl --list --quiet 2>&1 | ForEach-Object { ($_ -replace "`0", "").Trim() } | Where-Object { $_ })
        if ($distros.Count -gt 0) { return $distros[0] }
    } catch {}
    return $null
}
function Format-PartitionExt4Wsl {
    param(
        [int]$DiskNumber,
        [int]$PartitionNumber,
        [string]$Label = "LINUX_LIVE"
    )

    $physDrive = "\\.\PHYSICALDRIVE$DiskNumber"

    # Remove Windows drive letter if assigned (Windows can't use ext4)
    try {
        $part = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber -ErrorAction Stop
        if ($part.DriveLetter) {
            Remove-PartitionAccessPath -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber `
                -AccessPath "$($part.DriveLetter):\" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    } catch {}

    # Attach raw device to WSL2
    Log-Message "Attaching disk to WSL for ext4 formatting..."
    $result = & wsl --mount $physDrive --partition $PartitionNumber --bare 2>&1
    if ($LASTEXITCODE -ne 0) {
        Log-Message "Failed to attach disk to WSL: $result" -Error
        return $false
    }

    Start-Sleep -Seconds 3

    # Find the block device exposed by WSL --mount --bare
    # Use lsblk to find the specific partition device, not just any partition
    $devPath = (& wsl -u root bash -c "lsblk -rno PATH,TYPE,PARTN 2>/dev/null | awk '\$2==\"part\" && \$3==$PartitionNumber {print \$1; exit}'" 2>&1).Trim()
    $devPath = $devPath -replace "`0", ""

    if (-not $devPath -or -not $devPath.StartsWith("/dev/")) {
        Log-Message "Could not find block device in WSL (got: '$devPath')" -Error
        & wsl --unmount $physDrive 2>$null
        return $false
    }

    Log-Message "Block device in WSL: $devPath"

    # Format as ext4
    Log-Message "Formatting as ext4 via WSL (label: $Label)..."
    Set-Status "Formatting boot partition ext4 via WSL..."
    $result = & wsl -u root mkfs.ext4 -F -L $Label $devPath 2>&1
    $mkfsExit = $LASTEXITCODE

    # Detach
    & wsl --unmount $physDrive 2>$null
    Start-Sleep -Seconds 1

    if ($mkfsExit -ne 0) {
        Log-Message "mkfs.ext4 failed: $result" -Error
        return $false
    }

    Log-Message "ext4 filesystem created successfully."
    return $true
}
function Mount-Ext4PartitionWsl {
    param(
        [int]$DiskNumber,
        [int]$PartitionNumber
    )

    $physDrive = "\\.\PHYSICALDRIVE$DiskNumber"

    Log-Message "Mounting ext4 partition via WSL..."
    Set-Status "Mounting ext4 partition via WSL..."
    $result = & wsl --mount $physDrive --partition $PartitionNumber --type ext4 2>&1
    if ($LASTEXITCODE -ne 0) {
        Log-Message "Failed to mount ext4 via WSL: $result" -Error
        return $null
    }

    Start-Sleep -Seconds 3

    # Find mount point for the specific partition we just mounted
    # First get the device path, then find its mount point
    $devPath = (& wsl -u root bash -c "lsblk -rno PATH,PARTN 2>/dev/null | awk '\$2==$PartitionNumber {print \$1; exit}'" 2>&1).Trim()
    $devPath = $devPath -replace "`0", ""
    if ($devPath -and $devPath.StartsWith("/dev/")) {
        $mountPoint = (& wsl -u root bash -c "findmnt -rno TARGET $devPath 2>/dev/null | head -1" 2>&1).Trim()
    } else {
        # Fallback: find the most recently mounted ext4 partition
        $mountPoint = (& wsl -u root bash -c "findmnt -rno TARGET -t ext4 2>/dev/null | tail -1" 2>&1).Trim()
    }
    $mountPoint = $mountPoint -replace "`0", ""

    if (-not $mountPoint) {
        Log-Message "Could not determine WSL mount point" -Error
        & wsl --unmount $physDrive 2>$null
        return $null
    }

    # Get default WSL distro name
    $wslDistro = Get-WslDefaultDistro
    if (-not $wslDistro) {
        Log-Message "Could not determine default WSL distribution" -Error
        & wsl --unmount $physDrive 2>$null
        return $null
    }

    $wslWinPath = "\\wsl.localhost\$wslDistro$mountPoint"

    Log-Message "WSL mount point: $mountPoint"
    Log-Message "Windows UNC path: $wslWinPath"

    return @{
        WslPath   = $mountPoint
        WinPath   = $wslWinPath
        PhysDrive = $physDrive
    }
}
function Dismount-Ext4PartitionWsl {
    param([string]$PhysDrive)

    if ($PhysDrive) {
        & wsl --unmount $PhysDrive 2>$null
        Log-Message "ext4 partition unmounted from WSL."
    }
}
