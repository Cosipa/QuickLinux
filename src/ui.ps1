function Show-MissingConfigDialog {
    $cfgForm = New-Object System.Windows.Forms.Form
    $cfgForm.Text = "QuickLinux - Configuration Error"
    $cfgForm.Size = New-Object System.Drawing.Size(440, 240)
    $cfgForm.StartPosition = "CenterScreen"
    $cfgForm.FormBorderStyle = "FixedDialog"
    $cfgForm.MaximizeBox = $false
    $cfgForm.MinimizeBox = $false
    $cfgForm.TopMost = $true

    $iconLabel = New-Object System.Windows.Forms.Label
    $iconLabel.Text = [char]0x26A0
    $iconLabel.Font = New-Object System.Drawing.Font("Segoe UI", 36)
    $iconLabel.ForeColor = [System.Drawing.Color]::FromArgb(255, 165, 0)
    $iconLabel.Location = New-Object System.Drawing.Point(15, 20)
    $iconLabel.Size = New-Object System.Drawing.Size(50, 50)
    $iconLabel.TextAlign = "MiddleCenter"
    $cfgForm.Controls.Add($iconLabel)

    $msgLabel = New-Object System.Windows.Forms.Label
    $msgLabel.Text = "Could not load distro configuration.`n`n" +
        "This script requires distro data from the QuickLinux repository.`n`n" +
        "Possible causes:`n" +
        "  - Running as a standalone file without distros.json`n" +
        "  - No internet connection to download config`n`n" +
        "Please download the full package from GitHub."
    $msgLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $msgLabel.Location = New-Object System.Drawing.Point(70, 15)
    $msgLabel.Size = New-Object System.Drawing.Size(350, 130)
    $cfgForm.Controls.Add($msgLabel)

    $openButton = New-Object System.Windows.Forms.Button
    $openButton.Text = "Open GitHub"
    $openButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $openButton.Location = New-Object System.Drawing.Point(70, 155)
    $openButton.Size = New-Object System.Drawing.Size(130, 32)
    $openButton.BackColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
    $openButton.ForeColor = [System.Drawing.Color]::White
    $openButton.FlatStyle = "Flat"
    $openButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $cfgForm.Controls.Add($openButton)

    $exitButton = New-Object System.Windows.Forms.Button
    $exitButton.Text = "Exit"
    $exitButton.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $exitButton.Location = New-Object System.Drawing.Point(220, 155)
    $exitButton.Size = New-Object System.Drawing.Size(130, 32)
    $exitButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $cfgForm.Controls.Add($exitButton)

    $cfgForm.AcceptButton = $openButton
    $cfgForm.CancelButton = $exitButton

    return $cfgForm.ShowDialog()
}
function Log-Message {
    param(
        [string]$Message,
        [switch]$Error
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $fullMessage = "[$timestamp] $Message"

    $logBox.AppendText("$fullMessage`r`n")
    $logBox.SelectionStart = $logBox.TextLength
    $logBox.ScrollToCaret()

    if ($Error) {
        Write-Host $fullMessage -ForegroundColor Red
    } else {
        Write-Host $fullMessage
    }
}
function Set-Status {
    param([string]$Status)
    $statusLabel.Text = $Status
    $form.Refresh()
}
function Show-ISOFoundDialog {
    param([string]$DistroName, [double]$SizeGB)

    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = "ISO File Found"
    $dlg.Size = New-Object System.Drawing.Size(480, 260)
    $dlg.StartPosition = "CenterScreen"
    $dlg.FormBorderStyle = "FixedDialog"
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.TopMost = $true

    $msgLabel = New-Object System.Windows.Forms.Label
    $msgLabel.Text = "A $DistroName ISO file ($([math]::Round($SizeGB, 1)) GB) was found on your computer.`n`n" +
        "You can either:`n" +
        "  - Verify the file's integrity and use it to prepare your boot partition`n" +
        "  - Keep the file and choose a different distribution instead`n`n" +
        "Verifying the file checks that it was downloaded correctly and has not been corrupted. This only takes a few seconds."
    $msgLabel.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $msgLabel.Location = New-Object System.Drawing.Point(20, 15)
    $msgLabel.Size = New-Object System.Drawing.Size(440, 130)
    $dlg.Controls.Add($msgLabel)

    $verifyButton = New-Object System.Windows.Forms.Button
    $verifyButton.Text = "Verify & Use This File"
    $verifyButton.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $verifyButton.Location = New-Object System.Drawing.Point(40, 160)
    $verifyButton.Size = New-Object System.Drawing.Size(190, 35)
    $verifyButton.BackColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
    $verifyButton.ForeColor = [System.Drawing.Color]::White
    $verifyButton.FlatStyle = "Flat"
    $verifyButton.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $dlg.Controls.Add($verifyButton)

    $chooseButton = New-Object System.Windows.Forms.Button
    $chooseButton.Text = "Choose Different Distro"
    $chooseButton.Font = New-Object System.Drawing.Font("Segoe UI", 9)
    $chooseButton.Location = New-Object System.Drawing.Point(250, 160)
    $chooseButton.Size = New-Object System.Drawing.Size(190, 35)
    $chooseButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.Controls.Add($chooseButton)

    $dlg.AcceptButton = $verifyButton
    $dlg.CancelButton = $chooseButton

    return $dlg.ShowDialog()
}
function Verify-ISOIntegrity {
    param([string]$IsoPath)
    return Verify-ISOChecksum -FilePath $IsoPath
}

function Update-ISOStatus {
    if ($customRadio.Checked) {
        if ($script:CustomIsoPath -and (Test-Path $script:CustomIsoPath)) {
            $fileInfo = Get-Item $script:CustomIsoPath
            $fileSizeGB = [math]::Round($fileInfo.Length / 1GB, 2)
            $isoStatus.Text = "Status: Custom ISO selected ($fileSizeGB GB)"
            $downloadButton.Enabled = $false
            $prepareButton.Enabled = $true
            $script:IsoPath = $script:CustomIsoPath
            $script:IsoDownloaded = $true
        } else {
            $isoStatus.Text = "Status: No custom ISO selected"
            $downloadButton.Enabled = $false
            $prepareButton.Enabled = $false
            $script:IsoDownloaded = $false
        }
        return
    }

    $result = Check-ISOExists

    if ($result.State -eq "found") {
        # Show dialog to user
        $choice = Show-ISOFoundDialog -DistroName $result.DistroName -SizeGB $result.SizeGB

        if ($choice -eq [System.Windows.Forms.DialogResult]::OK) {
            # User chose "Verify & Use" - run checksum
            Log-Message "Verifying ISO integrity..."
            Set-Status "Verifying ISO integrity..."
            $form.Refresh()

            if (Verify-ISOIntegrity -IsoPath $result.Path) {
                Log-Message "ISO integrity verified."
                $script:IsoPath = $result.Path
                $script:IsoDownloaded = $true
                Set-Status "ISO verified - click 'Prepare Boot' to continue"
                $isoStatus.Text = "Status: ISO verified - proceed with Step 2"
                $downloadButton.BackColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
                $downloadButton.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
                $downloadButton.Enabled = $false
                $prepareButton.Enabled = $true
            } else {
                Log-Message "ISO integrity check failed - file may be corrupted." -Error
                Remove-Item $result.Path -Force -ErrorAction SilentlyContinue
                $script:IsoDownloaded = $false
                Set-Status "ISO corrupted - deleted. Click 'Download ISO'."
                $isoStatus.Text = "Status: ISO corrupted, deleted. Click 'Download ISO'."
                $downloadButton.BackColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
                $downloadButton.ForeColor = [System.Drawing.Color]::White
                $downloadButton.Enabled = $true
                $prepareButton.Enabled = $false
            }
        } else {
            # User chose "Choose Different" - keep ISO, don't enable anything
            Log-Message "Keeping existing ISO, waiting for user to choose distro."
            Set-Status "Ready - download an ISO or use a custom one"
            $script:IsoDownloaded = $false
            $isoStatus.Text = "Status: $result.DistroName ISO found - click 'Download ISO' to download"
            $downloadButton.BackColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
            $downloadButton.ForeColor = [System.Drawing.Color]::White
            $downloadButton.Enabled = $true
            $prepareButton.Enabled = $false
        }
    } else {
        Set-Status "Ready - download an ISO or use a custom one"
        $isoStatus.Text = "Status: Not downloaded"
        $downloadButton.Text = "Download ISO"
        $downloadButton.BackColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
        $downloadButton.ForeColor = [System.Drawing.Color]::White
        $downloadButton.Enabled = $true
        $prepareButton.Enabled = $false
        $script:IsoDownloaded = $false
    }
}
function Start-PrepareBoot {
    Start-Installation
}
function Get-SelectedDistro {
    if ($customRadio.Checked) {
        $isoSource = if ($script:CustomIsoPath) { $script:CustomIsoPath } else { $script:IsoPath }
        if (-not $isoSource) {
            return $null
        }
        return @{
            Name        = [System.IO.Path]::GetFileNameWithoutExtension($isoSource)
            IsoFilename = [System.IO.Path]::GetFileName($isoSource)
            Custom      = $true
        }
    }
    else {
        $idx = $distroCombo.SelectedIndex
        if ($idx -ge 0 -and $idx -lt $script:DistroKeys.Count) {
            return $script:Distros[$script:DistroKeys[$idx]]
        }
    }
    return $script:Distros["mint"]
}
function Show-DiskPlan {
    param(
        [string]$DistroName
    )

    $bootPartSizeGB = Get-BootPartSizeGB     # 7 GB (FAT32) or 12 GB (ext4)
    $bootPartFsType = Get-BootPartFsType     # "FAT32" or "ext4"

    # ---- Enumerate all suitable disks ----
    $allDisks = Get-Disk | Where-Object {
        $_.OperationalStatus -eq 'Online' -and $_.Size -gt 10GB
    } | Sort-Object Number

    $cDiskNumber = $script:CDriveInfo.DiskNumber

    # Build dropdown items: C: disk first, then others
    $diskItems = @()
    foreach ($d in $allDisks) {
        $dSizeGB = [math]::Round($d.Size / 1GB, 1)
        $dFreeGB = Get-DiskUnallocatedGB -DiskNumber $d.Number
        $busType = if ($d.BusType) { $d.BusType } else { "Unknown" }
        $model = if ($d.Model) { $d.Model.Trim() } else { "Disk" }

        $letters = (Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveLetter } |
            ForEach-Object { "$($_.DriveLetter):" }) -join ", "
        $letterInfo = if ($letters) { " [$letters]" } else { "" }

        $isCDisk = ($d.Number -eq $cDiskNumber)
        if ($isCDisk) {
            $dFreeGB = [math]::Max($dFreeGB, $script:MaxAvailableGB)
        }
        $prefix = if ($isCDisk) { "Disk $($d.Number) (Windows)" } else { "Disk $($d.Number)" }

        $diskItems += [PSCustomObject]@{
            Number = $d.Number
            Label = "$prefix - $model - $dSizeGB GB ($busType)$letterInfo - Total unallocated: $dFreeGB GB"
            IsCDisk = $isCDisk
            TotalGB = $dSizeGB
            FreeGB = $dFreeGB
        }
    }

    # ── Early check: any disk has enough space for minimum Linux? ─────────────
    $hasEnoughSpace = $false
    foreach ($item in $diskItems) {
        $minBootPlanGB = Get-BootPartSizeGB
        if ($item.IsCDisk) {
            $minShrinkAllGB = [math]::Floor($script:CDriveInfo.FreeGB - $minBootPlanGB - 10)
            $cPart = Get-Partition -DriveLetter C -ErrorAction SilentlyContinue
            $cAnchorEnd = if ($cPart) { $cPart.Offset + $cPart.Size } else { $script:CDriveInfo.PartitionEndOffset }
            $minFreePlan = Get-ContiguousInstallPlan -DiskNumber $item.Number -AnchorEnd $cAnchorEnd `
                -BootPartSizeGB $minBootPlanGB -LinuxSizeGB $script:MinLinuxSizeGB
            $minBootOnlyPlan = Get-ContiguousInstallPlan -DiskNumber $item.Number -AnchorEnd $cAnchorEnd `
                -BootPartSizeGB $minBootPlanGB -LinuxSizeGB 0
            if ($minShrinkAllGB -ge $script:MinLinuxSizeGB -or
                $minFreePlan.HasRequestedLinuxSpace -or
                ($minBootOnlyPlan.HasBootSpace -and [math]::Floor($script:CDriveInfo.FreeGB - 10) -ge $script:MinLinuxSizeGB)) {
                $hasEnoughSpace = $true
                break
            }
        } else {
            $parts = @(Get-Partition -DiskNumber $item.Number -ErrorAction SilentlyContinue | Sort-Object Offset)
            $anchorEnd = if ($parts.Count -gt 0) {
                $lastPart = $parts | Select-Object -Last 1
                $lastPart.Offset + $lastPart.Size
            } else {
                [int64](1MB)
            }
            $minFreePlan = Get-ContiguousInstallPlan -DiskNumber $item.Number -AnchorEnd $anchorEnd `
                -BootPartSizeGB $minBootPlanGB -LinuxSizeGB $script:MinLinuxSizeGB
            $canShrinkForMin = $false
            foreach ($part in $parts) {
                if ($part.DriveLetter) {
                    try {
                        $vol = Get-Volume -DriveLetter $part.DriveLetter -ErrorAction Stop
                        if ($vol.FileSystem -eq "NTFS" -and [math]::Floor(($vol.SizeRemaining / 1GB) - $minBootPlanGB - 5) -ge $script:MinLinuxSizeGB) {
                            $canShrinkForMin = $true
                            break
                        }
                    } catch {}
                }
            }
            $canWipeForMin = ($item.TotalGB -ge ($script:MinLinuxSizeGB + $minBootPlanGB + 1))
            if ($minFreePlan.HasRequestedLinuxSpace -or $canShrinkForMin -or $canWipeForMin) {
                $hasEnoughSpace = $true
                break
            }
        }
    }
    if (-not $hasEnoughSpace) {
        [System.Windows.Forms.MessageBox]::Show(
            "None of your disks have enough free space for Linux.`n`n" +
            "Minimum required: $($script:MinLinuxSizeGB) GB.`n`n" +
            "Please free up some space on your disk and try again.",
            "Insufficient Disk Space",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        )
        $script:DiskPlanApproved = $false
        return @{ Approved = $false }
    }

    # ---- Build the dialog ----
    $planForm = New-Object System.Windows.Forms.Form
    $planForm.Text = "Disk Plan - Review Before Proceeding"
    $planForm.Size = New-Object System.Drawing.Size(720, 780)
    $planForm.StartPosition = "CenterParent"
    $planForm.FormBorderStyle = "Sizable"
    $planForm.MinimumSize = New-Object System.Drawing.Size(720, 480)
    $planForm.MaximizeBox = $true
    $planForm.MinimizeBox = $false
    $planForm.AutoScroll = $true

    $planFont = New-Object System.Drawing.Font("Segoe UI", 9)
    $planBoldFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
    $planHeaderFont = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
    $planMonoFont = New-Object System.Drawing.Font("Consolas", 9)

    $yPos = 12

    # Title
    $titleLabel = New-Object System.Windows.Forms.Label
    $titleLabel.Text = "Review Disk Changes for $DistroName"
    $titleLabel.Font = $planHeaderFont
    $titleLabel.Location = New-Object System.Drawing.Point(16, $yPos)
    $titleLabel.Size = New-Object System.Drawing.Size(670, 26)
    $planForm.Controls.Add($titleLabel)
    $yPos += 32

    # Warning banner
    $warningPanel = New-Object System.Windows.Forms.Panel
    $warningPanel.Location = New-Object System.Drawing.Point(16, $yPos)
    $warningPanel.Size = New-Object System.Drawing.Size(670, 42)
    $warningPanel.BackColor = [System.Drawing.Color]::FromArgb(255, 248, 220)
    $warningPanel.BorderStyle = "FixedSingle"
    $planForm.Controls.Add($warningPanel)

    $warningLabel = New-Object System.Windows.Forms.Label
    $warningLabel.Text = [char]0x26A0 + "  These changes modify your disk's partition table. Some options (like wipe and reformat) will DESTROY ALL DATA on the target disk. Make sure you have a backup of important files before proceeding."
    $warningLabel.Font = $planFont
    $warningLabel.Location = New-Object System.Drawing.Point(8, 4)
    $warningLabel.Size = New-Object System.Drawing.Size(650, 34)
    $warningPanel.Controls.Add($warningLabel)
    $yPos += 52

    # ---- TARGET DISK SELECTOR ----
    $diskSelectGroup = New-Object System.Windows.Forms.GroupBox
    $diskSelectGroup.Text = "Target Disk"
    $diskSelectGroup.Font = $planBoldFont
    $diskSelectGroup.Location = New-Object System.Drawing.Point(16, $yPos)
    $diskSelectGroup.Size = New-Object System.Drawing.Size(670, 56)
    $planForm.Controls.Add($diskSelectGroup)

    $diskCombo = New-Object System.Windows.Forms.ComboBox
    $diskCombo.Font = $planFont
    $diskCombo.DropDownStyle = "DropDownList"
    $diskCombo.Location = New-Object System.Drawing.Point(10, 22)
    $diskCombo.Size = New-Object System.Drawing.Size(648, 24)
    $diskSelectGroup.Controls.Add($diskCombo)

    foreach ($item in $diskItems) {
        $diskCombo.Items.Add($item.Label) | Out-Null
    }
    $cIndex = 0
    for ($i = 0; $i -lt $diskItems.Count; $i++) {
        if ($diskItems[$i].IsCDisk) { $cIndex = $i; break }
    }
    $diskCombo.SelectedIndex = $cIndex
    $yPos += 66

    # ---- LINUX PARTITION SIZE ----
    $sizeGroup = New-Object System.Windows.Forms.GroupBox
    $sizeGroup.Text = "Linux Partition Size"
    $sizeGroup.Font = $planBoldFont
    $sizeGroup.Location = New-Object System.Drawing.Point(16, $yPos)
    $sizeGroup.Size = New-Object System.Drawing.Size(670, 56)
    $planForm.Controls.Add($sizeGroup)

    $sizeLabel = New-Object System.Windows.Forms.Label
    $sizeLabel.Text = "Size for Linux (GB):"
    $sizeLabel.Font = $planFont
    $sizeLabel.Location = New-Object System.Drawing.Point(10, 24)
    $sizeLabel.Size = New-Object System.Drawing.Size(130, 20)
    $sizeGroup.Controls.Add($sizeLabel)

    $sizeNumeric = New-Object System.Windows.Forms.NumericUpDown
    $sizeNumeric.Font = $planFont
    $sizeNumeric.Location = New-Object System.Drawing.Point(145, 22)
    $sizeNumeric.Size = New-Object System.Drawing.Size(80, 24)
    $sizeNumeric.Minimum = $script:MinLinuxSizeGB
    $sizeNumeric.Maximum = if ($script:MaxAvailableGB -gt $script:MinLinuxSizeGB) { $script:MaxAvailableGB } else { 10000 }
    $sizeNumeric.Value = [Math]::Min(30, $sizeNumeric.Maximum)
    $sizeGroup.Controls.Add($sizeNumeric)

    $sizeHelpLabel = New-Object System.Windows.Forms.Label
    $sizeHelpLabel.Text = "Minimum: 20 GB, Recommended: 100+ GB"
    $sizeHelpLabel.Font = $planFont
    $sizeHelpLabel.Location = New-Object System.Drawing.Point(240, 24)
    $sizeHelpLabel.Size = New-Object System.Drawing.Size(400, 20)
    $sizeGroup.Controls.Add($sizeHelpLabel)
    $yPos += 66

    # ---- CURRENT LAYOUT ----
    $currentGroup = New-Object System.Windows.Forms.GroupBox
    $currentGroup.Text = "Current Disk Layout"
    $currentGroup.Font = $planBoldFont
    $currentGroup.Location = New-Object System.Drawing.Point(16, $yPos)
    $currentGroup.Size = New-Object System.Drawing.Size(670, 150)
    $planForm.Controls.Add($currentGroup)

    $currentText = New-Object System.Windows.Forms.TextBox
    $currentText.Multiline = $true
    $currentText.ReadOnly = $true
    $currentText.ScrollBars = "Vertical"
    $currentText.Font = $planMonoFont
    $currentText.Location = New-Object System.Drawing.Point(10, 20)
    $currentText.Size = New-Object System.Drawing.Size(648, 120)
    $currentText.BackColor = [System.Drawing.Color]::White
    $currentGroup.Controls.Add($currentText)
    $yPos += 160

    # ---- PLANNED CHANGES ----
    $changesGroup = New-Object System.Windows.Forms.GroupBox
    $changesGroup.Text = "Changes QuickLinux Will Make"
    $changesGroup.Font = $planBoldFont
    $changesGroup.Location = New-Object System.Drawing.Point(16, $yPos)
    $changesGroup.Size = New-Object System.Drawing.Size(670, 100)
    $planForm.Controls.Add($changesGroup)

    $changesText = New-Object System.Windows.Forms.TextBox
    $changesText.Multiline = $true
    $changesText.ReadOnly = $true
    $changesText.Font = $planMonoFont
    $changesText.Location = New-Object System.Drawing.Point(10, 20)
    $changesText.Size = New-Object System.Drawing.Size(648, 70)
    $changesText.BackColor = [System.Drawing.Color]::White
    $changesGroup.Controls.Add($changesText)
    $yPos += 110

    # ---- AFTER LAYOUT ----
    $afterGroup = New-Object System.Windows.Forms.GroupBox
    $afterGroup.Text = "Resulting Disk Layout"
    $afterGroup.Font = $planBoldFont
    $afterGroup.Location = New-Object System.Drawing.Point(16, $yPos)
    $afterGroup.Size = New-Object System.Drawing.Size(670, 130)
    $planForm.Controls.Add($afterGroup)

    $afterText = New-Object System.Windows.Forms.TextBox
    $afterText.Multiline = $true
    $afterText.ReadOnly = $true
    $afterText.ScrollBars = "Vertical"
    $afterText.Font = $planMonoFont
    $afterText.Location = New-Object System.Drawing.Point(10, 20)
    $afterText.Size = New-Object System.Drawing.Size(648, 100)
    $afterText.BackColor = [System.Drawing.Color]::White
    $afterGroup.Controls.Add($afterText)
    $yPos += 140

    # ---- STRATEGY SELECTION ----
    $strategyGroup = New-Object System.Windows.Forms.GroupBox
    $strategyGroup.Text = "Partition Strategy"
    $strategyGroup.Font = $planBoldFont
    $strategyGroup.Location = New-Object System.Drawing.Point(16, $yPos)
    $strategyGroup.Size = New-Object System.Drawing.Size(670, 104)
    $planForm.Controls.Add($strategyGroup)

    $stratPanel = New-Object System.Windows.Forms.Panel
    $stratPanel.Location = New-Object System.Drawing.Point(10, 18)
    $stratPanel.Size = New-Object System.Drawing.Size(648, 80)
    $strategyGroup.Controls.Add($stratPanel)

    $radioShrink = New-Object System.Windows.Forms.RadioButton
    $radioShrink.Font = $planFont
    $radioShrink.Location = New-Object System.Drawing.Point(0, 0)
    $radioShrink.Size = New-Object System.Drawing.Size(640, 20)
    $radioShrink.Checked = $true
    $stratPanel.Controls.Add($radioShrink)

    $radioFreeAll = New-Object System.Windows.Forms.RadioButton
    $radioFreeAll.Font = $planFont
    $radioFreeAll.Location = New-Object System.Drawing.Point(0, 24)
    $radioFreeAll.Size = New-Object System.Drawing.Size(640, 20)
    $stratPanel.Controls.Add($radioFreeAll)

    $radioWipe = New-Object System.Windows.Forms.RadioButton
    $radioWipe.Font = $planFont
    $radioWipe.ForeColor = [System.Drawing.Color]::DarkRed
    $radioWipe.Location = New-Object System.Drawing.Point(0, 48)
    $radioWipe.Size = New-Object System.Drawing.Size(640, 20)
    $radioWipe.Visible = $false
    $stratPanel.Controls.Add($radioWipe)

    $yPos += 112

    # Track selected disk number and shrink info
    $script:DiskPlanStrategy = "shrink_all"
    $script:DiskPlanTargetDisk = $cDiskNumber
    $script:DiskPlanShrinkLetter = $null
    $script:DiskPlanShrinkAmount = 0

    # ---- Master update function ----
    $updateAll = {
        $selIndex = $diskCombo.SelectedIndex
        if ($selIndex -lt 0) { return }
        $selDisk = $diskItems[$selIndex]
        $selDiskNum = $selDisk.Number
        $isTargetCDisk = $selDisk.IsCDisk

        $useRefind = $refindCheck.Checked
        $refindGB = if ($useRefind) { 0.1 } else { 0 }
        $bootPlacementOverheadGB = (Get-BootPlacementOverheadBytes -UseRefind:$useRefind) / 1GB
        $script:DiskPlanTargetDisk = $selDiskNum

        # Update current layout text
        $layoutLines = Get-DiskLayoutText -DiskNumber $selDiskNum
        $diskObj = Get-Disk -Number $selDiskNum
        $dTotalGB = [math]::Round($diskObj.Size / 1GB, 2)
        $currentGroup.Text = "Current Disk Layout  (Disk $selDiskNum - $dTotalGB GB)"

        $totalFreeGB = Get-DiskUnallocatedGB -DiskNumber $selDiskNum
        if ($totalFreeGB -gt 0.01) {
            $layoutLines += ""
            $layoutLines += "  Total unallocated space: $totalFreeGB GB"
        }
        $currentText.Text = ($layoutLines -join "`r`n")

        $dynamicMaxLinuxGB = $script:MinLinuxSizeGB
        if ($isTargetCDisk) {
            $cPartitionForMax = Get-Partition -DriveLetter C
            $cPartitionEndForMax = $cPartitionForMax.Offset + $cPartitionForMax.Size
            $freeAllPlanForMax = Get-ContiguousInstallPlan -DiskNumber $selDiskNum -AnchorEnd $cPartitionEndForMax `
                -BootPartSizeGB $bootPartSizeGB -LinuxSizeGB 0 -UseRefind:$useRefind
            $bootOnlyPlanForMax = Get-ContiguousInstallPlan -DiskNumber $selDiskNum -AnchorEnd $cPartitionEndForMax `
                -BootPartSizeGB $bootPartSizeGB -LinuxSizeGB 0 -UseRefind:$useRefind
            $maxShrinkAllGB = [math]::Max(0, [math]::Floor($script:CDriveInfo.FreeGB - $bootPartSizeGB - $bootPlacementOverheadGB - 10))
            $maxUseFreeBootGB = if ($bootOnlyPlanForMax.HasBootSpace) { [math]::Max(0, [math]::Floor($script:CDriveInfo.FreeGB - 10 + $bootOnlyPlanForMax.LinuxSpaceGB)) } else { 0 }
            $maxUseFreeAllGB = if ($freeAllPlanForMax.HasBootSpace) { [math]::Max(0, [math]::Floor($freeAllPlanForMax.LinuxSpaceGB)) } else { 0 }
            $dynamicMaxLinuxGB = [math]::Max($maxShrinkAllGB, [math]::Max($maxUseFreeBootGB, $maxUseFreeAllGB))
        } else {
            $partsForMax = @(Get-Partition -DiskNumber $selDiskNum -ErrorAction SilentlyContinue | Sort-Object Offset)
            $anchorEndForMax = if ($partsForMax.Count -gt 0) {
                $lastPart = $partsForMax | Select-Object -Last 1
                $lastPart.Offset + $lastPart.Size
            } else {
                [int64](1MB)
            }
            $freePlanForMax = Get-ContiguousInstallPlan -DiskNumber $selDiskNum -AnchorEnd $anchorEndForMax `
                -BootPartSizeGB $bootPartSizeGB -LinuxSizeGB 0 -UseRefind:$useRefind
            $maxExistingFreeGB = if ($freePlanForMax.HasBootSpace) { [math]::Max(0, [math]::Floor($freePlanForMax.LinuxSpaceGB)) } else { 0 }
            $maxShrinkGB = 0
            foreach ($part in $partsForMax) {
                if ($part.DriveLetter) {
                    try {
                        $vol = Get-Volume -DriveLetter $part.DriveLetter -ErrorAction Stop
                        if ($vol.FileSystem -eq "NTFS") {
                            $candidateMax = [math]::Floor(($vol.SizeRemaining / 1GB) - $bootPartSizeGB - $bootPlacementOverheadGB - 5)
                            if ($candidateMax -gt $maxShrinkGB) {
                                $maxShrinkGB = $candidateMax
                            }
                        }
                    } catch {}
                }
            }
            $maxWipeGB = [math]::Floor($selDisk.TotalGB - $bootPartSizeGB - $refindGB)
            $dynamicMaxLinuxGB = [math]::Max($maxExistingFreeGB, [math]::Max($maxShrinkGB, $maxWipeGB))
        }

        if ($dynamicMaxLinuxGB -lt $script:MinLinuxSizeGB) {
            $dynamicMaxLinuxGB = $script:MinLinuxSizeGB
        }
        if ([decimal]$sizeNumeric.Maximum -ne [decimal]$dynamicMaxLinuxGB) {
            $sizeNumeric.Maximum = [decimal]$dynamicMaxLinuxGB
        }
        if ($sizeNumeric.Value -gt $sizeNumeric.Maximum) {
            $sizeNumeric.Value = $sizeNumeric.Maximum
            return
        }

        $LinuxSizeGB = [int]$sizeNumeric.Value
        $shrinkAllAmountGB = Get-ShrinkAllAmountGB -LinuxSizeGB $LinuxSizeGB -BootPartSizeGB $bootPartSizeGB -UseRefind:$useRefind
        $totalNeededGB = $shrinkAllAmountGB

        if ($isTargetCDisk) {
            # ---- C: disk strategies ----
            $radioWipe.Visible = $false
            $radioWipe.Checked = $false
            $cPartition = Get-Partition -DriveLetter C
            $cSizeGB = [math]::Round($cPartition.Size / 1GB, 2)
            $cFreeGB = $script:CDriveInfo.FreeGB
            $cPartitionEnd = $cPartition.Offset + $cPartition.Size
            $usableFreeGB = Get-DiskUnallocatedGB -DiskNumber $selDiskNum -AfterOffset $cPartitionEnd
            $freeAllPlan = Get-ContiguousInstallPlan -DiskNumber $selDiskNum -AnchorEnd $cPartitionEnd `
                -BootPartSizeGB $bootPartSizeGB -LinuxSizeGB $LinuxSizeGB -UseRefind:$useRefind
            $freeBootPlan = Get-ContiguousInstallPlan -DiskNumber $selDiskNum -AnchorEnd $cPartitionEnd `
                -BootPartSizeGB $bootPartSizeGB -LinuxSizeGB 0 -UseRefind:$useRefind

            $canFreeAll = $freeAllPlan.HasRequestedLinuxSpace
            $canFreeBoot = $freeBootPlan.HasBootSpace
            $freeBootExistingLinuxBytes = if ($canFreeBoot) { $freeBootPlan.LinuxSpaceBytes } else { [int64]0 }
            $requestedLinuxBytes = [int64]($LinuxSizeGB * 1GB)
            if ($requestedLinuxBytes -gt $freeBootExistingLinuxBytes) {
                $freeBootShrinkBytes = $requestedLinuxBytes - $freeBootExistingLinuxBytes
            } else {
                $freeBootShrinkBytes = [int64]0
            }
            $freeBootExistingLinuxGB = [math]::Round($freeBootExistingLinuxBytes / 1GB, 2)
            $freeBootShrinkAmountGB = $freeBootShrinkBytes / 1GB

            $refindNote = if ($useRefind) { ", live boot ($bootPartSizeGB GB), and rEFInd" } else { " + live boot ($bootPartSizeGB GB)" }
            $radioShrink.Text = "Shrink C: by $([math]::Round($totalNeededGB, 2)) GB to create Linux ($LinuxSizeGB GB)$refindNote"
            $radioShrink.Visible = $true
            $radioShrink.Enabled = $true

            if ($canFreeAll) {
                $radioFreeAll.Text = "Use existing unallocated space — no C: shrink needed"
                $radioFreeAll.Visible = $true
                $radioFreeAll.Enabled = $true
            } elseif ($canFreeBoot) {
                if ($freeBootExistingLinuxGB -ge $LinuxSizeGB) {
                    $radioFreeAll.Text = "Use existing unallocated space — no C: shrink needed"
                } elseif ($freeBootExistingLinuxGB -gt 0) {
                    $radioFreeAll.Text = "Use existing unallocated space, then shrink C: by $([math]::Round($freeBootShrinkAmountGB, 2)) GB to reach $LinuxSizeGB GB for Linux"
                } else {
                    $radioFreeAll.Text = "Place live boot partition in existing unallocated space, then shrink C: by $([math]::Round($freeBootShrinkAmountGB, 2)) GB for Linux"
                }
                $radioFreeAll.Visible = $true
                $radioFreeAll.Enabled = $true
            } else {
                $radioFreeAll.Visible = $false
                $radioFreeAll.Checked = $false
                if (-not $radioShrink.Checked) { $radioShrink.Checked = $true }
            }

            $strategyGroup.Visible = $true

            $strategy = "shrink_all"
            if ($radioFreeAll.Visible -and $radioFreeAll.Checked) {
                if ($canFreeAll) { $strategy = "use_free_all" }
                elseif ($canFreeBoot) { $strategy = "use_free_boot" }
            }
            $script:DiskPlanStrategy = $strategy
            switch ($strategy) {
                "shrink_all" { $script:DiskPlanShrinkAmount = $totalNeededGB }
                "use_free_boot" { $script:DiskPlanShrinkAmount = $freeBootShrinkAmountGB }
                default { $script:DiskPlanShrinkAmount = 0 }
            }

            $changeLines = @()
            $afterLines = @()
            $partitions = Get-Partition -DiskNumber $selDiskNum | Sort-Object Offset

            # Always resolve the selected distro first
            $distro = Get-SelectedDistro
            $distroName = if ($customRadio.Checked -and $script:CustomIsoPath) {
                [System.IO.Path]::GetFileNameWithoutExtension($script:CustomIsoPath)
            } elseif ($distro -and $distro.Name) {
                $distro.Name
            } else {
                $DistroName
            }
            switch ($strategy) {
                "shrink_all" {
                    $newCSizeGB = [math]::Round($cSizeGB - $totalNeededGB, 2)
                    $step = 1
                    $changeLines += "  $step. Shrink C: by $([math]::Round($totalNeededGB, 2)) GB to create Linux ($LinuxSizeGB GB) + live boot ($bootPartSizeGB GB)"
                    $step++
                    $changeLines += "  $step. Create $bootPartSizeGB GB $bootPartFsType live boot partition (LINUX_LIVE) with $distroName files"
                    if ($useRefind) {
                        $step++
                        $changeLines += "  $step. Create 100 MB FAT32 rEFInd partition"
                    }
                    $step++
                    $changeLines += "  $step. Leave $LinuxSizeGB GB unallocated for Linux installation"
                    $step++
                    if ($useRefind) {
                        $changeLines += "  $step. Install rEFInd boot manager and configure UEFI boot entry"
                    } else {
                        $changeLines += "  $step. Configure UEFI boot entry for $distroName"
                    }

                    $afterLines = Format-AfterLayout -Partitions $partitions -DistroName $distroName `
                        -BootPartSizeGB $bootPartSizeGB -LinuxSizeGB $LinuxSizeGB `
                        -ShrinkLetter 'C' -NewShrinkSizeGB $newCSizeGB -UseRefind:$useRefind `
                        -BootPartFsType $bootPartFsType
                }
                "use_free_all" {
                    $step = 1
                    $changeLines += "  $step. C: partition is NOT modified (stays at $cSizeGB GB)"
                    $step++
                    $changeLines += "  $step. Use existing unallocated space for live boot and Linux"
                    if ($useRefind) {
                        $step++
                        $changeLines += "  $step. Create 100 MB FAT32 rEFInd partition"
                    }
                    $step++
                    $remainFreeGB = $freeAllPlan.LinuxSpaceGB
                    $changeLines += "  $step. Remaining ~$remainFreeGB GB stays unallocated for Linux"
                    $step++
                    if ($useRefind) {
                        $changeLines += "  $step. Install rEFInd boot manager and configure UEFI boot entry"
                    } else {
                        $changeLines += "  $step. Configure UEFI boot entry for $distroName"
                    }

                    $afterLines = Format-AfterLayout -Partitions $partitions -DistroName $distroName `
                        -BootPartSizeGB $bootPartSizeGB -ShowUnchanged -AppendLinuxAndBoot `
                        -RemainingFreeGB $remainFreeGB -UseRefind:$useRefind `
                        -BootPartFsType $bootPartFsType
                }
                "use_free_boot" {
                    $newCSizeGB = [math]::Round($cSizeGB - $freeBootShrinkAmountGB, 2)
                    $step = 1
                    $changeLines += "  $step. Place live boot partition in existing unallocated space"
                    # Calculate actual existing free space used before any extra shrink
                    $existingFreeGB = $freeBootPlan.ChosenGapSizeGB
                    $step++
                    $changeLines += "  $step. Create $bootPartSizeGB GB $bootPartFsType live boot partition (LINUX_LIVE) in existing unallocated space ($([math]::Round($existingFreeGB, 1)) GB available)"
                    if ($useRefind) {
                        $step++
                        $changeLines += "  $step. Create 100 MB FAT32 rEFInd partition"
                    }
                    $step++
                    $changeLines += "  $step. Linux space target: $LinuxSizeGB GB"
                    if ($freeBootExistingLinuxGB -gt 0) {
                        $step++
                        $changeLines += "  $step. Use $freeBootExistingLinuxGB GB of existing unallocated space for Linux"
                    }
                    if ($freeBootShrinkAmountGB -gt 0) {
                        $step++
                        $changeLines += "  $step. Shrink C: by $([math]::Round($freeBootShrinkAmountGB, 2)) GB to complete the requested Linux space"
                    }
                    $step++
                    if ($useRefind) {
                        $changeLines += "  $step. Install rEFInd boot manager and configure UEFI boot entry"
                    } else {
                        $changeLines += "  $step. Configure UEFI boot entry for $distroName"
                    }

                    $afterLines = Format-AfterLayout -Partitions $partitions -DistroName $distroName `
                        -BootPartSizeGB $bootPartSizeGB -LinuxSizeGB $LinuxSizeGB `
                        -ShrinkLetter 'C' -NewShrinkSizeGB $newCSizeGB -ShrinkLinuxOnly `
                        -UseRefind:$useRefind -BootPartFsType $bootPartFsType
                }
            }

            $changesText.Text = ($changeLines -join "`r`n")
            $afterText.Text = ($afterLines -join "`r`n")

        } else {
            # ---- Other disk ----
            $shrinkablePartitions = @()
            $partitions = Get-Partition -DiskNumber $selDiskNum -ErrorAction SilentlyContinue | Sort-Object Offset
            if ($partitions) {
                foreach ($part in $partitions) {
                    if ($part.DriveLetter) {
                        try {
                            $vol = Get-Volume -DriveLetter $part.DriveLetter -ErrorAction Stop
                            if ($vol.FileSystem -eq "NTFS" -and $vol.SizeRemaining -ge (($totalNeededGB + 5) * 1GB)) {
                                $shrinkablePartitions += [PSCustomObject]@{
                                    DriveLetter = $part.DriveLetter
                                    SizeGB = [math]::Round($part.Size / 1GB, 2)
                                    FreeGB = [math]::Round($vol.SizeRemaining / 1GB, 2)
                                    PartitionNumber = $part.PartitionNumber
                                }
                            }
                        } catch {}
                    }
                }
            }

            $diskFreeGB = $selDisk.FreeGB
            $anchorEnd = if ($partitions -and $partitions.Count -gt 0) {
                $lastPart = $partitions | Select-Object -Last 1
                $lastPart.Offset + $lastPart.Size
            } else {
                [int64](1MB)
            }
            $otherDrivePlan = Get-ContiguousInstallPlan -DiskNumber $selDiskNum -AnchorEnd $anchorEnd `
                -BootPartSizeGB $bootPartSizeGB -LinuxSizeGB $LinuxSizeGB -UseRefind:$useRefind
            $hasFreeSpace = $otherDrivePlan.HasRequestedLinuxSpace
            $hasShrinkable = ($shrinkablePartitions.Count -gt 0)

            $nonNtfsPartitions = @()
            if ($partitions) {
                foreach ($part in $partitions) {
                    if ($part.DriveLetter) {
                        try {
                            $vol = Get-Volume -DriveLetter $part.DriveLetter -ErrorAction Stop
                            if ($vol.FileSystem -ne "NTFS" -and $vol.FileSystem) {
                                $nonNtfsPartitions += [PSCustomObject]@{
                                    DriveLetter = $part.DriveLetter
                                    FileSystem = $vol.FileSystem
                                    SizeGB = [math]::Round($part.Size / 1GB, 2)
                                }
                            }
                        } catch {}
                    }
                }
            }

            # Configure radio buttons for other-drive strategies
            if ($hasFreeSpace) {
                $radioShrink.Text = "Use existing unallocated space on Disk $selDiskNum — no partition shrink needed"
                $radioShrink.Visible = $true
                $radioShrink.Enabled = $true
                if (-not $radioShrink.Checked -and -not $radioFreeAll.Checked -and -not $radioWipe.Checked) {
                    $radioShrink.Checked = $true
                }
            } else {
                $radioShrink.Visible = $false
                $radioShrink.Checked = $false
            }

            if ($hasShrinkable) {
                $bestShrink = $shrinkablePartitions | Sort-Object FreeGB -Descending | Select-Object -First 1
                $radioFreeAll.Text = "Shrink $($bestShrink.DriveLetter): on Disk $selDiskNum by $([math]::Round($totalNeededGB, 2)) GB to create Linux ($LinuxSizeGB GB) + live boot ($bootPartSizeGB GB)"
                $radioFreeAll.Visible = $true
                $radioFreeAll.Enabled = $true
                if (-not $hasFreeSpace -and -not $radioWipe.Checked) {
                    $radioFreeAll.Checked = $true
                }
            } else {
                $radioFreeAll.Visible = $false
                $radioFreeAll.Checked = $false
            }

            # Always offer wipe & reformat for non-C: disks if disk is large enough
            $wipeMinGB = $LinuxSizeGB + $bootPartSizeGB + $refindGB
            $diskSizeOK = ($selDisk.TotalGB -ge $wipeMinGB)
            $radioWipe.Text = [char]0x26A0 + " Erase Disk $selDiskNum and use it entirely for QuickLinux ($($selDisk.TotalGB) GB) - ALL DATA WILL BE DESTROYED"
            $radioWipe.Visible = $true
            $radioWipe.Enabled = $diskSizeOK

            if (-not $hasFreeSpace -and -not $hasShrinkable) {
                if ($diskSizeOK) {
                    $radioShrink.Text = "No unallocated space or shrinkable partitions on Disk $selDiskNum"
                    $radioShrink.Visible = $true
                    $radioShrink.Enabled = $false
                    $radioShrink.Checked = $false

                    if ($nonNtfsPartitions.Count -gt 0) {
                        $fsTypes = ($nonNtfsPartitions | ForEach-Object { "$($_.DriveLetter): ($($_.FileSystem))" }) -join ", "
                        $radioFreeAll.Text = "Cannot shrink $fsTypes - only NTFS partitions can be resized by Windows"
                        $radioFreeAll.Visible = $true
                        $radioFreeAll.Enabled = $false
                        $radioFreeAll.Checked = $false
                    }

                    if (-not $radioWipe.Checked) {
                        $radioWipe.Checked = $true
                    }
                } else {
                    $radioShrink.Text = "No unallocated space or shrinkable partitions on Disk $selDiskNum"
                    $radioShrink.Visible = $true
                    $radioShrink.Enabled = $false
                    $radioShrink.Checked = $false
                    $radioFreeAll.Visible = $false

                    if ($nonNtfsPartitions.Count -gt 0) {
                        $fsTypes = ($nonNtfsPartitions | ForEach-Object { "$($_.DriveLetter): ($($_.FileSystem))" }) -join ", "
                        $radioFreeAll.Text = "Cannot shrink $fsTypes - only NTFS partitions can be resized by Windows"
                        $radioFreeAll.Visible = $true
                        $radioFreeAll.Enabled = $false
                        $radioFreeAll.Checked = $false
                    }
                }
            }

            $strategyGroup.Visible = $true

            $usingWipe = ($radioWipe.Visible -and $radioWipe.Checked)

            if ($usingWipe) {
                $usingShrink = $false
            } elseif ($hasShrinkable -and -not $hasFreeSpace -and -not $usingWipe) {
                $usingShrink = $true
            } elseif ($hasFreeSpace -and -not $hasShrinkable) {
                $usingShrink = $false
            } elseif ($hasFreeSpace -and $hasShrinkable) {
                $usingShrink = $radioFreeAll.Checked
            } else {
                $usingShrink = $false
            }

            if ($usingWipe) {
                $script:DiskPlanStrategy = "wipe_disk"
                $script:DiskPlanShrinkLetter = $null
                $script:DiskPlanShrinkAmount = 0
            } elseif ($usingShrink) {
                $script:DiskPlanStrategy = "other_drive_shrink"
                $script:DiskPlanShrinkLetter = $bestShrink.DriveLetter
                $script:DiskPlanShrinkAmount = $totalNeededGB
            } else {
                $script:DiskPlanStrategy = "other_drive"
                $script:DiskPlanShrinkLetter = $null
                $script:DiskPlanShrinkAmount = 0
            }

            $changeLines = @()
            $afterLines = @()

            if ($usingWipe) {
                $usableGB = [math]::Round($selDisk.TotalGB - $bootPartSizeGB - $refindGB, 1)

                $changeLines += "  ** WARNING: This will ERASE ALL DATA on this disk! **"
                $changeLines += ""
                $step = 1
                $changeLines += "  $step. C: partition is NOT modified (different disk)"
                $step++
                $changeLines += "  $step. Wipe Disk $selDiskNum and create a new GPT partition table"
                $step++
                $changeLines += "  $step. Create $bootPartSizeGB GB $bootPartFsType live boot partition (LINUX_LIVE)"
                if ($useRefind) {
                    $step++
                    $changeLines += "  $step. Create 100 MB FAT32 rEFInd partition"
                }
                $step++
                $changeLines += "  $step. Leave ~$usableGB GB unallocated for Linux installation"
                $step++
                if ($useRefind) {
                    $changeLines += "  $step. Install rEFInd boot manager and configure UEFI boot entry"
                } else {
                    $changeLines += "  $step. Install bootloader to Windows ESP and configure UEFI boot entry for $DistroName"
                }

                $afterLines += "  LINUX_LIVE ($bootPartFsType)     $bootPartSizeGB GB  <-- $DistroName live boot"
                if ($useRefind) {
                    $afterLines += "  REFIND (FAT32)         0.1 GB  <-- rEFInd boot manager"
                }
                $afterLines += "  [Unallocated - Linux]  ~$usableGB GB  <-- Linux Storage after install"
            } elseif ($usingShrink) {
                $shrinkTarget = $bestShrink
                $newPartSizeGB = [math]::Round($shrinkTarget.SizeGB - $totalNeededGB, 2)
                $step = 1
                $changeLines += "  $step. C: partition is NOT modified (different disk selected)"
                $step++
                $changeLines += "  $step. Shrink $($shrinkTarget.DriveLetter): by $([math]::Round($totalNeededGB, 2)) GB on Disk $selDiskNum to create Linux ($LinuxSizeGB GB) + live boot ($bootPartSizeGB GB)"
                $step++
                $changeLines += "  $step. Create $bootPartSizeGB GB $bootPartFsType live boot partition (LINUX_LIVE) on Disk $selDiskNum"
                if ($useRefind) {
                    $step++
                    $changeLines += "  $step. Create 100 MB FAT32 rEFInd partition"
                }
                $step++
                $changeLines += "  $step. Leave $LinuxSizeGB GB unallocated for Linux installation"
                $step++
                if ($useRefind) {
                    $changeLines += "  $step. Install rEFInd boot manager and configure UEFI boot entry"
                } else {
                    $changeLines += "  $step. Configure UEFI boot entry for $DistroName"
                }

                if ($partitions) {
                    $afterLines = Format-AfterLayout -Partitions $partitions -DistroName $DistroName `
                        -BootPartSizeGB $bootPartSizeGB -LinuxSizeGB $LinuxSizeGB `
                        -ShrinkLetter $shrinkTarget.DriveLetter -NewShrinkSizeGB $newPartSizeGB -UseRefind:$useRefind `
                        -BootPartFsType $bootPartFsType
                }
            } else {
                if ($hasFreeSpace) {
                    $step = 1
                    $changeLines += "  $step. C: partition is NOT modified (different disk selected)"
                    $step++
                    $changeLines += "  $step. Create $bootPartSizeGB GB $bootPartFsType live boot partition (LINUX_LIVE) on Disk $selDiskNum"
                    if ($useRefind) {
                        $step++
                        $changeLines += "  $step. Create 100 MB FAT32 rEFInd partition"
                    }
                    $step++
                    $changeLines += "  $step. Remaining unallocated space on Disk $selDiskNum available for Linux"
                    $step++
                    if ($useRefind) {
                        $changeLines += "  $step. Install rEFInd boot manager and configure UEFI boot entry"
                    } else {
                        $changeLines += "  $step. Configure UEFI boot entry for $DistroName"
                    }

                    $remainFreeGB = $otherDrivePlan.LinuxSpaceGB
                    if ($partitions) {
                        $afterLines = Format-AfterLayout -Partitions $partitions -DistroName $DistroName `
                            -BootPartSizeGB $bootPartSizeGB -ShowUnchanged -AppendLinuxAndBoot `
                            -RemainingFreeGB $remainFreeGB -UseRefind:$useRefind `
                            -BootPartFsType $bootPartFsType
                    }
                } else {
                    $changeLines += "  Cannot proceed with this disk."
                    $changeLines += ""
                    if ($nonNtfsPartitions.Count -gt 0) {
                        foreach ($nfp in $nonNtfsPartitions) {
                            $changeLines += "  $($nfp.DriveLetter): is $($nfp.FileSystem) ($($nfp.SizeGB) GB) - cannot be shrunk by Windows."
                        }
                        $changeLines += ""
                        $changeLines += "  To use this disk, you would need to:"
                        $changeLines += "    - Back up your data from the drive"
                        $changeLines += "    - Shrink or delete the partition using Disk Management"
                        $changeLines += "    - Re-run QuickLinux (it will detect the free space)"
                    } else {
                        $changeLines += "  No unallocated space available on this disk."
                    }

                    if ($partitions) {
                        $afterLines = Format-AfterLayout -Partitions $partitions -DistroName $DistroName `
                            -BootPartSizeGB $bootPartSizeGB -NoChanges `
                            -BootPartFsType $bootPartFsType
                    }
                }
            }

            $changesText.Text = ($changeLines -join "`r`n")
            $afterText.Text = ($afterLines -join "`r`n")
        }
    }

    # Wire events
    $diskCombo.Add_SelectedIndexChanged({
        $radioShrink.Checked = $true
        & $updateAll
    })
    $sizeNumeric.Add_ValueChanged({ & $updateAll })
    $radioShrink.Add_CheckedChanged({ & $updateAll })
    $radioFreeAll.Add_CheckedChanged({ & $updateAll })
    $radioWipe.Add_CheckedChanged({ & $updateAll })

    # Initial update
    & $updateAll

    # ---- BUTTONS ----
    $confirmButton = New-Object System.Windows.Forms.Button
    $confirmButton.Text = "Confirm && Proceed"
    $confirmButton.Font = $planBoldFont
    $confirmButton.Size = New-Object System.Drawing.Size(160, 38)
    $confirmButton.Location = New-Object System.Drawing.Point(362, $yPos)
    $confirmButton.BackColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
    $confirmButton.ForeColor = [System.Drawing.Color]::White
    $confirmButton.FlatStyle = "Flat"
    $planForm.Controls.Add($confirmButton)

    $cancelPlanButton = New-Object System.Windows.Forms.Button
    $cancelPlanButton.Text = "Cancel"
    $cancelPlanButton.Font = $planFont
    $cancelPlanButton.Size = New-Object System.Drawing.Size(120, 38)
    $cancelPlanButton.Location = New-Object System.Drawing.Point(532, $yPos)
    $planForm.Controls.Add($cancelPlanButton)

    $script:DiskPlanApproved = $false

    $confirmButton.Add_Click({
        $selIndex = $diskCombo.SelectedIndex
        $selDisk = $diskItems[$selIndex]

        if (-not $selDisk.IsCDisk) {
            $strat = $script:DiskPlanStrategy
            if ($strat -eq "other_drive") {
                $targetParts = @(Get-Partition -DiskNumber $selDisk.Number -ErrorAction SilentlyContinue | Sort-Object Offset)
                $targetAnchorEnd = if ($targetParts.Count -gt 0) {
                    $lastPart = $targetParts | Select-Object -Last 1
                    $lastPart.Offset + $lastPart.Size
                } else {
                    [int64](1MB)
                }
                $targetPlan = Get-ContiguousInstallPlan -DiskNumber $selDisk.Number -AnchorEnd $targetAnchorEnd `
                    -BootPartSizeGB $bootPartSizeGB -LinuxSizeGB ([int]$sizeNumeric.Value) -UseRefind:$refindCheck.Checked
                if (-not $targetPlan.HasRequestedLinuxSpace) {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Disk $($selDisk.Number) does not have a contiguous unallocated gap large enough for Linux + boot.`n`n" +
                        "Requested Linux space: $([int]$sizeNumeric.Value) GB`n" +
                        "Usable Linux space after boot placement: $($targetPlan.LinuxSpaceGB) GB`n`n" +
                        "Please select a different disk or choose to shrink a partition.",
                        "Insufficient Space on Target Disk",
                        [System.Windows.Forms.MessageBoxButtons]::OK,
                        [System.Windows.Forms.MessageBoxIcon]::Warning
                    )
                    return
                }
            } elseif ($strat -eq "other_drive_shrink") {
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
            } elseif ($strat -eq "wipe_disk") {
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
                
                $wipeConfirm = [System.Windows.Forms.MessageBox]::Show(
                    "WARNING: You are about to ERASE ALL DATA on Disk $($selDisk.Number)!`n`n" +
                    "This will:`n" +
                    "  - Destroy the partition table`n" +
                    "  - Delete ALL partitions and data`n" +
                    "  - Create a fresh GPT layout`n`n" +
                    "This action CANNOT be undone.`n`n" +
                    "Are you absolutely sure?",
                    "Confirm Disk Wipe",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                if ($wipeConfirm -ne [System.Windows.Forms.DialogResult]::Yes) {
                    return
                }
            } elseif ($strat -eq "other_drive") {
                [System.Windows.Forms.MessageBox]::Show(
                    "Disk $($selDisk.Number) cannot be used as-is.`n`n" +
                    "It does not have a contiguous post-data gap large enough for Linux + boot.`n" +
                    "You may need to shrink or remove a partition manually first.",
                    "Cannot Use Target Disk",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                return
            } else {
                [System.Windows.Forms.MessageBox]::Show(
                    "Disk $($selDisk.Number) has no unallocated space and no shrinkable NTFS partitions.`n`n" +
                    "Please select a different disk.",
                    "Cannot Use Target Disk",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Warning
                )
                return
            }
        }

        $script:DiskPlanApproved = $true
        $planForm.Close()
    })

    $cancelPlanButton.Add_Click({
        $script:DiskPlanApproved = $false
        $planForm.Close()
    })

    $planScreenH = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height
    $desiredH = $yPos + 52 + ($planForm.Size.Height - $planForm.ClientSize.Height)
    $cappedH = [Math]::Min($desiredH, $planScreenH - 40)
    $planForm.ClientSize = New-Object System.Drawing.Size(702, ($yPos + 52))
    if ($desiredH -gt ($planScreenH - 40)) {
        $planForm.Size = New-Object System.Drawing.Size($planForm.Size.Width, $cappedH)
    }

    $planForm.ShowDialog($form)

    # Capture current partition count for later re-validation
    $currentPartCount = 0
    try {
        $currentPartCount = @(Get-Partition -DiskNumber $script:DiskPlanTargetDisk -ErrorAction Stop).Count
    } catch {}

    return @{
        Approved = $script:DiskPlanApproved
        Strategy = $script:DiskPlanStrategy
        TargetDiskNumber = $script:DiskPlanTargetDisk
        ShrinkDriveLetter = $script:DiskPlanShrinkLetter
        ShrinkAmountGB = $script:DiskPlanShrinkAmount
        LinuxSizeGB = [int]$sizeNumeric.Value
        UseRefind = $refindCheck.Checked
        UseExt4Boot = $ext4BootCheck.Checked
        ExpectedPartitionCount = $currentPartCount
    }
}
