function Download-DistroConfig {
    $url = "https://raw.githubusercontent.com/Cosipa/QuickLinux/main/distros.json"
    $dest = Join-Path $env:TEMP "distros.json"

    try {
        $wc = New-Object System.Net.WebClient
        $wc.Timeout = 10000
        $wc.DownloadFile($url, $dest)

        if (Test-Path $dest) {
            return $dest
        }
    } catch {}
    return $null
}
function Check-ISOExists {
    if ($customRadio.Checked) {
        if ($script:CustomIsoPath -and (Test-Path $script:CustomIsoPath)) {
            return @{ State = "found"; Path = $script:CustomIsoPath }
        }
        return @{ State = "missing"; Path = "" }
    }

    $distro = Get-SelectedDistro
    $isoPath = Join-Path $env:TEMP $distro.IsoFilename

    if (Test-Path $isoPath) {
        $fileInfo = Get-Item $isoPath
        if ($fileInfo.Length -ge 2GB) {
            $fileSizeGB = [math]::Round($fileInfo.Length / 1GB, 2)
            return @{ State = "found"; Path = $isoPath; SizeGB = $fileSizeGB; DistroName = $distro.Name }
        } else {
            # Partial download - delete it
            Log-Message "Found partial ISO ($([math]::Round($fileInfo.Length / 1GB, 2)) GB), deleting..."
            Remove-Item $isoPath -Force -ErrorAction SilentlyContinue
        }
    }

    return @{ State = "missing"; Path = ""; SizeGB = 0; DistroName = $distro.Name }
}
function Verify-ISOChecksum {
    param(
        [string]$FilePath
    )

    Log-Message "Verifying ISO checksum..."
    Set-Status "Verifying ISO integrity..."

    try {
        $distro = Get-SelectedDistro
        $expectedHash = $distro.Checksum
        Log-Message "Expected SHA256: $expectedHash"

        Log-Message "Calculating SHA256 checksum of downloaded ISO (this may take a minute)..."
        $actualHash = (Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLower()
        Log-Message "Actual SHA256:   $actualHash"

        if ($actualHash -eq $expectedHash) {
            Log-Message "[PASS] Checksum verification PASSED - ISO is authentic!"
            return $true
        } else {
            Log-Message "[FAIL] Checksum verification FAILED - ISO may be corrupted or tampered!" -Error

            $response = [System.Windows.Forms.MessageBox]::Show(
                "The ISO file checksum does not match the expected checksum!`n`n" +
                "Expected: $expectedHash`n" +
                "Actual:   $actualHash`n`n" +
                "This could mean the file is corrupted or has been tampered with.`n" +
                "Do you want to delete it and re-download?",
                "Checksum Verification Failed",
                [System.Windows.Forms.MessageBoxButtons]::YesNo,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )

            if ($response -eq [System.Windows.Forms.DialogResult]::Yes) {
                try {
                    Remove-Item $FilePath -Force
                    Log-Message "Corrupted ISO deleted"
                } catch {
                    Log-Message "Error deleting ISO: $_" -Error
                }
            }

            return $false
        }
    }
    catch {
        Log-Message "Error calculating checksum: $_" -Error

        $response = [System.Windows.Forms.MessageBox]::Show(
            "Unable to verify the ISO checksum. Error: $_`n`n" +
            "Do you want to continue anyway?",
            "Checksum Verification Error",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        return ($response -eq [System.Windows.Forms.DialogResult]::Yes)
    }
}
function Download-LinuxISO {
    param(
        [string]$Destination
    )

    $distro = Get-SelectedDistro
    $isoName = $distro.Name
    $expectedSize = $distro.ExpectedSize
    $mirrors = $distro.Mirrors

    # Check available disk space before downloading
    $destDir = Split-Path -Parent $Destination
    if ($destDir -and (Test-Path $destDir)) {
        $drive = [System.IO.DriveInfo]::new($destDir.TrimEnd('\'))
        $freeGB = [math]::Round($drive.AvailableFreeSpace / 1GB, 1)
        if ($freeGB -lt 5) {
            Log-Message "Insufficient disk space: need at least 5 GB, have $freeGB GB" -Error
            return $false
        }
        Log-Message "Available space on $drive`: $freeGB GB"
    }

    Log-Message "Downloading $isoName ISO ($expectedSize)..."
    Log-Message "This may take a while depending on your internet speed..."

    foreach ($i in 0..($mirrors.Count - 1)) {
        $mirror = $mirrors[$i]
        Log-Message "Trying mirror $($i + 1)/$($mirrors.Count): $($mirror.Split('/')[2])"
        Set-Status "Connecting to mirror..."

        try {
            Add-Type -AssemblyName System.Net.Http

            $httpClient = New-Object System.Net.Http.HttpClient
            $httpClient.Timeout = [TimeSpan]::FromMinutes(60)

            $response = $httpClient.GetAsync($mirror, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).Result

            if ($response.IsSuccessStatusCode) {
                $totalBytes = $response.Content.Headers.ContentLength
                $totalMB = [math]::Round($totalBytes / 1MB, 1)
                Log-Message "File size: $totalMB MB"

                $fileStream = [System.IO.File]::Create($Destination)
                $downloadStream = $response.Content.ReadAsStreamAsync().Result

                $buffer = New-Object byte[] 81920
                $totalRead = 0
                $lastUpdate = [DateTime]::Now
                $updateInterval = [TimeSpan]::FromMilliseconds(500)

                Set-Status "Downloading..."

                while ($true) {
                    $bytesRead = $downloadStream.Read($buffer, 0, $buffer.Length)

                    if ($bytesRead -eq 0) {
                        break
                    }

                    $fileStream.Write($buffer, 0, $bytesRead)
                    $totalRead += $bytesRead

                    $now = [DateTime]::Now
                    if (($now - $lastUpdate) -gt $updateInterval) {
                        $percent = [int](($totalRead / $totalBytes) * 100)
                        $mbDownloaded = [math]::Round($totalRead / 1MB, 1)

                        $progressBar.Value = $percent
                        Set-Status "Downloading: $percent% - $mbDownloaded MB / $totalMB MB"

                        [System.Windows.Forms.Application]::DoEvents()
                        $lastUpdate = $now
                    }
                }

                $fileStream.Close()
                $downloadStream.Close()
                $response.Dispose()
                $httpClient.Dispose()

                $progressBar.Value = 100
                Set-Status "Download complete!"
                Start-Sleep -Milliseconds 500
                $progressBar.Value = 0
                $statusLabel.Text = ""

                $fileInfo = Get-Item $Destination
                $fileSizeGB = [math]::Round($fileInfo.Length / 1GB, 2)
                Log-Message "Downloaded file size: $fileSizeGB GB"

                if ($fileInfo.Length -lt 2GB) {
                    Log-Message "File size too small, download may be corrupted" -Error
                    Remove-Item $Destination -Force
                    continue
                }

                if (-not (Verify-ISOChecksum -FilePath $Destination)) {
                    Log-Message "Checksum verification failed, trying next mirror..." -Error
                    continue
                }

                return $true
            } else {
                throw "HTTP Error: $($response.StatusCode)"
            }
        }
        catch {
            Log-Message "Download failed: $_" -Error

            if (Test-Path $Destination) {
                try {
                    Remove-Item $Destination -Force -ErrorAction SilentlyContinue
                    Log-Message "Removed incomplete download"
                } catch {}
            }

            if ($i -lt $mirrors.Count - 1) {
                Log-Message "Trying next mirror..."
            }
        }
    }

    # All mirrors failed
    Log-Message "All automatic download attempts failed" -Error

    $response = [System.Windows.Forms.MessageBox]::Show(
        "Automatic download failed. Would you like to:`n`n" +
        "- Download manually from your browser?`n" +
        "- Place the file at: $Destination`n" +
        "- Then run the installer again`n`n" +
        "Click Yes to open the $isoName download page, No to cancel",
        "Download Failed",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information
    )

    if ($response -eq [System.Windows.Forms.DialogResult]::Yes) {
        Start-Process $distro.DownloadPage
        Log-Message $distro.DownloadMsg
        Log-Message $Destination
        Log-Message "Then run the installer again"
    }

    return $false
}
function Download-Refind {
    $dest = Join-Path $env:TEMP $script:RefindFilename
    if (Test-Path $dest) {
        Log-Message "Found cached rEFInd: $dest"
        return $dest
    }
    Log-Message "Downloading rEFInd boot manager..."
    Set-Status "Downloading rEFInd..."
    try {
        Add-Type -AssemblyName System.Net.Http
        $handler = New-Object System.Net.Http.HttpClientHandler
        $handler.AllowAutoRedirect = $true
        $httpClient = New-Object System.Net.Http.HttpClient($handler)
        $httpClient.Timeout = [TimeSpan]::FromMinutes(10)
        $httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("windows-installer/1.0")

        $response = $httpClient.GetAsync(
            $script:RefindUrl,
            [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
        ).Result

        if ($response.IsSuccessStatusCode) {
            $totalBytes = $response.Content.Headers.ContentLength
            $fileStream = [System.IO.File]::Create($dest)
            $downloadStream = $response.Content.ReadAsStreamAsync().Result
            $buffer = New-Object byte[] 81920
            $totalRead = [int64]0
            $lastUpdate = [DateTime]::Now

            while ($true) {
                $bytesRead = $downloadStream.Read($buffer, 0, $buffer.Length)
                if ($bytesRead -eq 0) { break }
                $fileStream.Write($buffer, 0, $bytesRead)
                $totalRead += $bytesRead
                $now = [DateTime]::Now
                if (($now - $lastUpdate).TotalMilliseconds -gt 500) {
                    if ($totalBytes -gt 0) {
                        $percent = [int](($totalRead / $totalBytes) * 100)
                        Set-Status "Downloading rEFInd... $percent%"
                    }
                    [System.Windows.Forms.Application]::DoEvents()
                    $lastUpdate = $now
                }
            }

            $fileStream.Close()
            $downloadStream.Close()
            $response.Dispose()
            $httpClient.Dispose()

            $sizeMB = [math]::Round((Get-Item $dest).Length / 1MB, 1)
            Log-Message "rEFInd downloaded: $sizeMB MB"

            # Verify checksum
            if ($script:RefindSha256) {
                Log-Message "Verifying rEFInd checksum..."
                $actualHash = (Get-FileHash -Path $dest -Algorithm SHA256).Hash.ToLower()
                if ($actualHash -ne $script:RefindSha256.ToLower()) {
                    Log-Message "rEFInd checksum mismatch! Expected $($script:RefindSha256), got $actualHash" -Error
                    Remove-Item $dest -Force
                    Set-Status ""
                    return $null
                }
                Log-Message "rEFInd checksum verified."
            }

            Set-Status ""
            return $dest
        } else {
            throw "HTTP Error: $($response.StatusCode)"
        }
    }
    catch {
        Log-Message "rEFInd download failed: $_" -Error
        if (Test-Path $dest) { Remove-Item $dest -Force }
        return $null
    }
}
function Start-DownloadISO {
    if ($script:IsRunning) { return }
    $script:IsRunning = $true
    Set-UILocked $true
    $downloadButton.Enabled = $false
    $prepareButton.Enabled = $false

    $distro = Get-SelectedDistro
    $script:IsoPath = Join-Path $env:TEMP $distro.IsoFilename

    try {
        if (Download-LinuxISO -Destination $script:IsoPath) {
            $script:IsoDownloaded = $true
            Log-Message "ISO download complete. Click 'Prepare Boot' when ready."
            Set-Status "ISO ready - click 'Prepare Boot' to continue"
            $fileInfo = Get-Item $script:IsoPath
            $fileSizeGB = [math]::Round($fileInfo.Length / 1GB, 2)
            $isoStatus.Text = "Status: ISO verified - proceed with Step 2"
            $downloadButton.BackColor = [System.Drawing.Color]::FromArgb(180, 180, 180)
            $downloadButton.ForeColor = [System.Drawing.Color]::FromArgb(100, 100, 100)
            $downloadButton.Enabled = $false
            $prepareButton.Enabled = $true
        } else {
            $script:IsoDownloaded = $false
            Set-Status "Download failed"
            $isoStatus.Text = "Status: Download failed"
            $downloadButton.BackColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
            $downloadButton.ForeColor = [System.Drawing.Color]::White
            $downloadButton.Enabled = $true
            $prepareButton.Enabled = $false
        }
    }
    catch {
        Log-Message "Download error: $_" -Error
        $script:IsoDownloaded = $false
        Set-Status "Download failed"
        $isoStatus.Text = "Status: Download failed"
        $downloadButton.BackColor = [System.Drawing.Color]::FromArgb(135, 185, 74)
        $downloadButton.ForeColor = [System.Drawing.Color]::White
        $downloadButton.Enabled = $true
        $prepareButton.Enabled = $false
    }
    finally {
        $script:IsRunning = $false
        Set-UILocked $false
    }
}
