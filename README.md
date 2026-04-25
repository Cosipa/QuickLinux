# QuickLinux: USB-less Linux Installer

Install a bootable Linux partition to your hard drive without a USB stick or
manual BIOS configuration, meant to be easy for newcomers to Linux to install a
distribution, after running the program and filling up the details of your
instalation you will boot to the distro installer that you chose, from there you
will be able to install the distribution fully.

## How to use QuickLinux

QuickLinux must be run in Admin mode because it modifies disk partitions and
boot settings. Here are a few ways to open PowerShell as administrator:

1. **Start menu Method:**
   - Right-click on the start menu.
   - Choose "Windows PowerShell (Admin)" (for Windows 10) or "Terminal (Admin)"
     (for Windows 11).

2. **Search and Launch Method:**
   - Press the Windows key.
   - Type "PowerShell" or "Terminal" (for Windows 11).
   - Press `Ctrl + Shift + Enter` or right-click and choose "Run as
     administrator" to launch it with administrator privileges.

### Launch Command

Run QuickLinux with a single command:

```ps1
irm "https://cosipa.dev/quicklinux" | iex
```

> [!NOTE]
> After running the command, a window will appear asking for administrator
> access - this is normal and required for disk modifications.

## What this tool does

Normally, installing Linux requires downloading an ISO, flashing it to a USB
stick, booting from that USB, and then running the linux installer from a live
environment. QuickLinux skips the USB part.

### How it works

1. **Run QuickLinux:** pick your distro and target disk space.

2. **QuickLinux prepares your drive:** it downloads the Linux ISO and creates a
   small bootable partition containing the Linux live environment.

3. **Reboot:** your computer boots into the live environment (e.g., Linux Mint).

4. **Run the installer:** from inside the live session, click the "Install" icon
   on the desktop and follow the distro's normal installation steps. **Linux is
   NOT installed yet at this point, you have to go through the installer of the
   distribution.**

5. **After installation:** the computer will reboot and show your fully
   installed Linux desktop, you may use a disk partitioning tool to free up
   space from the installer and expand the Linux partition (optional yet
   recommended).

### Who this is for

Anyone who wants to **dual-boot Linux alongside Windows** (or another Linux
distro) without a USB drive. You don't need to fiddle with BIOS boot menus.
QuickLinux handles the boot entry automatically as well.

> [!WARNING]
> This program modifies your disk's partition table and UEFI boot configuration.
> Errors during this process may leave your system unbootable and require manual
> recovery. In the rare situation where this could occur, most windows
> installations can be fully recovered by typing `bcdboot C:\Windows` in the
> command prompt inside the Windows recovery environment and hitting Enter.
> Backing up your data before use is recommended. Use at your own risk.

> [!INFO]
> You can access the Windows filesystem from your newly installed Linux
> dual-boot setup, that means you can copy files from Windows to Linux.

---

**Acknowledgement:** AI was used in the development of this software. The code
has however been tested and is safe.

---

## rEFInd

QuickLinux includes an option to install the boot manager rEFInd
(https://www.rodsbooks.com/refind/). This requires disabling secure boot.

## Important Notes

- You may have to disable bitlocker/decrypt your hard drive to use this
  software.

- You may have to disable Secure Boot in the BIOS depending on your computer.

- Currently the installer supports the installation of **Linux Mint 22.3
  Cinnamon**, **Ubuntu 24.04.4 LTS**, **Kubuntu 24.04.4 LTS**, **Debian Live
  13.3.0 KDE**, and **Fedora 43 - KDE Plasma Desktop**. You may also use your
  own `.iso` files, but Debian and Fedora based distros don't work for now.
  Linux Mint Debian Edition is an exception.

- QuickLinux attempts to set Linux as the default boot entry automatically, but
  this doesn't work on all systems. You may have to select Linux as the default
  boot option in the BIOS. The BIOS is accessible during startup by pressing F2,
  DEL, F10, ESC, F1, F12, or F11. Refer to your PC or motherboard's
  documentation for more information.

---

## Post-Installation

### Kubuntu

To create a persistent Kubuntu installation after creating the live partition,
run the installer, and then when the partitioning option comes up choose replace
partition and choose the free space created by the linux installer.

### Linux Mint

To create a persistent Linux Mint installation after installing the live image,
you must click on the install Linux Mint icon on the desktop from within the
live partition Linux Mint OS. Once the partitioning screen comes up you must
create a swap area (equal to your RAM size. If disk space is limited, 8 GB is
the minimum recommended.), and a btrfs file system in the rest of the free space
at `/`. I recommend btrfs as opposed to ext4, because if you ever want to
install another distro using this software, only btrfs supports resizing the
mounted partition.

---

## Accessing Windows

Under Linux Mint, Ubuntu, and Kubuntu, Windows can be accessed upon booting by
selecting "Boot from next volume", however **⚠️ WATCH OUT** — under Debian and
Fedora, you must change your boot order in the BIOS to access Windows.

---

## Troubleshooting

### "Could not load distro configuration" error

This error should not appear when using the launch command above, as the script
automatically downloads the required configuration. If you see this error:

1. Ensure you have an internet connection
2. Check that Windows Defender or your firewall is not blocking the download
3. Try running the command again

---

## Acknowledgements

QuickLinux is a fork of [ulli](https://github.com/rltvty2/ulli) by rltvty2,
licensed under GPL v3.0. The original project provided the foundation for
USB-less Linux installation. QuickLinux builds upon that work with UI
improvements, additional distro support, and a streamlined installation
experience.

---

## License

Released under **GNU General Public License v3.0**. You are free to do whatever
you like with the source except distribute a closed source version.
