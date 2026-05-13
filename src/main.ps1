# Detect screen resolution and adapt window size
$primaryScreen = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$scrW = $primaryScreen.Width
$scrH = $primaryScreen.Height
if ($scrH -le 900) {
    $formW = 720
    $formH = [Math]::Min($scrH - 60, 560)
} else {
    $formW = 720
    $formH = 560
}

# Load distro data
$script:Distros = Get-DistroData
$script:DistroKeys = @($script:Distros.Keys)

# Create main form
$form = New-Object System.Windows.Forms.Form
$form.Text = "QuickLinux - USB-less Linux Installer"
$form.Size = New-Object System.Drawing.Size($formW, $formH)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "Sizable"
$form.MinimumSize = New-Object System.Drawing.Size(720, 480)
$form.AutoScroll = $true
$form.Icon = [System.Drawing.SystemIcons]::Application

# Create fonts
$headerFont = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$normalFont = New-Object System.Drawing.Font("Segoe UI", 9)
$boldFont = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

# Header label
$headerLabel = New-Object System.Windows.Forms.Label
$headerLabel.Text = "QuickLinux - USB-less Linux Installer"
$headerLabel.Font = $headerFont
$headerLabel.ForeColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
$headerLabel.Location = New-Object System.Drawing.Point(10, 10)
$headerLabel.Size = New-Object System.Drawing.Size(680, 30)
$headerLabel.TextAlign = "MiddleCenter"
$form.Controls.Add($headerLabel)

# Sub-header label
$subHeaderLabel = New-Object System.Windows.Forms.Label
$subHeaderLabel.Text = "Mint 22.3, Ubuntu 24.04.4, Kubuntu 24.04.4, Debian 13.3.0, or Fedora 43  |  No USB required"
$subHeaderLabel.Font = $normalFont
$subHeaderLabel.ForeColor = [System.Drawing.Color]::DimGray
$subHeaderLabel.Location = New-Object System.Drawing.Point(10, 42)
$subHeaderLabel.Size = New-Object System.Drawing.Size(680, 18)
$subHeaderLabel.TextAlign = "MiddleCenter"
$form.Controls.Add($subHeaderLabel)

# Status label
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Ready - download an ISO or use a custom one"
$statusLabel.Font = $normalFont
$statusLabel.Location = New-Object System.Drawing.Point(10, 62)
$statusLabel.Size = New-Object System.Drawing.Size(680, 20)
$statusLabel.TextAlign = "MiddleCenter"
$form.Controls.Add($statusLabel)

# Progress bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(10, 84)
$progressBar.Size = New-Object System.Drawing.Size(680, 14)
$progressBar.Style = "Continuous"
$form.Controls.Add($progressBar)

# ISO source group
$isoGroup = New-Object System.Windows.Forms.GroupBox
$isoGroup.Text = "Distribution"
$isoGroup.Font = $normalFont
$isoGroup.Location = New-Object System.Drawing.Point(10, 104)
$isoGroup.Size = New-Object System.Drawing.Size(680, 100)
$form.Controls.Add($isoGroup)

# ─── Distro dropdown list ─────────────────────────────────────────────────────
$distroCombo = New-Object System.Windows.Forms.ComboBox
$distroCombo.Font = $boldFont
$distroCombo.Location = New-Object System.Drawing.Point(10, 22)
$distroCombo.Size = New-Object System.Drawing.Size(650, 24)
$distroCombo.ForeColor = [System.Drawing.Color]::Black
$distroCombo.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
foreach ($distroId in $script:DistroKeys) {
    $distroCombo.Items.Add($script:Distros[$distroId].RadioLabel) | Out-Null
}
if ($distroCombo.Items.Count -gt 0) {
    $distroCombo.SelectedIndex = 0
}
$isoGroup.Controls.Add($distroCombo)

# Custom ISO checkbox
$customRadio = New-Object System.Windows.Forms.CheckBox
$customRadio.Text = "Use existing ISO file:"
$customRadio.Font = $normalFont
$customRadio.Location = New-Object System.Drawing.Point(10, 56)
$customRadio.Size = New-Object System.Drawing.Size(160, 20)
$isoGroup.Controls.Add($customRadio)

# Custom ISO path textbox
$customIsoTextbox = New-Object System.Windows.Forms.TextBox
$customIsoTextbox.Font = $normalFont
$customIsoTextbox.Location = New-Object System.Drawing.Point(172, 54)
$customIsoTextbox.Size = New-Object System.Drawing.Size(388, 24)
$customIsoTextbox.ReadOnly = $true
$customIsoTextbox.Enabled = $false
$isoGroup.Controls.Add($customIsoTextbox)

# Browse button
$browseButton = New-Object System.Windows.Forms.Button
$browseButton.Text = "Browse..."
$browseButton.Font = $normalFont
$browseButton.Location = New-Object System.Drawing.Point(568, 53)
$browseButton.Size = New-Object System.Drawing.Size(100, 26)
$browseButton.Enabled = $false
$isoGroup.Controls.Add($browseButton)

# ─── Step 1: Download ISO ─────────────────────────────────────────────────────
$step1Group = New-Object System.Windows.Forms.GroupBox
$step1Group.Text = "Step 1: Download Linux ISO"
$step1Group.Font = $normalFont
$step1Group.Location = New-Object System.Drawing.Point(10, 214)
$step1Group.Size = New-Object System.Drawing.Size(680, 60)
$form.Controls.Add($step1Group)

$downloadButton = New-Object System.Windows.Forms.Button
$downloadButton.Text = "Download ISO"
$downloadButton.Font = $boldFont
$downloadButton.Location = New-Object System.Drawing.Point(10, 24)
$downloadButton.Size = New-Object System.Drawing.Size(130, 28)
$downloadButton.BackColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
$downloadButton.ForeColor = [System.Drawing.Color]::White
$downloadButton.FlatStyle = "Flat"
$step1Group.Controls.Add($downloadButton)

$isoStatus = New-Object System.Windows.Forms.Label
$isoStatus.Text = "Status: Not downloaded"
$isoStatus.Font = $normalFont
$isoStatus.Location = New-Object System.Drawing.Point(150, 28)
$isoStatus.Size = New-Object System.Drawing.Size(520, 20)
$step1Group.Controls.Add($isoStatus)

# ─── Step 2: Prepare Boot ─────────────────────────────────────────────────────
$step2Group = New-Object System.Windows.Forms.GroupBox
$step2Group.Text = "Step 2: Prepare Boot Partition"
$step2Group.Font = $normalFont
$step2Group.Location = New-Object System.Drawing.Point(10, 284)
$step2Group.Size = New-Object System.Drawing.Size(680, 80)
$form.Controls.Add($step2Group)

$prepareButton = New-Object System.Windows.Forms.Button
$prepareButton.Text = "Prepare Boot"
$prepareButton.Font = $boldFont
$prepareButton.Location = New-Object System.Drawing.Point(10, 24)
$prepareButton.Size = New-Object System.Drawing.Size(130, 28)
$prepareButton.BackColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
$prepareButton.ForeColor = [System.Drawing.Color]::White
$prepareButton.FlatStyle = "Flat"
$prepareButton.Enabled = $false
$step2Group.Controls.Add($prepareButton)

$infoBox = New-Object System.Windows.Forms.Label
$infoBox.Text = [char]0x2139 + " This prepares your computer to boot into a Linux live session. After rebooting, run the Linux installer from within the live session to complete the installation."
$infoBox.Font = $normalFont
$infoBox.ForeColor = [System.Drawing.Color]::DimGray
$infoBox.Location = New-Object System.Drawing.Point(150, 24)
$infoBox.Size = New-Object System.Drawing.Size(520, 40)
$step2Group.Controls.Add($infoBox)

# ─── Disk info group ──────────────────────────────────────────────────────────
$diskGroup = New-Object System.Windows.Forms.GroupBox
$diskGroup.Text = "Disk Information"
$diskGroup.Font = $normalFont
$diskGroup.Location = New-Object System.Drawing.Point(10, 374)
$diskGroup.Size = New-Object System.Drawing.Size(680, 100)
$form.Controls.Add($diskGroup)

$diskInfoText = New-Object System.Windows.Forms.TextBox
$diskInfoText.Multiline = $true
$diskInfoText.ReadOnly = $true
$diskInfoText.ScrollBars = "Vertical"
$diskInfoText.Font = $normalFont
$diskInfoText.Location = New-Object System.Drawing.Point(10, 20)
$diskInfoText.Size = New-Object System.Drawing.Size(660, 70)
$diskInfoText.BorderStyle = "None"
$diskInfoText.TabStop = $false
$diskGroup.Controls.Add($diskInfoText)

# ─── Advanced Options (collapsed by default) ──────────────────────────────────
$advancedToggle = New-Object System.Windows.Forms.Button
$advancedToggle.Text = "Show Advanced Options +"
$advancedToggle.Font = $normalFont
$advancedToggle.Location = New-Object System.Drawing.Point(10, 484)
$advancedToggle.Size = New-Object System.Drawing.Size(180, 26)
$advancedToggle.FlatStyle = "Flat"
$form.Controls.Add($advancedToggle)

$advancedPanel = New-Object System.Windows.Forms.Panel
$advancedPanel.Location = New-Object System.Drawing.Point(10, 514)
$advancedPanel.Size = New-Object System.Drawing.Size(680, 200)
$advancedPanel.Visible = $false
$form.Controls.Add($advancedPanel)

# rEFInd checkbox (inside advanced panel)
$refindCheck = New-Object System.Windows.Forms.CheckBox
$refindCheck.Text = "Install rEFInd boot manager - requires disabling Secure Boot"
$refindCheck.Font = $normalFont
$refindCheck.Location = New-Object System.Drawing.Point(0, 0)
$refindCheck.Size = New-Object System.Drawing.Size(680, 25)
$refindCheck.Checked = $false
$advancedPanel.Controls.Add($refindCheck)

# ext4 boot partition checkbox
$ext4BootCheck = New-Object System.Windows.Forms.CheckBox
$ext4BootCheck.Text = "Use ext4 boot partition (12 GB) instead of FAT32 (7 GB) - requires WSL + rEFInd"
$ext4BootCheck.Font = $normalFont
$ext4BootCheck.Location = New-Object System.Drawing.Point(0, 25)
$ext4BootCheck.Size = New-Object System.Drawing.Size(680, 25)
$ext4BootCheck.Checked = $false
$advancedPanel.Controls.Add($ext4BootCheck)

# Delete ISO checkbox
$deleteIsoCheck = New-Object System.Windows.Forms.CheckBox
$deleteIsoCheck.Text = "Delete ISO file after installation"
$deleteIsoCheck.Font = $normalFont
$deleteIsoCheck.Location = New-Object System.Drawing.Point(0, 50)
$deleteIsoCheck.Size = New-Object System.Drawing.Size(300, 25)
$deleteIsoCheck.Checked = $true
$advancedPanel.Controls.Add($deleteIsoCheck)

# Auto-restart checkbox
$autoRestartCheck = New-Object System.Windows.Forms.CheckBox
$autoRestartCheck.Text = "Automatically restart and configure UEFI boot"
$autoRestartCheck.Font = $normalFont
$autoRestartCheck.Location = New-Object System.Drawing.Point(0, 75)
$autoRestartCheck.Size = New-Object System.Drawing.Size(350, 25)
$autoRestartCheck.Checked = $true
$advancedPanel.Controls.Add($autoRestartCheck)

# Log group (inside advanced panel)
$logGroup = New-Object System.Windows.Forms.GroupBox
$logGroup.Text = "System Log"
$logGroup.Font = $normalFont
$logGroup.Location = New-Object System.Drawing.Point(0, 100)
$logGroup.Size = New-Object System.Drawing.Size(680, 90)
$advancedPanel.Controls.Add($logGroup)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = "Vertical"
$logBox.ReadOnly = $true
$logBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logBox.Location = New-Object System.Drawing.Point(10, 20)
$logBox.Size = New-Object System.Drawing.Size(660, 60)
$logGroup.Controls.Add($logBox)

# ─── Buttons ──────────────────────────────────────────────────────────────────
$exitButton = New-Object System.Windows.Forms.Button
$exitButton.Text = "Exit"
$exitButton.Font = $normalFont
$exitButton.Location = New-Object System.Drawing.Point(550, 484)
$exitButton.Size = New-Object System.Drawing.Size(140, 35)
$form.Controls.Add($exitButton)

# ============================================================
# EVENT HANDLERS
# ============================================================

# Event handlers
$downloadButton.Add_Click({
    Start-DownloadISO
})

$prepareButton.Add_Click({
    Start-PrepareBoot
})

$advancedToggle.Add_Click({
    $script:AdvancedVisible = -not $script:AdvancedVisible
    $advancedPanel.Visible = $script:AdvancedVisible
    if ($script:AdvancedVisible) {
        $advancedToggle.Text = "Hide Advanced Options -"
        $form.Height = 760
    } else {
        $advancedToggle.Text = "Show Advanced Options +"
        $form.Height = 560
    }
    $form.Refresh()
})

$exitButton.Add_Click({
    if ($script:IsRunning) {
        $result = [System.Windows.Forms.MessageBox]::Show(
            "An operation is in progress. Exiting now may leave your disk in an inconsistent state.`n`n" +
            "It is strongly recommended to let it complete or fail naturally.`n`n" +
            "If you exit, any partial partitions created will remain on disk and may need manual cleanup.`n`n" +
            "Are you sure you want to exit?",
            "Confirm Exit",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )

        if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
            $script:CancelRequested = $true
            Log-Message "User requested cancellation. Waiting for current operation to complete..."
            Set-Status "Cancelling..."
            Start-Sleep -Seconds 2
            $form.Close()
        }
    } else {
        $form.Close()
    }
})

$customRadio.Add_CheckedChanged({
    if ($customRadio.Checked) {
        $customIsoTextbox.Enabled = $true
        $browseButton.Enabled = $true
        $distroCombo.Enabled = $false
        $downloadButton.Enabled = $false
    } else {
        $customIsoTextbox.Enabled = $false
        $browseButton.Enabled = $false
        $distroCombo.Enabled = $true
        $script:CustomIsoPath = ""
        $customIsoTextbox.Text = ""
    }
    Update-ISOStatus
})

# ext4 boot checkbox interlock with rEFInd
$ext4BootCheck.Add_CheckedChanged({
    if ($ext4BootCheck.Checked) {
        if (-not $refindCheck.Checked) {
            $refindCheck.Checked = $true
        }
    }
})

$refindCheck.Add_CheckedChanged({
    if (-not $refindCheck.Checked -and $ext4BootCheck.Checked) {
        $ext4BootCheck.Checked = $false
    }
})

$distroCombo.Add_SelectedIndexChanged({
    Update-ISOStatus
})

$browseButton.Add_Click({
    $openFileDialog = New-Object System.Windows.Forms.OpenFileDialog
    $openFileDialog.Title = "Select Linux ISO File"
    $openFileDialog.Filter = "ISO Files (*.iso)|*.iso|All Files (*.*)|*.*"
    $openFileDialog.FilterIndex = 1
    $openFileDialog.RestoreDirectory = $true

    if ($openFileDialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $script:CustomIsoPath = $openFileDialog.FileName
        $customIsoTextbox.Text = $script:CustomIsoPath

        $fileInfo = Get-Item $script:CustomIsoPath
        $fileSizeGB = [math]::Round($fileInfo.Length / 1GB, 2)
        Log-Message "Selected ISO: $(Split-Path -Leaf $script:CustomIsoPath)"
        Log-Message "File size: $fileSizeGB GB"
        Update-ISOStatus
    }
})

# Initialize
Update-DiskInfo
Update-ISOStatus

# Show form
$form.ShowDialog() | Out-Null
