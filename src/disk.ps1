function Get-BootPartSizeGB {
    if ($ext4BootCheck.Checked) { return $script:MinPartitionSizeGBExt4 }
    return $script:MinPartitionSizeGB
}
function Get-BootPartFsType {
    if ($ext4BootCheck.Checked) { return "ext4" }
    return "FAT32"
}
function Get-PartitionLabel {
    param($Part)
    if ($Part.DriveLetter -eq 'C') {
        return "C: (Windows/NTFS)    "
    } elseif ($Part.DriveLetter) {
        return "$($Part.DriveLetter): drive               "
    } elseif ($Part.Type -eq "Recovery" -or $Part.GptType -match "de94bba4") {
        return "Recovery             "
    } elseif ($Part.IsSystem) {
        return "EFI System (ESP)     "
    } elseif ($Part.GptType -match "e3c9e316") {
        return "Microsoft Reserved   "
    } else {
        return "Partition            "
    }
}
function Format-AfterLayout {
    param(
        [array]$Partitions,
        [string]$DistroName,
        [int]$BootPartSizeGB,
        [int]$LinuxSizeGB = 0,
        [string]$ShrinkLetter = $null,
        [double]$NewShrinkSizeGB = 0,
        [switch]$ShrinkLinuxOnly,
        [switch]$AppendLinuxAndBoot,
        [double]$RemainingFreeGB = 0,
        [switch]$ShowUnchanged,
        [switch]$NoChanges,
        [switch]$UseRefind,
        [string]$BootPartFsType = "FAT32"
    )
    $lines = @()
    foreach ($part in $Partitions) {
        $sGB = [math]::Round($part.Size / 1GB, 2)

        if ($ShrinkLetter -and $part.DriveLetter -eq $ShrinkLetter) {
            $label = Get-PartitionLabel -Part $part
            $lines += "  $label $NewShrinkSizeGB GB  (shrunk)"
            $lines += "  [Unallocated - Linux]  $LinuxSizeGB GB  <-- Linux Storage after install"
            if (-not $ShrinkLinuxOnly) {
                $lines += "  LINUX_LIVE ($bootPartFsType)     $BootPartSizeGB GB  <-- $DistroName live boot"
            }
            if ($UseRefind) {
                $lines += "  REFIND (FAT32)         0.1 GB  <-- rEFInd boot manager"
            }
            continue
        }

        $label = Get-PartitionLabel -Part $part
        $suffix = if ($ShowUnchanged -and $part.DriveLetter) { "  (unchanged)" }
                  elseif ($NoChanges -and $part.DriveLetter) { "  (unchanged)" }
                  else { "" }
        $lines += "  $label $sGB GB$suffix"
    }

    if ($AppendLinuxAndBoot) {
        if ($RemainingFreeGB -gt 0) {
            $lines += "  [Unallocated - Linux]  $RemainingFreeGB GB  <-- Linux Storage after install"
        }
        $lines += "  LINUX_LIVE ($bootPartFsType)     $BootPartSizeGB GB  <-- $DistroName live boot"
        if ($UseRefind) {
            $lines += "  REFIND (FAT32)         0.1 GB  <-- rEFInd boot manager"
        }
    }

    if ($NoChanges) {
        $lines += ""
        $lines += "  (No changes - disk cannot be used as-is)"
    }

    return $lines
}
function Shrink-Partition {
    param(
        [string]$DriveLetter,
        [double]$ShrinkAmountGB
    )

    # ── BitLocker check ──────────────────────────────────────────────────────
    try {
        $bitlockerStatus = & manage-bde -status "$DriveLetter`:" 2>&1 | Out-String
        if ($bitlockerStatus -match "Conversion Status:\s*Encrypted|Conversion Status:\s*Fully Encrypted") {
            Log-Message "ERROR: ${DriveLetter}: is encrypted with BitLocker!" -Error
            Log-Message "Shrinking an encrypted partition can cause data loss." -Error
            Log-Message "Please suspend or disable BitLocker before continuing." -Error
            [System.Windows.Forms.MessageBox]::Show(
                "${DriveLetter}: is encrypted with BitLocker.`n`n" +
                "Shrinking an encrypted partition can cause data corruption.`n`n" +
                "Please suspend BitLocker protection for this drive first:`n" +
                "  manage-bde -protectors -disable ${DriveLetter}:`n`n" +
                "Then retry the installation.",
                "BitLocker Detected",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )
            return $false
        }
    } catch {
        Log-Message "Warning: Could not check BitLocker status: $_"
    }

    try {
        $currentSize = (Get-Partition -DriveLetter $DriveLetter).Size
        $newSize = $currentSize - ($ShrinkAmountGB * 1GB)
        Resize-Partition -DriveLetter $DriveLetter -Size $newSize -ErrorAction Stop
        Log-Message "${DriveLetter}: partition shrunk successfully!"

        # ── Wait for filesystem to settle ────────────────────────────────────
        # Windows may still be finalizing filesystem metadata after shrink.
        # Poll until the partition reports stable size.
        $settled = $false
        for ($i = 0; $i -lt 30; $i++) {
            Start-Sleep -Seconds 1
            try {
                $currentPart = Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop
                if ($currentPart.Size -le $newSize + 1MB) {
                    $settled = $true
                    break
                }
            } catch {}
        }
        if (-not $settled) {
            Log-Message "Warning: Partition size did not stabilize after 30s" -Error
        }

        return $true
    }
    catch {
        Log-Message "Trying diskpart method..."
        $sizeMB = [int]($ShrinkAmountGB * 1024)
        $diskpartScript = @"
select volume $DriveLetter
shrink desired=$sizeMB
exit
"@
        $scriptPath = Join-Path $env:TEMP "shrink_script.txt"
        $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII

        $result = diskpart /s $scriptPath
        Remove-Item $scriptPath -Force

        if ($result -match "successfully") {
            Log-Message "${DriveLetter}: partition shrunk successfully!"

            # Wait for filesystem to settle after diskpart shrink
            Start-Sleep -Seconds 10
            return $true
        } else {
            $hint = if ($DriveLetter -eq 'C') {
                "You may need to: 1) Run disk cleanup 2) Disable hibernation (powercfg -h off) 3) Reboot"
            } else {
                "You may need to: 1) Run disk cleanup 2) Defragment the drive 3) Reboot"
            }
            Log-Message "Failed to shrink ${DriveLetter}: partition!" -Error
            Log-Message $hint -Error
            return $false
        }
    }
}
function New-UefiBootEntry {
    param(
        [string]$DistroName,
        [string]$DevicePartition,
        [string]$EfiPath
    )
    $bootCreated = $false
    try {
        $copyOutput = & bcdedit.exe /copy "{bootmgr}" /d "`"$DistroName`"" 2>&1
        $copyOutputStr = $copyOutput -join " "

        if ($copyOutputStr -match '\{[0-9a-fA-F-]+\}') {
            $newGuid = $matches[0]
            Log-Message "Created new entry: $newGuid"

            $inheritedProps = @("default", "displayorder", "toolsdisplayorder", "timeout", "resumeobject", "inherit", "locale")
            foreach ($prop in $inheritedProps) {
                Start-Process "bcdedit.exe" -ArgumentList "/deletevalue", $newGuid, $prop -Wait -NoNewWindow -ErrorAction SilentlyContinue 2>$null | Out-Null
            }

            Log-Message "Setting device=partition=$DevicePartition path=$EfiPath"

            $r1 = Start-Process "bcdedit.exe" -ArgumentList "/set", $newGuid, "device", "partition=$DevicePartition" -Wait -PassThru -NoNewWindow
            $r2 = Start-Process "bcdedit.exe" -ArgumentList "/set", $newGuid, "path", $EfiPath -Wait -PassThru -NoNewWindow
            Start-Process "bcdedit.exe" -ArgumentList "/set", $newGuid, "description", "`"$DistroName`"" -Wait -NoNewWindow -ErrorAction SilentlyContinue | Out-Null
            $r3 = Start-Process "bcdedit.exe" -ArgumentList "/set", "{fwbootmgr}", "displayorder", $newGuid, "/addfirst" -Wait -PassThru -NoNewWindow
            $r4 = Start-Process "bcdedit.exe" -ArgumentList "/set", "{fwbootmgr}", "default", $newGuid -Wait -PassThru -NoNewWindow

            if ($r1.ExitCode -eq 0 -and $r2.ExitCode -eq 0 -and $r3.ExitCode -eq 0 -and $r4.ExitCode -eq 0) {
                Log-Message "UEFI boot entry created and set as default!"
                $bootCreated = $true
            } else {
                Log-Message "Some bcdedit commands failed (exit codes: device=$($r1.ExitCode), path=$($r2.ExitCode), displayorder=$($r3.ExitCode), default=$($r4.ExitCode))" -Error
                Start-Process "bcdedit.exe" -ArgumentList "/delete", $newGuid -Wait -NoNewWindow -ErrorAction SilentlyContinue
            }
        } else {
            Log-Message "bcdedit /copy did not return a GUID: $copyOutputStr" -Error
        }
    }
    catch {
        Log-Message "Failed to create boot entry: $_" -Error
    }
    return $bootCreated
}
function Set-UILocked {
    param([bool]$Locked)
    $enabled = -not $Locked
    $downloadButton.Enabled = $enabled -and -not $customRadio.Checked
    $prepareButton.Enabled = $enabled -and $script:IsoDownloaded
    $exitButton.Enabled = $enabled
    $distroCombo.Enabled = $enabled
    $browseButton.Enabled = $enabled -and $customRadio.Checked
}
function Update-DiskInfo {
    try {
        $cDrive = Get-Partition -DriveLetter C -ErrorAction Stop | Select-Object -First 1
        $disk = Get-Disk -Number $cDrive.DiskNumber -ErrorAction Stop
        $volume = Get-Volume -DriveLetter C -ErrorAction Stop

        $partitionNumber = if ($cDrive.PartitionNumber) {
            $cDrive.PartitionNumber
        } else {
            (Get-Partition -DiskNumber $cDrive.DiskNumber | Where-Object { $_.DriveLetter -eq 'C' }).PartitionNumber
        }

        $diskInfo = "C: Drive Information  |  " +
            "Total Size: $([math]::Round($volume.Size / 1GB, 2)) GB  |  " +
            "Free Space: $([math]::Round($volume.SizeRemaining / 1GB, 2)) GB  |  " +
            "File System: $($volume.FileSystem)  |  " +
            "Disk Number: $($cDrive.DiskNumber)  |  " +
            "Partition Number: $partitionNumber"

        $diskInfoText.Text = $diskInfo

        $script:CDriveInfo = @{
            DiskNumber = $cDrive.DiskNumber
            PartitionNumber = $partitionNumber
            FreeGB = [math]::Round($volume.SizeRemaining / 1GB, 2)
            TotalGB = [math]::Round($volume.Size / 1GB, 2)
        }

        # Max available stored for the disk plan dialog
        $script:MaxAvailableGB = [math]::Floor($script:CDriveInfo.FreeGB - $script:MinPartitionSizeGB - 10)
    }
    catch {
        Log-Message "Error getting disk information: $_" -Error
        $diskInfoText.Text = "Error retrieving disk information"
    }
}
function Get-DiskLayoutText {
    param(
        [int]$DiskNumber
    )
    $disk = Get-Disk -Number $DiskNumber
    $partitions = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Sort-Object Offset
    $lines = @()

    if (-not $partitions -or $partitions.Count -eq 0) {
        $lines += "  [Entire disk is unallocated]  $([math]::Round($disk.Size / 1GB, 2)) GB"
        return $lines
    }

    $previousEnd = [int64]0
    foreach ($part in $partitions) {
        if ($part.Offset -gt ($previousEnd + 1MB)) {
            $gapGB = [math]::Round(($part.Offset - $previousEnd) / 1GB, 2)
            if ($gapGB -gt 0.01) {
                $lines += "  [Unallocated]             $gapGB GB"
            }
        }

        $sizeGB = [math]::Round($part.Size / 1GB, 2)
        $label = Get-PartitionLabel -Part $part

        $freeNote = ""
        if ($part.DriveLetter) {
            try {
                $vol = Get-Volume -DriveLetter $part.DriveLetter -ErrorAction Stop
                if ($vol.SizeRemaining) {
                    $freeNote = "  (Free: $([math]::Round($vol.SizeRemaining / 1GB, 2)) GB)"
                }
            } catch {}
        }

        $lines += "  $label $sizeGB GB$freeNote"
        $previousEnd = $part.Offset + $part.Size
    }
    # Trailing
    if ($disk.Size -gt ($previousEnd + 1MB)) {
        $trailGB = [math]::Round(($disk.Size - $previousEnd) / 1GB, 2)
        if ($trailGB -gt 0.01) {
            $lines += "  [Unallocated]             $trailGB GB"
        }
    }

    return $lines
}
function Get-DiskUnallocatedGB {
    param(
        [int]$DiskNumber,
        [int64]$AfterOffset = 0
    )
    $disk = Get-Disk -Number $DiskNumber
    $partitions = Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue | Sort-Object Offset

    $total = [int64]0
    $previousEnd = [int64]0

    if ($partitions) {
        foreach ($part in $partitions) {
            $gap = $part.Offset - $previousEnd
            if ($gap -gt 1MB -and $previousEnd -ge $AfterOffset) {
                $total += $gap
            }
            $previousEnd = $part.Offset + $part.Size
        }
    }
    $trailing = $disk.Size - $previousEnd
    if ($trailing -gt 1MB -and $previousEnd -ge $AfterOffset) {
        $total += $trailing
    }

    return [math]::Round($total / 1GB, 2)
}
function Get-PartitionFresh {
    param(
        [Parameter(Mandatory)][int]$DiskNumber,
        [int]$PartitionNumber = 0,
        [string]$DriveLetter = ""
    )
    # Brief pause lets Windows finalize partition metadata
    Start-Sleep -Milliseconds 500
    try {
        if ($PartitionNumber -gt 0) {
            return Get-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber -ErrorAction Stop
        } elseif ($DriveLetter) {
            return Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop
        } else {
            return Get-Partition -DiskNumber $DiskNumber -ErrorAction Stop
        }
    } catch {
        # Retry once after a longer pause
        Start-Sleep -Seconds 2
        if ($PartitionNumber -gt 0) {
            return Get-Partition -DiskNumber $DiskNumber -PartitionNumber $PartitionNumber -ErrorAction Stop
        } elseif ($DriveLetter) {
            return Get-Partition -DriveLetter $DriveLetter -ErrorAction Stop
        } else {
            return Get-Partition -DiskNumber $DiskNumber -ErrorAction Stop
        }
    }
}
function Install-Refind {
    param(
        [string]$RefindDriveLetter,
        [string]$BootDriveLetter = "",
        [string]$BootDrivePath = "",
        [string]$DistroLabel
    )

    Log-Message ""
    Log-Message "== Installing rEFInd boot manager =="

    $refindZip = Download-Refind
    if (-not $refindZip) {
        Log-Message "Cannot install rEFInd without the download." -Error
        return $false
    }

    # Extract rEFInd
    Log-Message "Extracting rEFInd..."
    Set-Status "Extracting rEFInd..."
    $extractDir = Join-Path $env:TEMP "refind_extract"
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force }

    try {
        Expand-Archive -Path $refindZip -DestinationPath $extractDir -Force
    }
    catch {
        Log-Message "Failed to extract rEFInd: $_" -Error
        return $false
    }

    $refindSrc = Join-Path $extractDir "refind-bin-0.14.2\refind"
    $refindDrive = "${RefindDriveLetter}:"
    $efiBoot = Join-Path $refindDrive "EFI\BOOT"
    New-Item -Path $efiBoot -ItemType Directory -Force | Out-Null

    Log-Message "Copying rEFInd files..."
    Set-Status "Installing rEFInd..."

    # Copy refind_x64.efi as default UEFI loader
    $srcEfi = Join-Path $refindSrc "refind_x64.efi"
    if (Test-Path $srcEfi) {
        Copy-Item $srcEfi (Join-Path $efiBoot "BOOTx64.EFI") -Force
        Log-Message "  Copied refind_x64.efi as BOOTx64.EFI"
    } else {
        Log-Message "refind_x64.efi not found in extracted archive!" -Error
        return $false
    }

    # Copy filesystem drivers (ext4 needed to read LINUX_LIVE if ext4)
    $driversDir = Join-Path $efiBoot "drivers_x64"
    New-Item -Path $driversDir -ItemType Directory -Force | Out-Null
    $driversSrc = Join-Path $refindSrc "drivers_x64"
    foreach ($drv in @("ext4_x64.efi", "ext2_x64.efi")) {
        $src = Join-Path $driversSrc $drv
        if (Test-Path $src) {
            Copy-Item $src $driversDir -Force
            Log-Message "  Copied driver: $drv"
        }
    }

    # Copy icons
    $iconsSrc = Join-Path $refindSrc "icons"
    if (Test-Path $iconsSrc) {
        $iconsDir = Join-Path $efiBoot "icons"
        New-Item -Path $iconsDir -ItemType Directory -Force | Out-Null
        robocopy $iconsSrc $iconsDir /E /R:2 /W:2 /NP /NFL /NDL | Out-Null
        Log-Message "  Copied rEFInd icons."
    }

    # Detect boot layout on LINUX_LIVE partition
    $bootDrive = if ($BootDrivePath) { $BootDrivePath } else { "${BootDriveLetter}:" }
    $hasPxeboot = Test-Path (Join-Path $bootDrive "images\pxeboot\vmlinuz")
    $hasCasper = Test-Path (Join-Path $bootDrive "casper\vmlinuz")
    $hasLive = Test-Path (Join-Path $bootDrive "live\vmlinuz")

    # Extract kernel args from distro's grub.cfg
    $extraArgs = ""
    foreach ($cfgPath in @("EFI\BOOT\grub.cfg", "boot\grub2\grub.cfg", "boot\grub\grub.cfg")) {
        $full = Join-Path $bootDrive $cfgPath
        if (Test-Path $full) {
            try {
                $content = Get-Content $full -Raw -ErrorAction Stop
                foreach ($line in ($content -split "`n")) {
                    $s = $line.Trim()
                    if ($s -match "^(linux|linuxefi)\s") {
                        $parts = $s -split "\s+"
                        $args = @()
                        for ($i = 2; $i -lt $parts.Count; $i++) {
                            $p = $parts[$i]
                            if ($p -match "^root=") { continue }
                            if ($p -match "CDLABEL=" -or $p -match "LABEL=") {
                                $p = $p -replace "(CDLABEL=|LABEL=)\S+", '$1LINUX_LIVE'
                            }
                            $args += $p
                        }
                        $extraArgs = $args -join " "
                        break
                    }
                }
            } catch {}
            if ($extraArgs) { break }
        }
    }

    # Write refind.conf
    Log-Message "Writing rEFInd configuration..."
    $conf = "# rEFInd configuration - generated by QuickLinux`n"
    $conf += "timeout 10`n"
    $conf += "use_graphics_for linux`n"
    $conf += "scanfor internal,external,manual`n"
    $conf += "scan_all_linux_kernels false`n"
    $conf += "`n"

    if ($hasPxeboot) {
        if (-not $extraArgs) { $extraArgs = "rd.live.image rhgb quiet" }
        $conf += "menuentry `"$DistroLabel`" {`n"
        $conf += "  volume LINUX_LIVE`n"
        $conf += "  loader /images/pxeboot/vmlinuz`n"
        $conf += "  initrd /images/pxeboot/initrd.img`n"
        $conf += "  options `"root=live:LABEL=LINUX_LIVE $extraArgs`"`n"
        $conf += "}`n`n"
        $conf += "menuentry `"$DistroLabel (verbose)`" {`n"
        $conf += "  volume LINUX_LIVE`n"
        $conf += "  loader /images/pxeboot/vmlinuz`n"
        $conf += "  initrd /images/pxeboot/initrd.img`n"
        $conf += "  options `"root=live:LABEL=LINUX_LIVE rd.live.image`"`n"
        $conf += "}`n"
    }
    elseif ($hasCasper) {
        if (-not $extraArgs) { $extraArgs = "quiet splash" }
        $conf += "menuentry `"$DistroLabel`" {`n"
        $conf += "  volume LINUX_LIVE`n"
        $conf += "  loader /casper/vmlinuz`n"
        $conf += "  initrd /casper/initrd`n"
        $conf += "  options `"boot=casper $extraArgs`"`n"
        $conf += "}`n"
    }
    elseif ($hasLive) {
        if (-not $extraArgs) { $extraArgs = "boot=live components quiet splash" }
        $conf += "menuentry `"$DistroLabel`" {`n"
        $conf += "  volume LINUX_LIVE`n"
        $conf += "  loader /live/vmlinuz`n"
        $conf += "  initrd /live/initrd.img`n"
        $conf += "  options `"$extraArgs`"`n"
        $conf += "}`n"
    }
    else {
        $conf += "# Unknown layout - rEFInd will auto-scan.`n"
    }

    Set-Content -Path (Join-Path $efiBoot "refind.conf") -Value $conf -Encoding UTF8 -Force
    Log-Message "rEFInd configuration written."

    # Clean up extract dir
    if (Test-Path $extractDir) { Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue }

    Log-Message "rEFInd installed successfully."
    Log-Message "  rEFInd partition: $refindDrive"
    return $true
}
function New-RefindPartition {
    param(
        [int]$DiskNumber,
        [int64]$AfterOffset = 0
    )

    Log-Message "Creating 100 MB rEFInd partition..."
    Set-Status "Creating rEFInd partition..."

    $refindSize = [int64]($script:RefindSizeMB * 1MB)
    $refindDriveLetter = $null

    # Align offset to 1 MB boundary
    if ($AfterOffset -gt 0) {
        $alignedOffset = [int64]([Math]::Ceiling($AfterOffset / 1MB)) * 1MB
    } else {
        $alignedOffset = 0
    }

    try {
        if ($alignedOffset -gt 0) {
            $refindPartition = New-Partition -DiskNumber $DiskNumber `
                -Offset $alignedOffset `
                -Size $refindSize `
                -AssignDriveLetter `
                -ErrorAction Stop
        } else {
            $refindPartition = New-Partition -DiskNumber $DiskNumber `
                -Size $refindSize `
                -AssignDriveLetter `
                -ErrorAction Stop
        }

        Start-Sleep -Seconds 2
        $refindDriveLetter = $refindPartition.DriveLetter

        if (-not $refindDriveLetter) {
            $refindPartition | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction SilentlyContinue | Out-Null
            Start-Sleep -Seconds 2
            $refindPartition = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $refindPartition.PartitionNumber
            $refindDriveLetter = $refindPartition.DriveLetter
        }

        if (-not $refindDriveLetter) {
            throw "Could not assign a drive letter to the rEFInd partition"
        }

        Format-Volume -DriveLetter $refindDriveLetter `
            -FileSystem FAT32 `
            -NewFileSystemLabel "REFIND" `
            -Confirm:$false `
            -ErrorAction Stop | Out-Null

        Log-Message "rEFInd partition created as ${refindDriveLetter}: (REFIND)"
        return $refindDriveLetter
    }
    catch {
        Log-Message "Failed to create rEFInd partition: $_" -Error

        # Fallback: try diskpart
        if ($alignedOffset -gt 0) {
            Log-Message "Trying diskpart method for rEFInd partition..."
            $offsetMB = [int64]([Math]::Floor($alignedOffset / 1MB))
            $sizeMB = $script:RefindSizeMB

            $diskpartScript = @"
select disk $DiskNumber
create partition primary offset=$offsetMB size=$sizeMB
assign
exit
"@
            $scriptPath = Join-Path $env:TEMP "create_refind_partition.txt"
            $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII
            $result = & diskpart /s $scriptPath 2>&1
            Remove-Item $scriptPath -Force

            $resultString = $result -join "`n"
            if ($resultString -match "successfully created") {
                Start-Sleep -Seconds 3

                # Find the new partition
                $targetSize = [int64]($sizeMB * 1MB)
                $tolerance = [int64](10MB)
                $newParts = Get-Partition -DiskNumber $DiskNumber |
                    Where-Object { [Math]::Abs($_.Size - $targetSize) -lt $tolerance }
                $refPart = $newParts | Sort-Object Offset -Descending | Select-Object -First 1

                if ($refPart) {
                    $refindDriveLetter = $refPart.DriveLetter
                    if (-not $refindDriveLetter) {
                        $refPart | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction SilentlyContinue | Out-Null
                        Start-Sleep -Seconds 2
                        $refPart = Get-Partition -DiskNumber $DiskNumber -PartitionNumber $refPart.PartitionNumber
                        $refindDriveLetter = $refPart.DriveLetter
                    }

                    if ($refindDriveLetter) {
                        Format-Volume -DriveLetter $refindDriveLetter `
                            -FileSystem FAT32 `
                            -NewFileSystemLabel "REFIND" `
                            -Confirm:$false `
                            -ErrorAction Stop | Out-Null
                        Log-Message "rEFInd partition created via diskpart as ${refindDriveLetter}: (REFIND)"
                        return $refindDriveLetter
                    }
                }
            }
        }

        Log-Message "All rEFInd partition creation methods failed" -Error
        return $null
    }
}
function Start-Installation {
    if ($script:IsRunning) {
        return
    }

    $distro = Get-SelectedDistro
    $distroName = $distro.Name

    # ========================================
    # PRE-FLIGHT VALIDATION
    # ========================================
    $preflightIssues = @()

    # Check GPT partition style on target disks
    try {
        $allDisks = Get-Disk -ErrorAction SilentlyContinue
        foreach ($disk in $allDisks) {
            if ($disk.PartitionStyle -ne "GPT" -and $disk.BusType -ne "USB") {
                $preflightIssues += "Disk $($disk.Number) ($([math]::Round($disk.Size/1GB,0)) GB) uses $($disk.PartitionStyle) - only GPT is supported"
            }
        }
    } catch {}

    # Check Secure Boot status (rEFInd may require it disabled on some systems)
    try {
        $secureBoot = Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
        if ($secureBoot) {
            Log-Message "Secure Boot is enabled (rEFInd supports Secure Boot, but may need custom keys)"
        }
    } catch {
        Log-Message "Could not determine Secure Boot status"
    }

    # Check Virtualization (needed for WSL2 if ext4 boot selected)
    if ($useExt4Boot) {
        try {
            $vmMode = (Get-ComputerInfo).HypervisorPresent
            if (-not $vmMode) {
                $preflightIssues += "Hardware virtualization not detected - WSL2 (required for ext4 boot) may not work"
            }
        } catch {}
    }

    # Check available disk space on Windows drive
    try {
        $cVol = Get-Volume -DriveLetter C -ErrorAction Stop
        $cFreeGB = [math]::Round($cVol.SizeRemaining / 1GB, 2)
        if ($cFreeGB -lt 10) {
            $preflightIssues += "C: drive has only ${cFreeGB} GB free - at least 10 GB recommended for safe shrinking"
        }
    } catch {}

    if ($preflightIssues.Count -gt 0) {
        $issueText = "Pre-flight checks found issues:`n`n"
        foreach ($issue in $preflightIssues) {
            $issueText += "• $issue`n"
        }
        $issueText += "`nDo you want to continue anyway?"

        $preflightResult = [System.Windows.Forms.MessageBox]::Show(
            $issueText,
            "Pre-flight Warnings",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
        if ($preflightResult -ne [System.Windows.Forms.DialogResult]::Yes) {
            Log-Message "Preparation cancelled due to pre-flight warnings."
            Set-Status "Ready - download an ISO or use a custom one"
            return
        }
    }

    # ========================================
    # SHOW DISK PLAN - user must approve
    # ========================================
    $planResult = Show-DiskPlan -DistroName $distroName

    if (-not $planResult.Approved) {
        Log-Message "Preparation cancelled by user at disk plan review."
        Set-Status "Ready to install"
        return
    }

    $selectedStrategy = $planResult.Strategy
    $targetDiskNumber = $planResult.TargetDiskNumber
    $isOtherDrive = ($selectedStrategy -eq "other_drive" -or $selectedStrategy -eq "other_drive_shrink" -or $selectedStrategy -eq "wipe_disk")
    $otherDriveShrinkLetter = $planResult.ShrinkDriveLetter
    $otherDriveShrinkAmountGB = $planResult.ShrinkAmountGB
    $linuxSizeGB = $planResult.LinuxSizeGB
    $useRefind = $planResult.UseRefind
    $useExt4Boot = $planResult.UseExt4Boot
    $bootPartSizeGB = if ($useExt4Boot) { $script:MinPartitionSizeGBExt4 } else { $script:MinPartitionSizeGB }
    $bootPartFsType = if ($useExt4Boot) { "ext4" } else { "FAT32" }
    $refindGB = if ($useRefind) { 0.1 } else { 0 }
    $totalNeededGB = $linuxSizeGB + $bootPartSizeGB + $refindGB
    $refindNote = if ($useRefind) { ", rEFInd: yes" } else { "" }
    $ext4Note = if ($useExt4Boot) { ", ext4 boot: yes" } else { "" }
    $script:WslMountInfo = $null  # track WSL mount for cleanup
    Log-Message "Disk plan approved. Strategy: $selectedStrategy, Target disk: $targetDiskNumber, Linux size: $linuxSizeGB GB$refindNote$ext4Note"

    # ── Re-validate disk state before execution ──────────────────────────────
    # Disk layout may have changed since the plan was shown (Windows Update,
    # antivirus, other processes). Re-check to avoid operating on stale data.
    Log-Message "Re-validating disk state before proceeding..."
    try {
        $currentDisk = Get-Disk -Number $targetDiskNumber -ErrorAction Stop
        $currentPartitions = Get-Partition -DiskNumber $targetDiskNumber -ErrorAction Stop
        $currentPartitionCount = @($currentPartitions).Count
        if ($planResult.ExpectedPartitionCount -and $currentPartitionCount -ne $planResult.ExpectedPartitionCount) {
            Log-Message "WARNING: Disk layout changed since plan was shown!" -Error
            Log-Message "  Expected: $($planResult.ExpectedPartitionCount) partitions, Found: $currentPartitionCount" -Error
            $reconfirm = [System.Windows.Forms.MessageBox]::Show(
                "The disk layout has changed since you reviewed the plan.`n`n" +
                "Partition count: expected $($planResult.ExpectedPartitionCount), now $currentPartitionCount.`n`n" +
                "This could be caused by Windows Update or other disk operations.`n`n" +
                "Do you want to continue anyway?",
                "Disk Layout Changed",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($reconfirm -ne [System.Windows.Forms.DialogResult]::Yes) {
                Log-Message "Preparation cancelled due to disk layout change."
                Set-Status "Ready - download an ISO or use a custom one"
                return
            }
        }
    } catch {
        Log-Message "Warning: Could not re-validate disk state: $_"
    }

    # Validate WSL availability if ext4 boot is selected -- auto-install if missing
    if ($useExt4Boot) {
        Log-Message "Checking WSL availability for ext4 boot partition..."
        if (-not (Test-WslAvailable)) {
            # Check if Virtual Machine Platform is enabled (always a Windows Optional Feature, reliable check)
            $vmpEnabled = $false
            try {
                $vmpFeature = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction Stop
                $vmpEnabled = ($vmpFeature.State -eq "Enabled")
                Log-Message "Virtual Machine Platform state: $($vmpFeature.State)"
            } catch {
                Log-Message "Could not check VMP feature state: $_"
            }

            if ($vmpEnabled) {
                # VMP is enabled -- just need to install a distro (no reboot needed)
                Log-Message "WSL features are enabled. Installing Ubuntu distribution..."
                if (-not (Install-WslDistro)) {
                    [System.Windows.Forms.MessageBox]::Show(
                        "WSL2 could not install the Ubuntu distribution.`n`n" +
                        "This may mean hardware virtualization is not working:`n" +
                        "  - In BIOS/UEFI: enable VT-x (Intel) or AMD-V`n" +
                        "  - In a VM: enable nested virtualization and fully power off/restart`n`n" +
                        "You can retry, or uncheck 'ext4 boot partition' to use FAT32 instead.",
                        "WSL2 Not Available",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Error
                    )
                    Set-Status "Ready - download an ISO or use a custom one"
                    return
                }
            } else {
                # VMP not enabled -- need to enable features, then reboot
                $installWsl = [System.Windows.Forms.MessageBox]::Show(
                    "WSL (Windows Subsystem for Linux) is required to create ext4 partitions " +
                    "but the Virtual Machine Platform feature is not enabled.`n`n" +
                    "Would you like to enable it now?`n`n" +
                    "This will:`n" +
                    "  - Enable the WSL and Virtual Machine Platform features`n" +
                    "  - A system restart will be required`n" +
                    "  - After restart, re-run QuickLinux and Ubuntu will be installed automatically`n`n" +
                    "Note: Virtualization must be enabled in your BIOS/UEFI settings.",
                    "Install WSL?",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )
                if ($installWsl -ne [System.Windows.Forms.DialogResult]::Yes) {
                    Log-Message "Preparation cancelled: WSL is required for ext4 boot." -Error
                    Set-Status "Ready - download an ISO or use a custom one"
                    return
                }

                Log-Message "Enabling WSL and Virtual Machine Platform features..."
                Set-Status "Enabling WSL features..."
                $form.Refresh()

                try {
                    $wslInstallOutput = & wsl --install --no-distribution 2>&1
                    $wslInstallExit = $LASTEXITCODE
                    foreach ($line in $wslInstallOutput) {
                        $cleanLine = ("$line" -replace "`0", "").Trim()
                        if ($cleanLine) { Log-Message "  WSL: $cleanLine" }
                    }

                    Log-Message "WSL feature installation completed."

                    if (Test-WslAvailable) {
                        Log-Message "WSL is now available (no reboot needed)."
                    } else {
                        Log-Message "A system restart is required for WSL features to activate."
                        $rebootNow = [System.Windows.Forms.MessageBox]::Show(
                            "WSL features have been enabled but require a system restart.`n`n" +
                            "After restart, re-run QuickLinux and select ext4 boot again.`n" +
                            "Ubuntu will be downloaded and installed automatically.`n`n" +
                            "The computer will restart after you click OK.",
                            "Restart Required",
                            [System.Windows.Forms.MessageBoxButtons]::OKCancel,
                            [System.Windows.Forms.MessageBoxIcon]::Information
                        )
                        if ($rebootNow -eq [System.Windows.Forms.DialogResult]::OK) {
                            Log-Message "Restarting computer for WSL installation..."
                            Restart-Computer -Force
                        }
                        Set-Status "Ready - download an ISO or use a custom one"
                        return
                    }
                }
                catch {
                    Log-Message "Failed to install WSL: $_" -Error
                    [System.Windows.Forms.MessageBox]::Show(
                        "Failed to install WSL automatically.`n`n" +
                        "Error: $_`n`n" +
                        "Please install WSL manually by running:`n" +
                        "  wsl --install`n`n" +
                        "Then restart your computer and re-run QuickLinux.",
                        "WSL Installation Failed",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Error
                    )
                    Set-Status "Ready - download an ISO or use a custom one"
                    return
                }
            }
        } else {
            Log-Message "WSL is available."
        }
    }

    # Now lock the UI and proceed
    $script:IsRunning = $true
    Set-UILocked $true

    try {
        # Determine ISO path
        if ($customRadio.Checked) {
            if (-not $script:CustomIsoPath -or -not (Test-Path $script:CustomIsoPath)) {
                Log-Message "Error: Please select a valid ISO file!" -Error
                return
            }
            $script:IsoPath = $script:CustomIsoPath
            Log-Message "Using custom ISO: $script:IsoPath"
            $isoInfo = Get-Item $script:IsoPath
            Log-Message "ISO file size: $([math]::Round($isoInfo.Length / 1GB, 2)) GB"
        } else {
            $script:IsoPath = Join-Path $env:TEMP $distro.IsoFilename
            Log-Message "Selected distribution: $distroName"
        }

        # Check space (only if we're shrinking C:)
        if ($selectedStrategy -eq "shrink_all") {
            if ($script:CDriveInfo.FreeGB -lt ($totalNeededGB + 10)) {
                Log-Message "Error: Not enough free space on C: to shrink!" -Error
                Log-Message "Need: $($totalNeededGB + 10) GB free on C:" -Error
                Log-Message "Have: $($script:CDriveInfo.FreeGB) GB" -Error
                return
            }
        } elseif ($selectedStrategy -eq "use_free_boot") {
            if ($script:CDriveInfo.FreeGB -lt ($linuxSizeGB + 10)) {
                Log-Message "Error: Not enough free space on C: to shrink!" -Error
                Log-Message "Need: $($linuxSizeGB + 10) GB free on C:" -Error
                Log-Message "Have: $($script:CDriveInfo.FreeGB) GB" -Error
                return
            }
        } elseif ($selectedStrategy -eq "other_drive") {
            $otherDiskFreeGB = Get-DiskUnallocatedGB -DiskNumber $targetDiskNumber
            $minNeededFreeGB = $bootPartSizeGB + $refindGB + 1
            if ($otherDiskFreeGB -lt $minNeededFreeGB) {
                Log-Message "Error: Not enough unallocated space on Disk $targetDiskNumber!" -Error
                Log-Message "Need: $minNeededFreeGB GB, Have: $otherDiskFreeGB GB" -Error
                return
            }
        } elseif ($selectedStrategy -eq "other_drive_shrink") {
            if (-not $otherDriveShrinkLetter) {
                Log-Message "Error: No partition selected to shrink on Disk $targetDiskNumber!" -Error
                return
            }
            try {
                $shrinkVol = Get-Volume -DriveLetter $otherDriveShrinkLetter -ErrorAction Stop
                $shrinkFreeGB = [math]::Round($shrinkVol.SizeRemaining / 1GB, 2)
                if ($shrinkFreeGB -lt ($otherDriveShrinkAmountGB + 5)) {
                    Log-Message "Error: Not enough free space on ${otherDriveShrinkLetter}: to shrink!" -Error
                    Log-Message "Need: $($otherDriveShrinkAmountGB + 5) GB free, Have: $shrinkFreeGB GB" -Error
                    return
                }
            } catch {
                Log-Message "Error: Cannot access volume ${otherDriveShrinkLetter}: - $_" -Error
                return
            }
        }

        # Download ISO if needed
        if (-not $customRadio.Checked) {
            if (Test-Path $script:IsoPath) {
                Log-Message "Found existing ISO at: $script:IsoPath"

                try {
                    $fileInfo = Get-Item $script:IsoPath
                    $fileSizeGB = [math]::Round($fileInfo.Length / 1GB, 2)
                    Log-Message "Existing ISO size: $fileSizeGB GB"

                    if ($fileInfo.Length -lt 2GB) {
                        Log-Message "Existing ISO appears corrupted (too small)" -Error
                        Log-Message "Deleting corrupted file..." -Error
                        Remove-Item $script:IsoPath -Force

                        Set-Status "Re-downloading $distroName ISO..."
                        if (-not (Download-LinuxISO -Destination $script:IsoPath)) {
                            Log-Message "Failed to download $distroName ISO!" -Error
                            return
                        }
                    } else {
                        if (-not (Verify-ISOChecksum -FilePath $script:IsoPath)) {
                            Log-Message "Existing ISO failed checksum verification" -Error

                            Set-Status "Re-downloading $distroName ISO..."
                            if (-not (Download-LinuxISO -Destination $script:IsoPath)) {
                                Log-Message "Failed to download $distroName ISO!" -Error
                                return
                            }
                        } else {
                            if (-not $distro.IsHybrid) {
                                try {
                                    $testMount = Get-DiskImage -ImagePath $script:IsoPath -ErrorAction Stop
                                    Log-Message "ISO mount test passed"
                                }
                                catch {
                                    Log-Message "Existing ISO appears corrupted (mount test failed)" -Error
                                    Log-Message "Error: $_" -Error

                                    $response = [System.Windows.Forms.MessageBox]::Show(
                                        "The existing ISO file appears to be corrupted. Would you like to re-download it?",
                                        "Corrupted ISO",
                                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                                        [System.Windows.Forms.MessageBoxIcon]::Warning
                                    )

                                    if ($response -eq [System.Windows.Forms.DialogResult]::Yes) {
                                        Remove-Item $script:IsoPath -Force
                                        Set-Status "Re-downloading $distroName ISO..."
                                        if (-not (Download-LinuxISO -Destination $script:IsoPath)) {
                                            Log-Message "Failed to download $distroName ISO!" -Error
                                            return
                                        }
                                    } else {
                                        Log-Message "Preparation cancelled by user" -Error
                                        return
                                    }
                                }
                            } else {
                                Log-Message "ISO mount test skipped ($($distro.Keyword) hybrid ISO format)"
                            }
                        }
                    }
                }
                catch {
                    Log-Message "Error checking existing ISO: $_" -Error
                    return
                }
            } else {
                Set-Status "Downloading $distroName ISO..."
                if (-not (Download-LinuxISO -Destination $script:IsoPath)) {
                    Log-Message "Failed to download $distroName ISO!" -Error
                    return
                }
            }
        }

        # ── Wipe-disk strategy (secondary drives only) ──────────────────────
        if ($selectedStrategy -eq "wipe_disk") {
            # ── power warning dialog ─────────────────────────────────
            $powerConfirm = [System.Windows.Forms.MessageBox]::Show(
                "Keep your computer plugged in!`n`n" +
                "A partition resize is about to begin. Power loss during this process " +
                "could corrupt your partition table.`n`n" +
                "Make sure your computer is connected to AC power before continuing.",
                "Power Requirement Warning",
                [System.Windows.Forms.MessageBoxButtons]::OKCancel,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($powerConfirm -ne [System.Windows.Forms.DialogResult]::OK) {
                return
            }

            Log-Message ""
            Log-Message "== Strategy: wipe & reformat entire disk =="
            Log-Message "Target disk: Disk $targetDiskNumber"

            if ($targetDiskNumber -eq $script:CDriveInfo.DiskNumber) {
                Log-Message "REFUSING to wipe the disk containing Windows!" -Error
                return
            }

            Set-Status "Wiping disk $targetDiskNumber..."
            Log-Message "Clearing all data from Disk $targetDiskNumber..."

            try {
                Clear-Disk -Number $targetDiskNumber -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
                Log-Message "Disk cleared successfully."
            }
            catch {
                Log-Message "Clear-Disk failed: $_" -Error
                Log-Message "Trying diskpart fallback..."

                $diskpartScript = @"
select disk $targetDiskNumber
clean
convert gpt
exit
"@
                $scriptPath = Join-Path $env:TEMP "wipe_disk.txt"
                $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII
                $result = diskpart /s $scriptPath
                Remove-Item $scriptPath -Force

                $resultString = $result -join "`n"
                if ($resultString -notmatch "succeeded|successfully") {
                    Log-Message "Diskpart wipe also failed!" -Error
                    Log-Message $resultString -Error
                    return
                }
                Log-Message "Disk wiped via diskpart."
            }

            Start-Sleep -Seconds 2

            try {
                $diskStatus = Get-Disk -Number $targetDiskNumber
                if ($diskStatus.PartitionStyle -ne "GPT") {
                    Initialize-Disk -Number $targetDiskNumber -PartitionStyle GPT -ErrorAction Stop
                    Log-Message "Disk initialized as GPT."
                }
            } catch {
                Log-Message "Note: GPT initialization: $_"
            }

            Start-Sleep -Seconds 2

            # Create boot partition
            Log-Message "Creating $bootPartSizeGB GB boot partition..."
            Set-Status "Creating boot partition..."
            try {
                $bootPartition = New-Partition -DiskNumber $targetDiskNumber `
                    -Size ([int64]($bootPartSizeGB * 1GB)) `
                    -AssignDriveLetter `
                    -ErrorAction Stop

                Start-Sleep -Seconds 2
                $driveLetter = $bootPartition.DriveLetter
                $bootPartNumber = $bootPartition.PartitionNumber

                if (-not $driveLetter) {
                    $bootPartition | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction SilentlyContinue
                    Start-Sleep -Seconds 2
                    $bootPartition = Get-Partition -DiskNumber $targetDiskNumber -PartitionNumber $bootPartNumber
                    $driveLetter = $bootPartition.DriveLetter
                }

                if ($useExt4Boot) {
                    # Format as ext4 via WSL
                    if (-not (Format-PartitionExt4Wsl -DiskNumber $targetDiskNumber -PartitionNumber $bootPartNumber -Label "LINUX_LIVE")) {
                        throw "Failed to format boot partition as ext4 via WSL"
                    }

                    # Mount ext4 via WSL and set NewDrive to UNC path
                    $script:WslMountInfo = Mount-Ext4PartitionWsl -DiskNumber $targetDiskNumber -PartitionNumber $bootPartNumber
                    if (-not $script:WslMountInfo) {
                        throw "Failed to mount ext4 boot partition via WSL"
                    }
                    $script:NewDrive = $script:WslMountInfo.WinPath
                    $script:VolumeLabel = "LINUX_LIVE"
                    Log-Message "Boot partition created as ext4 (LINUX_LIVE), accessible at $($script:NewDrive)"
                } else {
                    if (-not $driveLetter) {
                        throw "Could not assign a drive letter to the boot partition"
                    }

                    Format-Volume -DriveLetter $driveLetter `
                        -FileSystem FAT32 `
                        -NewFileSystemLabel "LINUX_LIVE" `
                        -Confirm:$false `
                        -ErrorAction Stop

                    Log-Message "Boot partition created as ${driveLetter}: (LINUX_LIVE)"
                    $script:NewDrive = "${driveLetter}:"
                    $script:VolumeLabel = "LINUX_LIVE"
                }
            }
            catch {
                Log-Message "Failed to create boot partition: $_" -Error
                return
            }

            # Create rEFInd partition if enabled (wipe_disk)
            if ($useRefind) {
                Start-Sleep -Seconds 2
                if ($useExt4Boot) {
                    $bootPartInfo = Get-Partition -DiskNumber $targetDiskNumber -PartitionNumber $bootPartNumber
                } else {
                    $bootPartInfo = Get-Partition -DiskNumber $targetDiskNumber |
                        Where-Object { $_.DriveLetter -eq $driveLetter } | Select-Object -First 1
                }
                $refindAfterOffset = $bootPartInfo.Offset + $bootPartInfo.Size
                $script:RefindDriveLetter = New-RefindPartition -DiskNumber $targetDiskNumber -AfterOffset $refindAfterOffset
                if (-not $script:RefindDriveLetter) {
                    Log-Message "Warning: rEFInd partition creation failed. Continuing without rEFInd." -Error
                    $useRefind = $false
                }
            }

            Start-Sleep -Seconds 2
            $diskAfter = Get-Disk -Number $targetDiskNumber
            $partsAfter = Get-Partition -DiskNumber $targetDiskNumber | Sort-Object Offset
            $usedBytes = [int64]0
            foreach ($p in $partsAfter) { $usedBytes += $p.Size }
            $unallocGB = [math]::Round(($diskAfter.Size - $usedBytes) / 1GB, 1)

            Log-Message ""
            Log-Message "Disk $targetDiskNumber wiped and reformatted successfully:"
            Log-Message "  Partition 1: LINUX_LIVE ($bootPartSizeGB GB $bootPartFsType)"
            if ($useRefind -and $script:RefindDriveLetter) {
                Log-Message "  Partition 2: REFIND ($($script:RefindSizeMB) MB, $($script:RefindDriveLetter):)"
            }
            Log-Message "  Unallocated: ~$unallocGB GB (Linux Storage after install)"
            Log-Message ""
        }
        # ── Shrink/free-space strategies ──────────────────────────────────────
        elseif ($selectedStrategy -eq "other_drive_shrink") {
            # ── power warning dialog ────────────────────────────
            $powerConfirm = [System.Windows.Forms.MessageBox]::Show(
                "Keep your computer plugged in!`n`n" +
                "A partition resize is about to begin. Power loss during this process " +
                "could corrupt your partition table.`n`n" +
                "Make sure your computer is connected to AC power before continuing.",
                "Power Requirement Warning",
                [System.Windows.Forms.MessageBoxButtons]::OKCancel,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($powerConfirm -ne [System.Windows.Forms.DialogResult]::OK) {
                return
            }

            Set-Status "Shrinking ${otherDriveShrinkLetter}: partition on Disk $targetDiskNumber..."
            Log-Message "Shrinking ${otherDriveShrinkLetter}: partition by $otherDriveShrinkAmountGB GB..."
            Log-Message "This will create space for Linux: $linuxSizeGB GB and boot partition: $bootPartSizeGB GB ($bootPartFsType)..."

            if (-not (Shrink-Partition -DriveLetter $otherDriveShrinkLetter -ShrinkAmountGB $otherDriveShrinkAmountGB)) {
                return
            }

            Start-Sleep -Seconds 5
        } elseif ($selectedStrategy -ne "use_free_all" -and -not $isOtherDrive) {
            # ── power warning dialog ────────────────────────────
            $powerConfirm = [System.Windows.Forms.MessageBox]::Show(
                "Keep your computer plugged in!`n`n" +
                "A partition resize is about to begin. Power loss during this process " +
                "could corrupt your partition table.`n`n" +
                "Make sure your computer is connected to AC power before continuing.",
                "Power Requirement Warning",
                [System.Windows.Forms.MessageBoxButtons]::OKCancel,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
            if ($powerConfirm -ne [System.Windows.Forms.DialogResult]::OK) {
                return
            }

            $shrinkAmountGB = if ($selectedStrategy -eq "use_free_boot") { $linuxSizeGB } else { $totalNeededGB }

            Set-Status "Shrinking C: partition..."
            Log-Message "Shrinking C: partition by $shrinkAmountGB GB..."

            if ($selectedStrategy -eq "shrink_all") {
                Log-Message "This will create space for Linux: $linuxSizeGB GB and boot partition: $bootPartSizeGB GB ($bootPartFsType)..."
            } else {
                Log-Message "This will create $linuxSizeGB GB of space for Linux installation..."
                Log-Message "The $bootPartSizeGB GB $bootPartFsType boot partition will use existing unallocated space."
            }

            if (-not (Shrink-Partition -DriveLetter 'C' -ShrinkAmountGB $shrinkAmountGB)) {
                return
            }

            Start-Sleep -Seconds 5
        } else {
            if ($isOtherDrive) {
                Log-Message "Skipping C: partition shrink - installing to a separate disk (Disk $targetDiskNumber)."
            } else {
                Log-Message "Skipping C: partition shrink - using existing unallocated space."
            }
        }

        # Create boot partition (skip for wipe_disk -- already created above)
        if ($selectedStrategy -ne "wipe_disk") {
        Set-Status "Creating boot partition..."
        Log-Message "Creating $bootPartSizeGB GB $bootPartFsType boot partition on Disk $targetDiskNumber..."

        try {
            Start-Sleep -Seconds 2
            $disk = Get-Disk -Number $targetDiskNumber
            $partitions = Get-Partition -DiskNumber $targetDiskNumber | Sort-Object Offset

            if (-not $isOtherDrive) {
                $cPartition = Get-Partition -DriveLetter C
                $cPartitionEnd = $cPartition.Offset + $cPartition.Size
                $anchorEnd = $cPartitionEnd
            } elseif ($selectedStrategy -eq "other_drive_shrink" -and $otherDriveShrinkLetter) {
                $shrunkPartition = Get-Partition -DriveLetter $otherDriveShrinkLetter
                $anchorEnd = $shrunkPartition.Offset + $shrunkPartition.Size
            } else {
                if ($partitions -and $partitions.Count -gt 0) {
                    $lastPart = $partitions | Sort-Object Offset | Select-Object -Last 1
                    $anchorEnd = $lastPart.Offset + $lastPart.Size
                } else {
                    $anchorEnd = [int64](1MB)
                }
            }

            # ── Scan ALL unallocated gaps on the disk ────────────────────────
            $gaps = @()
            $sortedParts = $partitions | Sort-Object Offset
            $prevEnd = [int64]0

            foreach ($part in $sortedParts) {
                $gapSize = $part.Offset - $prevEnd
                if ($gapSize -gt 1MB) {
                    $gaps += [PSCustomObject]@{
                        Start = $prevEnd
                        End   = $part.Offset
                        Size  = $gapSize
                    }
                }
                $prevEnd = $part.Offset + $part.Size
            }
            $trailingGap = $disk.Size - $prevEnd
            if ($trailingGap -gt 1MB) {
                $gaps += [PSCustomObject]@{
                    Start = $prevEnd
                    End   = $disk.Size
                    Size  = $trailingGap
                }
            }

            $bootPartitionSize = [int64]($bootPartSizeGB * 1GB)
            $alignmentSize = [int64](1MB)
            $refindReserve = if ($useRefind) { [int64]($script:RefindSizeMB * 1MB) } else { [int64]0 }
            $bufferSize = [int64](16MB) + $refindReserve
            $minGapRequired = $bootPartitionSize + $bufferSize + $alignmentSize

            Log-Message "Scanning disk for unallocated gaps..."
            foreach ($gap in $gaps) {
                $gapGB = [math]::Round($gap.Size / 1GB, 2)
                $gapStartGB = [math]::Round($gap.Start / 1GB, 2)
                Log-Message "  Gap at $gapStartGB GB: $gapGB GB"
            }

            $usableGaps = $gaps | Where-Object { $_.Size -ge $minGapRequired }

            if (-not $usableGaps) {
                throw "No unallocated gap large enough for the $bootPartSizeGB GB boot partition"
            }

            $anchorGap = $usableGaps | Where-Object {
                $_.Start -ge ($anchorEnd - 1MB) -and $_.Start -le ($anchorEnd + 1MB)
            } | Select-Object -First 1

            $chosenGap = if ($anchorGap) { $anchorGap }
                          else {
                              # Fallback: pick largest gap AFTER the anchor partition, not anywhere on disk
                              # This ensures boot partition is placed after Windows/data partitions
                              $usableGapsAfterAnchor = $usableGaps | Where-Object { $_.Start -ge $anchorEnd }
                              if ($usableGapsAfterAnchor) {
                                  $usableGapsAfterAnchor | Sort-Object Size -Descending | Select-Object -First 1
                              } else {
                                  throw "No suitable gap found after the anchor partition (end: $([math]::Round($anchorEnd / 1GB, 2)) GB). Cannot safely place boot partition."
                              }
                          }

            $chosenGapGB = [math]::Round($chosenGap.Size / 1GB, 2)
            $chosenStartGB = [math]::Round($chosenGap.Start / 1GB, 2)
            Log-Message "Selected gap for boot partition: $chosenGapGB GB starting at $chosenStartGB GB"

            $bootPartitionEndOffset = $chosenGap.End - $bufferSize
            $bootPartitionOffset = $bootPartitionEndOffset - $bootPartitionSize
            $bootPartitionOffset = [int64]([Math]::Floor($bootPartitionOffset / $alignmentSize)) * $alignmentSize

            if ($bootPartitionOffset -lt ($chosenGap.Start + $alignmentSize)) {
                throw "Selected gap ($chosenGapGB GB) is too small after alignment for the boot partition"
            }

            $linuxSpace = $bootPartitionOffset - $chosenGap.Start
            $linuxSpaceGB = [math]::Round($linuxSpace / 1GB, 2)

            Log-Message "Unallocated space starts at: $chosenStartGB GB"
            Log-Message "Boot partition will start at: $([math]::Round($bootPartitionOffset / 1GB, 2)) GB"
            Log-Message "Gap ends at: $([math]::Round($chosenGap.End / 1GB, 2)) GB"
            Log-Message "Linux will have $linuxSpaceGB GB of unallocated space"

            Log-Message "Creating boot partition..."

            $bootPartitionSize = [int64]($bootPartSizeGB * 1GB)
            $offsetMB = [int64]([Math]::Floor($bootPartitionOffset / 1MB))
            $sizeMB = [int64]($bootPartSizeGB * 1024)

            if ($offsetMB -lt 0 -or $bootPartitionOffset -gt $disk.Size) {
                throw "Invalid offset calculated: $offsetMB MB (from $bootPartitionOffset bytes)"
            }

            Log-Message "Attempting to create partition at offset: $([math]::Round($bootPartitionOffset / 1GB, 2)) GB - $offsetMB MB"

            $partitionCreated = $false
            $newPartition = $null

            try {
                Log-Message "Attempting PowerShell method with specific offset..."
                $newPartition = New-Partition -DiskNumber $targetDiskNumber `
                    -Offset $bootPartitionOffset `
                    -Size $bootPartitionSize `
                    -AssignDriveLetter `
                    -ErrorAction Stop

                $partitionCreated = $true
                $driveLetter = $newPartition.DriveLetter
                Log-Message "Success! Partition created using PowerShell method"
            }
            catch {
                Log-Message "PowerShell method failed: $_"
                Log-Message "Trying diskpart method..."

                $attempts = @(
                    @{Offset = $offsetMB; Description = "Calculated position"},
                    @{Offset = [int64]($offsetMB - 1024); Description = "1GB before calculated position"},
                    @{Offset = [int64]($offsetMB - 2048); Description = "2GB before calculated position"},
                    @{Offset = [int64]($offsetMB - 5120); Description = "5GB before calculated position"}
                )

                $attempts = $attempts | Where-Object { $_.Offset -gt 0 }

                foreach ($attempt in $attempts) {
                    Log-Message "Attempt: $($attempt.Description)"
                    Log-Message "Trying offset: $([math]::Round($attempt.Offset * 1MB / 1GB, 2)) GB"

                    $diskpartScript = @"
select disk $targetDiskNumber
create partition primary offset=$($attempt.Offset) size=$sizeMB
assign
exit
"@
                    $scriptPath = Join-Path $env:TEMP "create_boot_partition.txt"
                    $diskpartScript | Out-File -FilePath $scriptPath -Encoding ASCII

                    $result = & diskpart /s $scriptPath 2>&1
                    Remove-Item $scriptPath -Force

                    $resultString = $result -join "`n"

                    if ($resultString -match "successfully created" -or $resultString -match "DiskPart successfully created") {
                        Log-Message "Success! Boot partition created at offset $([math]::Round($attempt.Offset * 1MB / 1GB, 2)) GB"
                        $partitionCreated = $true
                        break
                    } else {
                        if ($resultString -match "not enough usable space") {
                            Log-Message "Not enough space at this offset, trying next position..."
                        } else {
                            Log-Message "Failed with error: $($resultString | Select-String -Pattern 'error' -SimpleMatch)"
                        }
                    }
                }
            }

            if (-not $partitionCreated -and -not $isOtherDrive) {
                Log-Message "Offset-based creation failed. Trying alternative approach..."

                $currentPartitions = Get-Partition -DiskNumber $targetDiskNumber | Sort-Object Offset
                $cPartition = $currentPartitions | Where-Object { $_.DriveLetter -eq 'C' }
                $cEndOffset = $cPartition.Offset + $cPartition.Size

                $recoveryPartition = $currentPartitions | Where-Object {
                    $_.Type -eq "Recovery" -or $_.GptType -match "de94bba4"
                } | Sort-Object Offset | Select-Object -First 1

                if ($recoveryPartition) {
                    $gapSize = $recoveryPartition.Offset - $cEndOffset
                    $gapSizeGB = [math]::Round($gapSize / 1GB, 2)
                    Log-Message "Gap between C: and Recovery: $gapSizeGB GB"

                    $fillerSize = [int64]($gapSize - ($bootPartSizeGB * 1GB) - (1GB))
                    $fillerSizeGB = [math]::Round($fillerSize / 1GB, 2)

                    if ($fillerSize -gt 0) {
                        Log-Message "Attempting workaround: Creating filler partition of $fillerSizeGB GB"
                        $fillerPartition = $null

                        try {
                            $fillerPartition = New-Partition -DiskNumber $targetDiskNumber `
                                -Size $fillerSize `
                                -ErrorAction Stop

                            Log-Message "Filler partition created. Now creating boot partition..."

                            $bootPartition = New-Partition -DiskNumber $targetDiskNumber `
                                -Size ($bootPartSizeGB * 1GB) `
                                -AssignDriveLetter `
                                -ErrorAction Stop

                            Log-Message "Removing filler partition..."
                            Remove-Partition -DiskNumber $targetDiskNumber `
                                -PartitionNumber $fillerPartition.PartitionNumber `
                                -Confirm:$false `
                                -ErrorAction Stop

                            Log-Message "Filler partition removed. Boot partition should now be at end."
                            $partitionCreated = $true
                            $newPartition = $bootPartition
                            $driveLetter = $bootPartition.DriveLetter

                            if (-not $driveLetter) {
                                Start-Sleep -Seconds 3
                                $bootPartition = Get-Partition -DiskNumber $targetDiskNumber -PartitionNumber $bootPartition.PartitionNumber
                                $driveLetter = $bootPartition.DriveLetter
                            }
                        }
                        catch {
                            Log-Message "Workaround failed: $_" -Error
                            # Clean up filler partition if it was created
                            if ($fillerPartition) {
                                try {
                                    Log-Message "Cleaning up orphan filler partition..."
                                    Remove-Partition -DiskNumber $targetDiskNumber `
                                        -PartitionNumber $fillerPartition.PartitionNumber `
                                        -Confirm:$false `
                                        -ErrorAction SilentlyContinue
                                } catch {
                                    Log-Message "Warning: Could not remove filler partition. Manual cleanup may be needed." -Error
                                }
                            }
                        }
                    }
                }
            }

            if (-not $partitionCreated) {
                Log-Message "All offset methods failed. Creating partition without specific offset..."
                try {
                    $newPartition = New-Partition -DiskNumber $targetDiskNumber `
                        -Size ($bootPartSizeGB * 1GB) `
                        -AssignDriveLetter `
                        -ErrorAction Stop

                    $driveLetter = $newPartition.DriveLetter
                    $partitionCreated = $true
                    Log-Message "Boot partition created using standard method"
                }
                catch {
                    throw "All partition creation methods failed: $_"
                }
            }

            if ($partitionCreated -and -not $driveLetter) {
                # ── Poll for drive letter assignment ─────────────────────────
                # Windows Storage Management API may delay assigning drive letters.
                # Poll repeatedly instead of relying on a fixed sleep.
                $driveLetter = $null
                $targetSize = [int64]($bootPartSizeGB * 1GB)
                $tolerance = [int64](100MB)

                for ($i = 0; $i -lt 15; $i++) {
                    Start-Sleep -Seconds 1
                    # Force fresh query (bypass API cache)
                    $newPartitions = Get-Partition -DiskNumber $targetDiskNumber |
                        Where-Object { [Math]::Abs($_.Size - $targetSize) -lt $tolerance }

                    $bootPartition = $newPartitions | Sort-Object Offset -Descending | Select-Object -First 1

                    if ($bootPartition -and $bootPartition.DriveLetter) {
                        $driveLetter = $bootPartition.DriveLetter
                        Log-Message "Drive letter assigned: ${driveLetter}: (after $($i+1)s)"
                        break
                    }
                }

                if (-not $driveLetter -and $bootPartition) {
                    Log-Message "Drive letter not auto-assigned, forcing assignment..."
                    try {
                        $bootPartition | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction Stop
                        Start-Sleep -Seconds 2
                        $bootPartition = Get-Partition -DiskNumber $targetDiskNumber -PartitionNumber $bootPartition.PartitionNumber
                        $driveLetter = $bootPartition.DriveLetter
                    } catch {
                        Log-Message "Failed to assign drive letter: $_" -Error
                    }
                }

                if (-not $driveLetter) {
                    throw "Cannot find newly created boot partition or assign drive letter"
                }
            }

            $volumeLabel = "LINUX_LIVE"

            # Get partition number for ext4 or drive letter fallback
            $bootPartNumber = if ($newPartition) { $newPartition.PartitionNumber }
                              elseif ($bootPartition) { $bootPartition.PartitionNumber }
                              else { $null }

            if ($useExt4Boot) {
                # Format as ext4 via WSL
                if (-not $bootPartNumber) {
                    throw "Cannot determine boot partition number for ext4 formatting"
                }
                if (-not (Format-PartitionExt4Wsl -DiskNumber $targetDiskNumber -PartitionNumber $bootPartNumber -Label $volumeLabel)) {
                    throw "Failed to format boot partition as ext4 via WSL"
                }

                # Mount ext4 via WSL and set NewDrive to UNC path
                $script:WslMountInfo = Mount-Ext4PartitionWsl -DiskNumber $targetDiskNumber -PartitionNumber $bootPartNumber
                if (-not $script:WslMountInfo) {
                    throw "Failed to mount ext4 boot partition via WSL"
                }
                $script:NewDrive = $script:WslMountInfo.WinPath
                $script:VolumeLabel = $volumeLabel
                Log-Message "Boot partition created as ext4 (LINUX_LIVE), accessible at $($script:NewDrive)"
            } else {
                if (-not $driveLetter) {
                    throw "Failed to get drive letter for boot partition"
                }

                Log-Message "Formatting boot partition as FAT32..."

                Format-Volume -DriveLetter $driveLetter `
                    -FileSystem FAT32 `
                    -NewFileSystemLabel $volumeLabel `
                    -Confirm:$false `
                    -ErrorAction Stop

                Log-Message "Boot partition created and assigned to ${driveLetter}:"
                $script:NewDrive = "${driveLetter}:"
                $script:VolumeLabel = $volumeLabel
            }

            Log-Message ""
            Log-Message "=== Final Disk Layout (Disk $targetDiskNumber) ==="
            $finalPartitions = Get-Partition -DiskNumber $targetDiskNumber | Sort-Object Offset

            $previousEnd = [int64]0
            foreach ($part in $finalPartitions) {
                $sizeGB = [math]::Round($part.Size / 1GB, 2)
                $offsetGB = [math]::Round($part.Offset / 1GB, 2)
                $endGB = [math]::Round(($part.Offset + $part.Size) / 1GB, 2)

                if ($part.Offset -gt ($previousEnd + 1MB)) {
                    $gapSize = [math]::Round(($part.Offset - $previousEnd) / 1GB, 2)
                    if ($gapSize -gt 0.1) {
                        Log-Message "[Unallocated: $gapSize GB]"
                    }
                }

                $label = if ($part.DriveLetter) { "Drive $($part.DriveLetter):" }
                        elseif ($part.Type -eq "Recovery" -or $part.GptType -match "de94bba4") { "(Recovery)" }
                        elseif ($part.IsSystem) { "(System)" }
                        else { "(No letter)" }

                Log-Message "Partition $($part.PartitionNumber): $label - Size: $sizeGB GB - Location: $offsetGB-$endGB GB"

                $previousEnd = [int64]($part.Offset + $part.Size)
            }

            if ($disk.Size -gt ($previousEnd + 1MB)) {
                $trailingGap = [math]::Round(($disk.Size - $previousEnd) / 1GB, 2)
                if ($trailingGap -gt 0.1) {
                    Log-Message "[Unallocated: $trailingGap GB]"
                }
            }

            Log-Message ""
            Log-Message "Boot partition successfully created!"

            # Create rEFInd partition if enabled (non-wipe strategies)
            if ($useRefind) {
                if ($useExt4Boot -and $bootPartNumber) {
                    $bootPartInfo = Get-Partition -DiskNumber $targetDiskNumber -PartitionNumber $bootPartNumber -ErrorAction SilentlyContinue
                } else {
                    $bootPartInfo = Get-Partition -DiskNumber $targetDiskNumber |
                        Where-Object { $_.DriveLetter -eq $driveLetter } | Select-Object -First 1
                }
                if ($bootPartInfo) {
                    $refindAfterOffset = $bootPartInfo.Offset + $bootPartInfo.Size
                    $script:RefindDriveLetter = New-RefindPartition -DiskNumber $targetDiskNumber -AfterOffset $refindAfterOffset
                    if (-not $script:RefindDriveLetter) {
                        Log-Message "Warning: rEFInd partition creation failed. Continuing without rEFInd." -Error
                        $useRefind = $false
                    }
                } else {
                    Log-Message "Warning: Could not find boot partition to place rEFInd after." -Error
                    $useRefind = $false
                }
            }

            Log-Message "Linux can use the unallocated space for installation"

        }
        catch {
            Log-Message "Failed to create boot partition: $_" -Error
            return
        }
        } # end if ($selectedStrategy -ne "wipe_disk")

        # Mount ISO
        Set-Status "Mounting ISO..."
        Log-Message "Mounting ISO..."

        try {
            if (-not (Test-Path $script:IsoPath)) {
                Log-Message "ISO file not found at: $script:IsoPath" -Error
                return
            }

            $mountResult = Mount-DiskImage -ImagePath $script:IsoPath -StorageType ISO -PassThru -ErrorAction Stop
            Start-Sleep -Seconds 2

            $isoVolume = Get-Volume -DiskImage $mountResult -ErrorAction Stop | Select-Object -First 1

            if (-not $isoVolume) {
                Log-Message "Failed to get volume information from mounted ISO" -Error
                Dismount-DiskImage -ImagePath $script:IsoPath -ErrorAction SilentlyContinue
                return
            }

            $sourceDrive = "$($isoVolume.DriveLetter):"
            Log-Message "ISO mounted at $sourceDrive"

            if (-not $customRadio.Checked) {
                $validationFile = "$sourceDrive\$($distro.ValidationFile)"

                if (-not (Test-Path $validationFile)) {
                    Log-Message "Warning: ISO may not be a valid $distroName image (missing expected files)" -Error

                    $response = [System.Windows.Forms.MessageBox]::Show(
                        "The ISO doesn't appear to be a valid $distroName image. Continue anyway?",
                        "Invalid ISO",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )

                    if ($response -ne [System.Windows.Forms.DialogResult]::Yes) {
                        Dismount-DiskImage -ImagePath $script:IsoPath
                        return
                    }
                }
            } else {
                # ─── Custom ISO validation ─────────────────────────────────────
                $isoSize = (Get-Item $script:IsoPath).Length / 1GB
                if ($isoSize -lt 1.0) {
                    Log-Message "Warning: Custom ISO is only $([math]::Round($isoSize, 2)) GB - likely not a valid Linux image" -Error
                    $response = [System.Windows.Forms.MessageBox]::Show(
                        "The ISO file appears too small ($([math]::Round($isoSize, 2)) GB). Continue anyway?",
                        "Invalid ISO",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    if ($response -ne [System.Windows.Forms.DialogResult]::Yes) {
                        Dismount-DiskImage -ImagePath $script:IsoPath
                        return
                    }
                }

                $bootIndicators = @("isolinux", "boot", "EFI", "casper", "live", "squashfs")
                $foundBootFiles = $false
                foreach ($indicator in $bootIndicators) {
                    if (Test-Path "$sourceDrive\$indicator") {
                        $foundBootFiles = $true
                        break
                    }
                }
                if (-not $foundBootFiles) {
                    Log-Message "Warning: Custom ISO doesn't contain recognizable boot files" -Error
                    $response = [System.Windows.Forms.MessageBox]::Show(
                        "The ISO doesn't appear to be a bootable Linux image. Continue anyway?",
                        "Invalid ISO",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    if ($response -ne [System.Windows.Forms.DialogResult]::Yes) {
                        Dismount-DiskImage -ImagePath $script:IsoPath
                        return
                    }
                }
                Log-Message "Custom ISO validation passed ($([math]::Round($isoSize, 2)) GB)"
            }
        }
        catch {
            Log-Message "Failed to mount ISO: $_" -Error

            $response = [System.Windows.Forms.MessageBox]::Show(
                "Failed to mount the ISO file. It may be corrupted. Would you like to delete it and re-download?",
                "Mount Failed",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Error
            )

            if ($response -eq [System.Windows.Forms.DialogResult]::Yes -and -not $customRadio.Checked) {
                try {
                    Remove-Item $script:IsoPath -Force
                    Log-Message "Deleted corrupted ISO"

                    # Dismount failed ISO before recursive call to prevent double-dismount in finally
                    Dismount-DiskImage -ImagePath $script:IsoPath -ErrorAction SilentlyContinue

                    Set-Status "Re-downloading $distroName ISO..."
                    if (Download-LinuxISO -Destination $script:IsoPath) {
                        Start-Installation
                        return
                    }
                } catch {
                    Log-Message "Error handling corrupted ISO: $_" -Error
                }
            }
            return
        }

        # Copy files
        Set-Status "Copying files..."
        Log-Message "Copying $distroName files to $script:NewDrive..."
        Log-Message "This may take 10-20 minutes..."

        try {
            if ($useExt4Boot -and $script:WslMountInfo) {
                # Use WSL cp for ext4 (more reliable than robocopy through UNC)
                $wslMountPath = $script:WslMountInfo.WslPath
                $isoSourceLetter = $sourceDrive.TrimEnd(':').ToLower()
                Log-Message "Copying files via WSL to ext4 partition at $wslMountPath..."
                Set-Status "Copying files via WSL (this may take 10-20 minutes)..."
                $wsResult = & wsl -u root bash -c "cp -a /mnt/$isoSourceLetter/* $wslMountPath/ 2>&1; echo EXIT_CODE=\$?"
                $exitLine = $wsResult | Where-Object { $_ -match "EXIT_CODE=" }
                $wsExitCode = if ($exitLine) { [int]($exitLine -replace "EXIT_CODE=", "") } else { $LASTEXITCODE }
                if ($wsExitCode -ne 0) {
                    $errorLines = $wsResult | Where-Object { $_ -notmatch "EXIT_CODE=" }
                    Log-Message "WSL file copy failed (exit $wsExitCode):" -Error
                    foreach ($el in $errorLines) {
                        Log-Message "  $el" -Error
                    }
                    return
                }
                Log-Message "Files copied successfully via WSL!"
            } else {
                # Standard robocopy for FAT32
                $robocopyArgs = @(
                    $sourceDrive,
                    $script:NewDrive,
                    "/E",
                    "/R:3",
                    "/W:5",
                    "/NP",
                    "/NFL",
                    "/NDL",
                    "/ETA"
                )

                $result = robocopy @robocopyArgs

                if ($LASTEXITCODE -ge 8) {
                    Log-Message "Failed to copy files! Exit code: $LASTEXITCODE" -Error
                    return
                } elseif ($LASTEXITCODE -gt 0) {
                    $exitMessages = @{
                        1 = "One or more files were copied successfully"
                        2 = "Extra files/directories detected - nothing copied"
                        3 = "Files copied AND extra files detected"
                        4 = "Mismatched files/directories detected"
                        5 = "Files copied AND mismatches detected"
                        6 = "Extra files AND mismatches detected"
                        7 = "Files copied, extra files, AND mismatches detected"
                    }
                    $msg = $exitMessages[$LASTEXITCODE]
                    if ($msg) { Log-Message "Robocopy warning (exit $LASTEXITCODE): $msg" }
                }

                Log-Message "Files copied successfully!"

                Log-Message "Removing read-only attributes..."
                Set-Status "Removing read-only attributes..."
                try {
                    Get-ChildItem -Path $script:NewDrive -Recurse -Force -ErrorAction SilentlyContinue |
                        Where-Object { $_.Attributes -band [System.IO.FileAttributes]::ReadOnly } |
                        ForEach-Object {
                            $_.Attributes = $_.Attributes -band (-bnot [System.IO.FileAttributes]::ReadOnly)
                        }
                } catch {
                    Log-Message "Warning: Could not remove all read-only attributes: $_" -Error
                }
            }
        }
        catch {
            Log-Message "Error during file copy: $_" -Error
            return
        }
        finally {
            Dismount-DiskImage -ImagePath $script:IsoPath -ErrorAction SilentlyContinue
        }

        # Fedora-specific: fix volume label in GRUB and isolinux configs
        if ($distro.Keyword -eq "Fedora") {
            Set-Status "Fixing Fedora boot labels..."
            Log-Message "Fixing Fedora volume label references in boot configs..."

            $fedoraLabel = $script:VolumeLabel

            $bootConfigFiles = @()
            $searchPaths = @(
                (Join-Path $script:NewDrive "EFI\BOOT\grub.cfg"),
                (Join-Path $script:NewDrive "EFI\BOOT\BOOT.conf"),
                (Join-Path $script:NewDrive "boot\grub2\grub.cfg"),
                (Join-Path $script:NewDrive "boot\grub\grub.cfg"),
                (Join-Path $script:NewDrive "isolinux\isolinux.cfg"),
                (Join-Path $script:NewDrive "isolinux\grub.conf"),
                (Join-Path $script:NewDrive "syslinux\syslinux.cfg")
            )

            foreach ($cfgPath in $searchPaths) {
                if (Test-Path $cfgPath) {
                    $bootConfigFiles += $cfgPath
                }
            }

            if ($bootConfigFiles.Count -eq 0) {
                Log-Message "Warning: No boot config files found to patch" -Error
            } else {
                $patchedCount = 0
                foreach ($cfgFile in $bootConfigFiles) {
                    try {
                        # Read as bytes to preserve original encoding and line endings
                        $rawBytes = [System.IO.File]::ReadAllBytes($cfgFile)
                        $content = [System.Text.Encoding]::UTF8.GetString($rawBytes)
                        $originalContent = $content

                        # Only replace labels in non-comment lines
                        # Fedora uses LABEL= in kernel parameters and set isolabel=
                        $lines = $content -split "`n"
                        $newLines = @()
                        foreach ($line in $lines) {
                            $trimmed = $line.TrimStart()
                            # Skip comment lines
                            if ($trimmed.StartsWith("#") -or $trimmed.StartsWith(";")) {
                                $newLines += $line
                                continue
                            }
                            # Replace LABEL references in active config lines
                            $line = $line -replace '(root=live:(?:CD)?LABEL=)([^\s\\]+)', "`$1$fedoraLabel"
                            $line = $line -replace '(set\s+isolabel=)([^\s]+)', "`$1$fedoraLabel"
                            $line = $line -replace '(CDLABEL=)([^\s\\]+)', "`$1$fedoraLabel"
                            $newLines += $line
                        }
                        $content = $newLines -join "`n"

                        if ($content -ne $originalContent) {
                            # Write back preserving original line endings
                            [System.IO.File]::WriteAllText($cfgFile, $content, [System.Text.Encoding]::UTF8)
                            Log-Message "  Patched: $(Split-Path -Leaf $cfgFile)"
                            $patchedCount++
                        } else {
                            Log-Message "  No label references in: $(Split-Path -Leaf $cfgFile)"
                        }
                    }
                    catch {
                        Log-Message "  Warning: Could not patch $($cfgFile): $_" -Error
                    }
                }

                if ($patchedCount -gt 0) {
                    Log-Message "Patched $patchedCount boot config file(s) with label '$fedoraLabel'"
                } else {
                    Log-Message "Warning: No LABEL references found to patch. Fedora may not boot correctly." -Error
                    Log-Message "You may need to manually edit EFI\BOOT\grub.cfg and replace the LABEL= value with '$fedoraLabel'" -Error
                }
            }
        }

        # CachyOS/Arch-specific: fix archisolabel in GRUB, syslinux, and loader configs
        if ($distro.Keyword -eq "CachyOS") {
            Set-Status "Fixing CachyOS boot labels..."
            Log-Message "Fixing CachyOS volume label references in boot configs..."

            $cachyLabel = $script:VolumeLabel

            $bootConfigFiles = @()
            $searchPaths = @(
                (Join-Path $script:NewDrive "EFI\BOOT\grub.cfg"),
                (Join-Path $script:NewDrive "boot\grub\grub.cfg"),
                (Join-Path $script:NewDrive "syslinux\archiso_sys-linux.cfg"),
                (Join-Path $script:NewDrive "syslinux\archiso_pxe-linux.cfg"),
                (Join-Path $script:NewDrive "syslinux\archiso_sys.cfg"),
                (Join-Path $script:NewDrive "syslinux\archiso_pxe.cfg"),
                (Join-Path $script:NewDrive "syslinux\syslinux.cfg")
            )

            foreach ($cfgPath in $searchPaths) {
                if (Test-Path $cfgPath) {
                    $bootConfigFiles += $cfgPath
                }
            }

            # Also check systemd-boot loader entries
            $loaderDir = Join-Path $script:NewDrive "loader\entries"
            if (Test-Path $loaderDir) {
                $loaderConfFiles = Get-ChildItem -Path $loaderDir -Filter "*.conf" -ErrorAction SilentlyContinue
                foreach ($lf in $loaderConfFiles) {
                    $bootConfigFiles += $lf.FullName
                }
            }

            if ($bootConfigFiles.Count -eq 0) {
                Log-Message "Warning: No boot config files found to patch" -Error
            } else {
                $patchedCount = 0
                foreach ($cfgFile in $bootConfigFiles) {
                    try {
                        $rawBytes = [System.IO.File]::ReadAllBytes($cfgFile)
                        $content = [System.Text.Encoding]::UTF8.GetString($rawBytes)
                        $originalContent = $content

                        $lines = $content -split "`n"
                        $newLines = @()
                        foreach ($line in $lines) {
                            $trimmed = $line.TrimStart()
                            if ($trimmed.StartsWith("#") -or $trimmed.StartsWith(";")) {
                                $newLines += $line
                                continue
                            }
                            $line = $line -replace '(archiso(?:search)?label=)([^\s\\]+)', "`$1$cachyLabel"
                            $line = $line -replace '(archisodevice=/dev/disk/by-label/)([^\s\\]+)', "`$1$cachyLabel"
                            $line = $line -replace "(search\s+[^\r\n]*?--(?:label|fs-label)\s+)(\S+)", "`$1$cachyLabel"
                            $newLines += $line
                        }
                        $content = $newLines -join "`n"

                        if ($content -ne $originalContent) {
                            [System.IO.File]::WriteAllText($cfgFile, $content, [System.Text.Encoding]::UTF8)
                            Log-Message "  Patched: $(Split-Path -Leaf $cfgFile)"
                            $patchedCount++
                        } else {
                            Log-Message "  No label references in: $(Split-Path -Leaf $cfgFile)"
                        }
                    }
                    catch {
                        Log-Message "  Warning: Could not patch $($cfgFile): $_" -Error
                    }
                }

                if ($patchedCount -gt 0) {
                    Log-Message "Patched $patchedCount boot config file(s) with label '$cachyLabel'"
                } else {
                    Log-Message "Warning: No archisolabel references found to patch. CachyOS may not boot correctly." -Error
                    Log-Message "You may need to manually edit the boot config files and replace archisolabel= with '$cachyLabel'" -Error
                }
            }
        }

        # Install rEFInd if enabled
        if ($useRefind -and $script:RefindDriveLetter) {
            if ($useExt4Boot) {
                $refindInstalled = Install-Refind `
                    -RefindDriveLetter $script:RefindDriveLetter `
                    -BootDrivePath $script:NewDrive `
                    -DistroLabel $distroName
            } else {
                $bootDriveLetter = $script:NewDrive.TrimEnd(':')
                $refindInstalled = Install-Refind `
                    -RefindDriveLetter $script:RefindDriveLetter `
                    -BootDriveLetter $bootDriveLetter `
                    -DistroLabel $distroName
            }
            if (-not $refindInstalled) {
                Log-Message "Warning: rEFInd installation failed. Falling back to direct boot." -Error
                $useRefind = $false
            }
        }

        # Create boot configuration
        Set-Status "Creating boot configuration..."
        Log-Message "Creating boot configuration..."

        $efiPath = $script:NewDrive + "\EFI\BOOT"
        if (-not (Test-Path $efiPath)) {
            New-Item -Path $efiPath -ItemType Directory -Force
        }

        # For wipe_disk on a secondary drive: install the bootloader into the
        # Windows ESP so the firmware can boot it. (Skip if rEFInd handles booting.)
        $script:WipeBootInstalled = $false
        if ($selectedStrategy -eq "wipe_disk" -and -not ($useRefind -and $script:RefindDriveLetter)) {
            try {
                Log-Message "Installing bootloader into Windows ESP..."
                Set-Status "Installing bootloader into Windows ESP..."

                $winEspPart = Get-Partition -DiskNumber $script:CDriveInfo.DiskNumber |
                    Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' } |
                    Select-Object -First 1

                if (-not $winEspPart) {
                    throw "Could not find Windows EFI System Partition"
                }

                $winEspLetter = $winEspPart.DriveLetter
                $removeLetter = $false
                if (-not $winEspLetter) {
                    $winEspPart | Add-PartitionAccessPath -AssignDriveLetter -ErrorAction Stop
                    Start-Sleep -Seconds 2
                    $winEspPart = Get-Partition -DiskNumber $winEspPart.DiskNumber -PartitionNumber $winEspPart.PartitionNumber
                    $winEspLetter = $winEspPart.DriveLetter
                    $removeLetter = $true
                }

                if (-not $winEspLetter) {
                    throw "Could not assign drive letter to Windows ESP"
                }

                $winEspDrive = "${winEspLetter}:"
                Log-Message "Windows ESP mounted at $winEspDrive"

                $safeName = ($distroName -replace '[^a-zA-Z0-9]', '').Trim()
                if (-not $safeName) { $safeName = "Linux" }
                $script:WipeEspDistroDir = "\EFI\$safeName"
                $distroEspDir = "$winEspDrive$($script:WipeEspDistroDir)"
                New-Item -Path $distroEspDir -ItemType Directory -Force | Out-Null

                $sourceEfi = $script:NewDrive + "\EFI\BOOT"
                if (Test-Path $sourceEfi) {
                    robocopy $sourceEfi $distroEspDir /E /R:2 /W:2 /NP /NFL /NDL | Out-Null
                    Log-Message "EFI\BOOT directory copied to $distroEspDir"
                } else {
                    throw "No EFI\BOOT directory found on $($script:NewDrive)"
                }

                foreach ($grubDir in @("boot\grub", "boot\grub2")) {
                    $srcGrub = Join-Path $script:NewDrive $grubDir
                    if (Test-Path $srcGrub) {
                        $dstGrub = Join-Path $distroEspDir $grubDir
                        New-Item -Path $dstGrub -ItemType Directory -Force | Out-Null
                        robocopy $srcGrub $dstGrub /E /R:2 /W:2 /NP /NFL /NDL | Out-Null
                        Log-Message "Copied $grubDir to ESP"
                    }
                }

                $liveLabel = $script:VolumeLabel
                Log-Message "Patching boot configs in ESP to use label '$liveLabel'..."

                $cfgFiles = Get-ChildItem -Path $distroEspDir -Recurse -Include "*.cfg","*.conf" -ErrorAction SilentlyContinue
                $patchedCount = 0
                foreach ($cfgFile in $cfgFiles) {
                    try {
                        $content = Get-Content $cfgFile.FullName -Raw -ErrorAction Stop
                        $original = $content

                        $content = $content -replace "(search\s+[^`n]*(?:--label|-l)\s+')[^']+(')", "`$1$liveLabel`$2"
                        $content = $content -replace '(search\s+[^\n]*(?:--label|-l)\s+")([^"]+)(")', "`$1$liveLabel`$3"
                        $content = $content -replace "(search\s+[^`n]*(?:--label|-l)\s+)(\S+)(\s)", "`$1$liveLabel`$3"

                        $content = $content -replace '(root=live:(?:CD)?LABEL=)([^\s\\]+)', "`$1$liveLabel"
                        $content = $content -replace '(set isolabel=)([^\s]+)', "`$1$liveLabel"
                        $content = $content -replace '(CDLABEL=)([^\s\\]+)', "`$1$liveLabel"

                        $content = $content -replace '(LABEL=)([^\s\\]+)', "`$1$liveLabel"

                        if ($content -ne $original) {
                            Set-Content -Path $cfgFile.FullName -Value $content -Encoding UTF8 -Force
                            $patchedCount++
                        }
                    } catch {
                        Log-Message "  Warning: Could not patch $($cfgFile.Name): $_" -Error
                    }
                }
                Log-Message "Patched $patchedCount config file(s) in ESP"

                $script:WipeEfiName = "BOOTx64.EFI"
                foreach ($candidate in @("shimx64.efi", "grubx64.efi")) {
                    if (Test-Path "$distroEspDir\$candidate") {
                        $script:WipeEfiName = $candidate
                        break
                    }
                }
                Log-Message "Boot binary: $($script:WipeEfiName)"

                $script:WipeWinEspDrive = $winEspDrive
                $script:WipeBootInstalled = $true

                if ($removeLetter -and $winEspLetter) {
                    $script:WipeEspRemoveLetter = $true
                    $script:WipeEspLetter = $winEspLetter
                    $script:WipeEspPartition = $winEspPart
                } else {
                    $script:WipeEspRemoveLetter = $false
                }

                Log-Message "Bootloader installed to Windows ESP at $($script:WipeEspDistroDir)"
            } catch {
                Log-Message "Failed to install bootloader to Windows ESP: $_" -Error
                Log-Message "You may need to configure boot manually in UEFI/BIOS settings" -Error
            }
        }

        if ($autoRestartCheck.Checked) {
            Log-Message "Configuring UEFI boot priority..."
            Set-Status "Configuring UEFI boot priority..."

            try {
                if ($useRefind -and $script:RefindDriveLetter) {
                    # rEFInd boot entry - point to the rEFInd partition
                    Log-Message "Creating UEFI boot entry for rEFInd..."
                    $refindDrive = "$($script:RefindDriveLetter):"
                    $bootCreated = New-UefiBootEntry -DistroName "rEFInd - QuickLinux" `
                        -DevicePartition $refindDrive -EfiPath "\EFI\BOOT\BOOTx64.EFI"

                    if ($bootCreated) {
                        Log-Message "rEFInd UEFI boot entry created and set as default!"
                    } else {
                        Log-Message "Could not create rEFInd boot entry automatically" -Error
                        Log-Message "You will need to select 'rEFInd - QuickLinux' manually in UEFI/BIOS boot menu" -Error
                    }
                } else {
                    # Standard boot entry (no rEFInd)
                    $bcdeditOutput = bcdedit /enum firmware 2>&1
                    $lines = $bcdeditOutput

                    $bootEntries = @()
                    $currentEntry = $null

                    foreach ($line in $lines) {
                        if ($line -match '^Firmware Application \(') {
                            if ($currentEntry) {
                                $bootEntries += $currentEntry
                            }
                            $currentEntry = @{}
                        }
                        elseif ($line -match '^identifier\s+(.+)$') {
                            if ($currentEntry) {
                                $currentEntry.ID = $matches[1].Trim()
                            }
                        }
                        elseif ($line -match '^description\s+(.+)$') {
                            if ($currentEntry) {
                                $currentEntry.Description = $matches[1].Trim()
                            }
                        }
                    }
                    if ($currentEntry) {
                        $bootEntries += $currentEntry
                    }

                    Log-Message "Found $($bootEntries.Count) firmware boot entries:"
                    foreach ($entry in $bootEntries) {
                        Log-Message "  $($entry.Description) [$($entry.ID)]"
                    }

                    $distroKeyword = $distro.Keyword

                    $targetEntry = $null

                    $targetEntry = $bootEntries | Where-Object { $_.Description -like "*$distroKeyword*" } | Select-Object -First 1
                    if ($targetEntry) {
                        Log-Message "Found existing boot entry for '$distroKeyword'"
                    }

                    if (-not $targetEntry) {
                        $targetEntry = $bootEntries | Where-Object { $_.Description -like '*UEFI OS*' } | Select-Object -First 1
                        if ($targetEntry) {
                            Log-Message "Found generic 'UEFI OS' boot entry"
                        }
                    }

                    if ($targetEntry) {
                        Log-Message "Setting boot priority to: $($targetEntry.Description) [$($targetEntry.ID)]"

                        $process = Start-Process -FilePath "bcdedit.exe" `
                            -ArgumentList "/set", "{fwbootmgr}", "default", $targetEntry.ID `
                            -Wait -PassThru -NoNewWindow

                        if ($process.ExitCode -eq 0) {
                            Log-Message "UEFI boot priority set successfully!"
                        } else {
                            Log-Message "bcdedit /set default returned exit code $($process.ExitCode)" -Error
                        }
                    } else {
                        Log-Message "No existing boot entry found for $distroName"
                        Log-Message "Creating new UEFI firmware boot entry..."
                        $bootCreated = $false

                        if ($script:WipeBootInstalled) {
                            Log-Message "Creating firmware boot entry (Windows ESP)..."
                            $wipeEfiPath = "$($script:WipeEspDistroDir)\$($script:WipeEfiName)"
                            $bootCreated = New-UefiBootEntry -DistroName $distroName `
                                -DevicePartition $script:WipeWinEspDrive -EfiPath $wipeEfiPath

                            # Clean up ESP drive letter if we assigned it
                            if ($script:WipeEspRemoveLetter -and $script:WipeEspLetter) {
                                $script:WipeEspPartition | Remove-PartitionAccessPath -AccessPath "$($script:WipeEspLetter):\" -ErrorAction SilentlyContinue
                            }
                        } else {
                            $bootDeviceDrive = $script:NewDrive
                            Log-Message "Boot entry will point to partition: $bootDeviceDrive"
                            Log-Message "Attempting bcdedit /copy method..."
                            $bootCreated = New-UefiBootEntry -DistroName $distroName `
                                -DevicePartition $bootDeviceDrive -EfiPath "\EFI\BOOT\BOOTx64.EFI"
                        }

                        if (-not $bootCreated) {
                            Log-Message "Could not create UEFI boot entry automatically" -Error
                            Log-Message "You will need to set boot priority manually in UEFI/BIOS settings" -Error
                            Log-Message "Or use the one-time boot menu (usually F12) to select the $distroName partition" -Error
                        }
                    }
                }
            }
            catch {
                Log-Message "Error configuring UEFI boot: $_" -Error
                Log-Message "You may need to set boot priority manually in UEFI/BIOS settings" -Error
            }
        }

        # Success
        Log-Message "====================================="
        Log-Message "Preparation Complete!"
        Log-Message "====================================="
        Log-Message "$distroName boot partition created ($bootPartFsType) at $script:NewDrive"
        if ($customRadio.Checked) {
            Log-Message "ISO used: $(Split-Path -Leaf $script:CustomIsoPath)"
        }
        Log-Message ""
        Log-Message "*** DISK LAYOUT ***"
        $finalPartitions = Get-Partition -DiskNumber $targetDiskNumber | Sort-Object Offset
        foreach ($part in $finalPartitions) {
            $sizeGB = [math]::Round($part.Size / 1GB, 2)
            $label = if ($part.DriveLetter) { "Drive $($part.DriveLetter)" }
                    elseif ($part.Type -eq "Recovery" -or $part.GptType -match "de94bba4") { "Recovery" }
                    elseif ($part.IsSystem) { "System" }
                    else { "No letter" }
            Log-Message "- ${label}: $sizeGB GB"
        }
        Log-Message ""
        Log-Message "The unallocated space is ready for $distroName installation."
        Log-Message "The installer will automatically detect and use this space."
        Log-Message ""

        if ($useRefind -and $script:RefindDriveLetter) {
            Log-Message ""
            Log-Message "rEFInd boot manager has been installed and set as the default UEFI boot entry."
            Log-Message ""
        }

        if ($autoRestartCheck.Checked) {
            Log-Message "*** AUTOMATIC RESTART ENABLED ***"
            Log-Message "UEFI boot priority has been configured."
            Log-Message "The system will restart in 30 seconds!"
            if ($useRefind -and $script:RefindDriveLetter) {
                Log-Message "After restart, rEFInd should appear automatically and show `"$distroName`"."
            } else {
                Log-Message "After restart, the system will boot into $distroName"
            }
            Log-Message ""
        } else {
            if ($useRefind -and $script:RefindDriveLetter) {
                Log-Message "To boot ${distroName}:"
                Log-Message "1. Restart your computer"
                Log-Message "2. rEFInd should appear automatically and show `"$distroName`""
                Log-Message "3. If rEFInd doesn't appear, enter UEFI/BIOS (F2/F10/F12/DEL)"
                Log-Message "   and select `"rEFInd - QuickLinux`" from the boot menu"
                Log-Message "4. Disable Secure Boot if needed"
            } else {
                Log-Message "To boot $distroName, use the UEFI boot menu:"
                Log-Message "1. Restart your computer"
                Log-Message "2. Press F2, F10, F12, DEL, or ESC during startup"
                Log-Message "3. Select the $distroName entry"
                Log-Message "4. Make sure Secure Boot is disabled"
            }
            Log-Message ""
        }

        Set-Status "Ready to boot live Linux install environment"

        # Delete ISO if requested
        if ($deleteIsoCheck.Checked -and -not $customRadio.Checked) {
            try {
                Remove-Item $script:IsoPath -Force
                Log-Message "ISO file deleted."
                $script:IsoDownloaded = $false
            }
            catch {
                Log-Message "Could not delete ISO file."
            }
        }

        # Reset ISO state for next run
        if ($deleteIsoCheck.Checked -and -not $customRadio.Checked) {
            $script:IsoDownloaded = $false
            $isoStatus.Text = "Status: ISO deleted after preparation"
            $downloadButton.BackColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
            $downloadButton.ForeColor = [System.Drawing.Color]::White
            $downloadButton.Enabled = $true
            $prepareButton.Enabled = $false
        } else {
            $script:IsoDownloaded = $false
            $distro = Get-SelectedDistro
            $isoStatus.Text = "Status: $distro.Name ISO cached - click 'Download ISO' to re-download"
            $downloadButton.BackColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
            $downloadButton.ForeColor = [System.Drawing.Color]::White
            $downloadButton.Enabled = $true
            $prepareButton.Enabled = $false
        }

        # Auto-restart if enabled
        if ($autoRestartCheck.Checked) {
            Log-Message ""
            Log-Message "Preparing for automatic restart..."

            $countdownForm = New-Object System.Windows.Forms.Form
            $countdownForm.Text = "System Restart"
            $countdownForm.Size = New-Object System.Drawing.Size(420, 250)
            $countdownForm.StartPosition = "CenterScreen"
            $countdownForm.FormBorderStyle = "FixedDialog"
            $countdownForm.MaximizeBox = $false
            $countdownForm.MinimizeBox = $false

            $countdownLabel = New-Object System.Windows.Forms.Label
            $countdownLabel.Text = "System will restart in $script:CountdownSeconds seconds...`n`nYour computer will boot into the $distroName live session.`nFrom there, run the installer to complete the installation."
            $countdownLabel.Font = New-Object System.Drawing.Font("Segoe UI", 10)
            $countdownLabel.Location = New-Object System.Drawing.Point(20, 20)
            $countdownLabel.Size = New-Object System.Drawing.Size(380, 90)
            $countdownLabel.TextAlign = "MiddleCenter"
            $countdownForm.Controls.Add($countdownLabel)

            $script:CancelRestart = $false
            $script:RestartNow = $false

            $restartNowButton = New-Object System.Windows.Forms.Button
            $restartNowButton.Text = "Restart Now"
            $restartNowButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
            $restartNowButton.Location = New-Object System.Drawing.Point(40, 120)
            $restartNowButton.Size = New-Object System.Drawing.Size(150, 35)
            $restartNowButton.BackColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
            $restartNowButton.ForeColor = [System.Drawing.Color]::White
            $restartNowButton.FlatStyle = "Flat"
            $countdownForm.Controls.Add($restartNowButton)

            $cancelButton = New-Object System.Windows.Forms.Button
            $cancelButton.Text = "Cancel Restart"
            $cancelButton.Font = New-Object System.Drawing.Font("Segoe UI", 10)
            $cancelButton.Location = New-Object System.Drawing.Point(210, 120)
            $cancelButton.Size = New-Object System.Drawing.Size(150, 35)
            $countdownForm.Controls.Add($cancelButton)

            $restartNowButton.Add_Click({
                $script:RestartNow = $true
                $countdownForm.Close()
            })

            $cancelButton.Add_Click({
                $script:CancelRestart = $true
                $countdownForm.Close()
            })

            $timer = New-Object System.Windows.Forms.Timer
            $timer.Interval = 1000

            $timer.Add_Tick({
                $script:CountdownSeconds--
                $countdownLabel.Text = "System will restart in $script:CountdownSeconds seconds...`n`nYour computer will boot into the $distroName live session.`nFrom there, run the installer to complete the installation."

                if ($script:CountdownSeconds -le 0) {
                    $timer.Stop()
                    $countdownForm.Close()
                }
            })

            $timer.Start()
            $countdownForm.ShowDialog()
            $timer.Stop()

            if ($script:RestartNow -or -not $script:CancelRestart) {
                Log-Message "Restarting system..."
                Start-Sleep -Seconds 2
                Restart-Computer -Force
            } else {
                Log-Message "Restart cancelled by user"
                Log-Message "You can restart manually when ready"
            }
        }
    }
    catch {
        Log-Message "Preparation error: $_" -Error
        Set-Status "Preparation failed!"

        # ── Attempt cleanup of partial state ─────────────────────────────────
        Log-Message "Attempting to clean up partial installation state..."
        try {
            # Dismount ISO if still mounted
            if ($script:IsoPath -and (Get-DiskImage -ImagePath $script:IsoPath -ErrorAction SilentlyContinue).IsAttached) {
                Dismount-DiskImage -ImagePath $script:IsoPath -ErrorAction SilentlyContinue
                Log-Message "Dismounted ISO"
            }
        } catch {}

        try {
            # Remove rEFInd partition if it was created but installation failed
            if ($useRefind -and $script:RefindPartitionNumber -and $targetDiskNumber) {
                Log-Message "Removing rEFInd partition (installation failed)..."
                Remove-Partition -DiskNumber $targetDiskNumber `
                    -PartitionNumber $script:RefindPartitionNumber `
                    -Confirm:$false `
                    -ErrorAction SilentlyContinue
            }
        } catch {}

        try {
            # Remove boot partition if it was created but installation failed
            if ($script:NewDrive) {
                try {
                    $vol = Get-Volume -DriveLetter $script:NewDrive.TrimEnd('\').TrimEnd(':') -ErrorAction SilentlyContinue
                    if ($vol) {
                        $part = Get-PartitionFresh -DiskNumber $targetDiskNumber -PartitionNumber $vol.DriveLetter
                        if ($part -and $part.GptType -notmatch "basic_data") {
                            Log-Message "Removing boot partition (installation failed)..."
                            Remove-Partition -DiskNumber $targetDiskNumber `
                                -PartitionNumber $part.PartitionNumber `
                                -Confirm:$false `
                                -ErrorAction SilentlyContinue
                        }
                    }
                } catch {}
            }
        } catch {}

        Log-Message "Cleanup complete. You may retry the installation."
        Log-Message "NOTE: If partitions remain on disk, use Disk Management to remove them manually."
    }
    finally {
        # Clean up WSL mount if ext4 boot was used
        if ($script:WslMountInfo) {
            Dismount-Ext4PartitionWsl -PhysDrive $script:WslMountInfo.PhysDrive
            $script:WslMountInfo = $null
        }
        $script:IsRunning = $false
        $script:CancelRequested = $false
        Set-UILocked $false
    }
}
