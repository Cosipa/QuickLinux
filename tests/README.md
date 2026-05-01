# Tests

This directory contains Pester tests for QuickLinux.

## Running Tests

### Local (Windows)

```powershell
# Install Pester if not already installed
Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser

# Run tests
Invoke-Pester -Path ./tests -Output Detailed
```

### GitHub Actions

Tests run automatically on push to `main`/`develop` and on pull requests to
`main`.

## Test Coverage

- **disk.ps1**: `Get-BootPartSizeGB`, `Get-BootPartFsType`,
  `Get-PartitionLabel`, `Format-AfterLayout`
- **start.ps1**: `Get-DistroData` (JSON parsing)
- **download.ps1**: `Verify-ISOChecksum`, `Check-ISOExists`,
  `Download-DistroConfig`
- **wsl.ps1**: `Test-WslAvailable`, `Get-WslDefaultDistro`
- **Constants validation**: MinPartitionSizeGB, MinLinuxSizeGB, etc.

## Notes

- Tests use mocking heavily to avoid requiring admin privileges.
- GUI-dependent code: forms, button clicks, etc, are not tested.
- Disk operations are not tested in CI at this time.

