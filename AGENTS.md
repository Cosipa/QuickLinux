# QuickLinux Agent Guidelines

## Project Overview

QuickLinux is a tool for installing Linux distributions directly to a hard drive
without a USB stick, it runs on Windows and natively installs a Linux distro. It
provides a GUI interface for Windows (PowerShell/WindowsForms).

**Supported distributions:** Linux Mint 22.3, Ubuntu 24.04.4, Kubuntu 24.04.4,
Debian Live 13.3.0, Fedora 43 KDE

## Running the Project

### Dependencies

**Windows:**

- Ensure Windows 11 with Secure Boot enabled.

### Running the Application

**Windows:**

- Run the .bat file as an administrator by right clicking it --> run as
  administrator, this is needed to modify disk partitions and change boot
  settings.

### Windows (PowerShell) Conventions

**Function Naming:**

- Use PowerShell verb prefixes: `Get-*`, `Set-*`, `Start-*`, `Stop-*`, `Add-*`,
  `Remove-*`, `Invoke-*`
- CamelCase for parameter names

**Variable Naming:**

- Use `$script:variable` for module-scoped variables (preferred) or `$variable`
  for local
- Use CamelCase for variable names (preferred)

**Data Structures:**

- Use ordered dictionaries `[ordered]@{}` to maintain insertion order
- Consistent spacing around operators

**Code Structure:**

- PowerShell script block formatting with consistent indentation (usually 2
  spaces)
- Use `#` for comments
- Keep functions focused on single responsibilities

### Code Convention

**Documentation Comments:**

- Use Unicode box drawing characters: `# ─── constant ───────`
- Comment purpose and behavior immediately before code
- Reference specific sections when commenting complex logic

**Error Handling:**

- Always handle exceptions contextually with `try/catch` blocks
- Provide user-friendly error messages
- Log errors to console and UI
- Check return codes before processing output

**Constants:**

- Define module-level constants at the top of script
- Use clear meaningful names like `MIN_BOOT_GB`, `MIN_LINUX_GB`, `DISTROS`
- Group related constants in dictionaries or tables

**Code Execution:**

- Capture and validate command output
- Handle subprocess failures explicitly
- Use helper functions for common operations

### UI Development

**Windows:**

- Use `System.Windows.Forms` classes
- Enable visual styles with `EnableVisualStyles()`
- Follow WindowsForms control patterns
- Maintain consistent UI layout across platforms
- Use meaningful labels and error messages
- Provide progress feedback for long-running operations

