# ToiletPaper

> Cleanse CachyOS and return to a pristine, vanilla Arch Linux system.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Arch%20Linux-1793d1.svg)](https://archlinux.org)

ToiletPaper is a lightweight, zero-dependency conversion utility engineered to cleanly revert an existing CachyOS installation back to standard, upstream Arch Linux.

---

## Critical Disclaimer

> **CAUTION: FOUNDATIONAL SYSTEM MODIFICATION**  
> This tool performs fundamental, system-wide changes, including swapping repository configurations, replacing the kernel stack, force-downgrading package binaries to the baseline x86-64 architecture, resetting desktop/window manager configurations, and rewriting bootloader configurations.
> 
> * **Always create a full system backup** (e.g., using rsync, Timeshift, Snapper, or filesystem snapshots) before running this script.
> * Ensure you have an active network connection and sufficient power before proceeding.
> * This software is provided "as is", without warranty of any kind.

---

## Purpose and Anti-Bloat Philosophy

CachyOS provides custom kernel tweaks, optimized repositories (x86-64-v3/v4), custom CPU schedulers, desktop environment customizations, and specialized software stacks. While suitable for specific workloads, returning to vanilla Arch Linux is often desired for upstream reproducibility, baseline compatibility, or minimal bloat.

To stay strictly aligned with the anti-bloat philosophy:
* **Zero External Dependencies:** No whiptail, dialog, yad, or Python runtimes required.
* **Pure Bash Architecture:** The entire interactive checklist interface is built natively using Bash arrays, loops, and ANSI terminal codes.
* **Modular Execution:** Granular control over which reversion stages to execute.

---

## Reversion Modules

ToiletPaper allows you to selectively enable or disable the following reversion modules via an interactive checklist:

| Module | Name | Description |
| :---: | :--- | :--- |
| **1** | **Pacman & Repository Reversion** | Removes CachyOS repositories using official scripts, restores upstream core/pacman, and recursively cleans %INSTALLED_DB% database metadata from /var/lib/pacman/local/*/desc to prevent pacman corruption warnings. |
| **2** | **Architecture & Package Resync** | Purges local pacman cache and forces a full reinstallation of all native packages (pacman -Qqn) from official Arch mirrors, downgrading x86-64-v3/v4 binaries back to standard x86-64. |
| **3** | **Kernel & Bootloader Swap** | Installs upstream linux, linux-headers, and linux-firmware, purges linux-cachyos* kernels, and re-generates GRUB (grub.cfg) or systemd-boot (bootctl) configurations. |
| **4** | **Bloat & Configuration Purge** | Identifies and purges CachyOS branding, tools, and meta-packages (cachyos-settings, chwd, cachyos-hello, cachy-browser, cachyos-kernel-manager, etc.) alongside orphaned dependencies. |
| **5** | **OS Identity Restoration** | Reconstructs /etc/os-release with standard upstream Arch Linux release identifiers and resets legacy release tags. |
| **6** | **KDE Plasma Reset [Optional]** | Reverts CachyOS KDE customizations (custom themes, panel layouts, taskbars) back to standard vanilla KDE Breeze defaults. Automatically creates timestamped backups of user configs before resetting. |
| **7** | **Hyprland Reset & Noctalia Purge [Optional]** | Purges noctalia and noctalia-qs packages along with CachyOS Hyprland configs, safely backing up and restoring ~/.config/hypr to standard upstream defaults. |

---

## Quickstart & Usage

### 1. Requirements
* Root privileges (sudo or logged in as root).
* Active internet connection (to fetch packages from official Arch Linux mirrors).

### 2. Execution Options

#### Option A: One-Liner (Recommended)
Run directly via curl and bash:

```bash
curl -sSL https://raw.githubusercontent.com/dim-ghub/ToiletPaper/refs/heads/main/toiletpaper.sh | sudo bash
```

#### Option B: Clone and Run
Clone this repository and run locally:

```bash
git clone https://github.com/dim-ghub/ToiletPaper.git
cd ToiletPaper
chmod +x toiletpaper.sh
sudo ./toiletpaper.sh
```

### 3. Interactive Menu Controls
Upon launching, an interactive pure-Bash checklist will appear:

```text
 _____     _ _      _   ____                       
|_   _|__ (_) | ___| |_|  _ \ __ _ _ __   ___ _ __ 
  | |/ _ \| | |/ _ \ __| |_) / _` | '_ \ / _ \ '__|
  | | (_) | | |  __/ |_|  __/ (_| | |_) |  __/ |   
  |_|\___/|_|_|\___|\__|_|   \__,_| .__/ \___|_|   
                                  |_|              
  Cleanse CachyOS and return to pristine Vanilla Arch Linux
  Version: 1.1.0 | Pure Bash Architecture | Zero Dependencies

Select the reversion modules you wish to execute:

  [X] 1) Pacman & Repository Reversion (Remove Cachy repos, scrub %INSTALLED_DB%)
  [X] 2) Architecture & Package Resync (Downgrade x86-64-v3/v4 to standard x86-64)
  [X] 3) Kernel & Bootloader Swap (Install standard linux, remove cachyos kernels)
  [X] 4) Bloat & Configuration Purge (Remove cachyos-settings, chwd, cachy-browser)
  [X] 5) OS Identity Restoration (Overwrite /etc/os-release with Arch Linux)
  [X] 6) KDE Plasma Reset [Optional] (Revert themes, taskbar & applets to vanilla Breeze)
  [ ] 7) Hyprland Reset & Noctalia Purge [Optional] (Reset ~/.config/hypr, purge noctalia/noctalia-qs)

----------------------------------------------------------------------
  [1-7] Toggle module     [A] Select All     [N] Deselect All
  [C/Enter] Confirm & Run   [Q] Quit
----------------------------------------------------------------------
```

* Enter numbers **`1` - `7`** to toggle specific modules on or off.
* Press **`A`** to enable all modules, or **`N`** to deselect all.
* Press **`C`** (or **`ENTER`**) to confirm your selection and begin execution.
* Press **`Q`** to abort without making changes.

### 4. Post-Reversion Steps
Once the script completes, reboot your system into the upstream Arch Linux kernel:

```bash
sudo systemctl reboot
```

Verify your converted system after rebooting:
```bash
# Verify kernel
uname -r

# Verify repositories
pacman -Sy

# Verify OS identification
cat /etc/os-release
```

---

## License

This project is licensed under the [MIT License](LICENSE) - see the [LICENSE](LICENSE) file for details.
