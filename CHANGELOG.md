# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.0.1-beta] - 2026-04-26

### Fixed

- Auto-elevation now works correctly when running via `irm | iex` without closing the PowerShell window

### Added

- One-liner installation via PowerShell (`irm "https://cosipa.dev/quicklinux" | iex`)
- Modular source architecture: split monolithic script into domain-specific modules
- GitHub Actions CI pipeline for automated builds and releases
- Support for Fedora 43 KDE, Debian Live 13.3.0 KDE
- WSL2-based ext4 boot partition option
- rEFInd boot manager integration
- Disk plan dialog with visual layout preview
- Auto-restart with countdown timer
- ISO integrity verification (SHA256 checksums)

### Changed

- Complete UI redesign with Windows Forms
- Simplified README with top-level usage instructions
- Refactored from single 4,646-line script into focused modules

### Removed

- Batch file launcher (replaced by one-liner)
- Local Compile.ps1 build script (CI handles compilation)
- Compiled artifact from source control

## Acknowledgements

QuickLinux is a fork of [ulli](https://github.com/rltvty2/ulli) by rltvty2,
licensed under GPL v3.0. The original project provided the foundation for
USB-less Linux installation.
