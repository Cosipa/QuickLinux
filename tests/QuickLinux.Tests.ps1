BeforeAll {
    $script:SrcPath = Join-Path $PSScriptRoot "..\src"

    # Provide embedded JSON to avoid Get-Content issues
    $script:DistrosJson = @"
{
    "ubuntu": {
        "name": "Ubuntu 24.04.4 LTS",
        "radio_label": "Ubuntu 24.04.4 LTS",
        "expected_size": "4.5 GB",
        "mirrors": ["https://releases.ubuntu.com/24.04/ubuntu-24.04.2-desktop-amd64.iso"],
        "checksum": "abc123def456",
        "iso_filename": "ubuntu-24.04.2-desktop-amd64.iso",
        "download_page": "https://ubuntu.com/download/desktop",
        "download_msg": "Downloading Ubuntu",
        "keyword": "ubuntu",
        "validation_file": "SHA256SUMS",
        "is_hybrid": true
    }
}
"@

    # Aggressive mocking - block everything that could slow tests down
    Mock Invoke-WebRequest { return $null }
    Mock Invoke-RestMethod { return $null }
    Mock Get-FileHash { return @{ Hash = "fake" } }
    Mock Test-Path { return $true }
    Mock Get-Content { return $null }
    Mock Get-ChildItem { return @() }
    Mock Start-Process { }
    Mock Write-Host { }
    Mock Read-Host { }
    Mock Get-Partition { return @() }
    Mock Get-Volume { return @() }
    Mock Get-Disk { return @() }

    # Mock WSL commands - default to empty (no distros)
    Mock wsl { return "" }
    Mock Get-Command { return $null }

    # Load individual source files - only the functions, skip GUI code
    . "$script:SrcPath\start.ps1"
    . "$script:SrcPath\disk.ps1"
    . "$script:SrcPath\download.ps1"
    . "$script:SrcPath\wsl.ps1"
    . "$script:SrcPath\ui.ps1"

    # Mock Log-Message function AFTER loading ui.ps1 so it overrides
    Remove-Item Function:\Log-Message -ErrorAction SilentlyContinue
    Remove-Item Function:\Set-Status -ErrorAction SilentlyContinue
    Remove-Item Function:\Get-SelectedDistro -ErrorAction SilentlyContinue
    
    function global:Log-Message { param($Message, [switch]$Error) }
    function global:Set-Status { param($Status) }
    function global:Get-SelectedDistro { return @{ Checksum = "abc123" } }
}

Describe "Get-BootPartSizeGB" {
    It "Returns 7 when ext4BootCheck is unchecked" {
        $global:ext4BootCheck = @{ Checked = $false }
        Get-BootPartSizeGB | Should -Be 7
    }

    It "Returns 12 when ext4BootCheck is checked" {
        $global:ext4BootCheck = @{ Checked = $true }
        Get-BootPartSizeGB | Should -Be 12
    }
}

Describe "Get-BootPartFsType" {
    It "Returns FAT32 when ext4BootCheck is unchecked" {
        $global:ext4BootCheck = @{ Checked = $false }
        Get-BootPartFsType | Should -Be "FAT32"
    }

    It "Returns ext4 when ext4BootCheck is checked" {
        $global:ext4BootCheck = @{ Checked = $true }
        Get-BootPartFsType | Should -Be "ext4"
    }
}

Describe "Get-PartitionLabel" {
    It "Returns correct label for C: drive" {
        $part = @{ DriveLetter = 'C' }
        Get-PartitionLabel -Part $part | Should -Be "C: (Windows/NTFS)    "
    }

    It "Returns Recovery for recovery partition" {
        $part = @{ DriveLetter = $null; Type = "Recovery" }
        Get-PartitionLabel -Part $part | Should -Be "Recovery             "
    }

    It "Returns EFI System label for ESP partition" {
        $part = @{ DriveLetter = $null; IsSystem = $true }
        Get-PartitionLabel -Part $part | Should -Be "EFI System (ESP)     "
    }

    It "Returns Microsoft Reserved for MSR" {
        $part = @{ DriveLetter = $null; GptType = "e3c9e316-0b5e-11d3-baa1-08002b2f1111" }
        Get-PartitionLabel -Part $part | Should -Be "Microsoft Reserved   "
    }

    It "Returns generic Partition label for unknown" {
        $part = @{ DriveLetter = $null; Type = "Basic" }
        Get-PartitionLabel -Part $part | Should -Be "Partition            "
    }
}

Describe "Format-AfterLayout" {
    It "Returns formatted lines when shrinking a partition" {
        $partitions = @(
            @{ DriveLetter = 'C'; Size = 500GB; Type = "Basic" }
        )
        $result = Format-AfterLayout -Partitions $partitions -DistroName "Test" -BootPartSizeGB 7 -LinuxSizeGB 50 -ShrinkLetter "C" -NewShrinkSizeGB 400 -BootPartFsType "FAT32"
        $result | Should -Not -BeNullOrEmpty
        ($result -join "`n") | Should -Match "shrunk"
    }

    It "Handles append mode with unallocated space" {
        $partitions = @(
            @{ DriveLetter = 'C'; Size = 500GB; Type = "Basic" }
        )
        $result = Format-AfterLayout -Partitions $partitions -DistroName "Test" -BootPartSizeGB 7 -RemainingFreeGB 100 -AppendLinuxAndBoot -BootPartFsType "FAT32"
        $result | Should -Not -BeNullOrEmpty
        ($result -join "`n") | Should -Match "Unallocated"
    }

    It "Shows unchanged label when requested" {
        $partitions = @(
            @{ DriveLetter = 'C'; Size = 500GB; Type = "Basic" }
        )
        $result = Format-AfterLayout -Partitions $partitions -DistroName "Test" -BootPartSizeGB 7 -ShowUnchanged -BootPartFsType "FAT32"
        $result | Should -Match "unchanged"
    }

    It "Includes rEFInd entry when UseRefind is specified" {
        $partitions = @(
            @{ DriveLetter = 'C'; Size = 500GB; Type = "Basic" }
        )
        $result = Format-AfterLayout -Partitions $partitions -DistroName "Test" -BootPartSizeGB 7 -UseRefind -AppendLinuxAndBoot -BootPartFsType "FAT32"
        ($result -join "`n") | Should -Match "rEFInd"
    }

    It "Uses ext4 fs type in output when specified" {
        $partitions = @(
            @{ DriveLetter = 'C'; Size = 500GB; Type = "Basic" }
        )
        $result = Format-AfterLayout -Partitions $partitions -DistroName "Test" -BootPartSizeGB 12 -AppendLinuxAndBoot -BootPartFsType "ext4"
        ($result -join "`n") | Should -Match "ext4"
    }
}

Describe "Get-DistroData" {
    It "Returns an ordered dictionary" {
        $result = Get-DistroData
        $result | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
    }

    It "Contains ubuntu key" {
        $result = Get-DistroData
        $result.Keys | Should -Contain "ubuntu"
    }
}

Describe "Verify-ISOChecksum" {
    It "Returns true when checksum matches" {
        Mock Get-FileHash { return @{ Hash = "abc123" } }
        
        $result = Verify-ISOChecksum -FilePath "test.iso"
        $result | Should -Be $true
    }
}

Describe "Test-WslAvailable" {
    It "Returns false when wsl command returns empty" {
        $result = Test-WslAvailable
        $result | Should -Be $false
    }
}

Describe "Constants" {
    It "MinPartitionSizeGB is at least 7" {
        $script:MinPartitionSizeGB | Should -BeGreaterOrEqual 7
    }

    It "MinLinuxSizeGB is at least 20" {
        $script:MinLinuxSizeGB | Should -BeGreaterOrEqual 20
    }

    It "MinPartitionSizeGBExt4 is greater than MinPartitionSizeGB" {
        $script:MinPartitionSizeGBExt4 | Should -BeGreaterThan $script:MinPartitionSizeGB
    }

    It "RetryAttempts is at least 1" {
        $script:RetryAttempts | Should -BeGreaterOrEqual 1
    }

    It "RetryDelaySec is at least 1" {
        $script:RetryDelaySec | Should -BeGreaterOrEqual 1
    }
}