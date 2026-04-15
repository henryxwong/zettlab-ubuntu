# Installing Ubuntu 26.04 Server on Zettlab D6/D8 Ultra

> Install Ubuntu 26.04 Server on Zettlab D6/D8 Ultra NAS while preserving the original ZettOS installation as a fallback.

## Overview

**Reference:** [Zettlab Third-party System Flashing Guide](https://wiki.zettlab.com/guide/FAQ/Third-party%20system%20flashing.html)

**Hardware Note:** The Zettlab D6/D8 Ultra has an internal M.2 NVMe system drive plus support for additional M.2 slots.

## Prerequisites

- HDMI display and USB keyboard (required for BIOS and first boot)
- USB flash drive ≥ 8 GB
- Ubuntu Server 26.04 ISO
- Recommended: Secondary NVMe SSD for Ubuntu installation

## BIOS Configuration

### Step 1: Enter BIOS Setup

Power on and press **F2** to enter BIOS setup.

### Step 2: Configure BIOS Settings

1. **Disable Watchdog Timer (WDT)** — prevents random reboots during installation
2. Disable **Secure Boot**
3. Enable **HDD power on sequence** (or "HDD power up")
4. Save settings and exit (F10)

## Installation Procedure

### Step 1: Create Bootable USB

Download Ubuntu Server 26.04 ISO and write to USB using Rufus, balenaEtcher, or similar tool.

### Step 2: Boot Installer with Front LCD Fix

1. Insert USB drive and power on
2. Press **F12** to open boot menu; select USB drive
3. At GRUB menu, highlight Ubuntu Server entry and press **E**
4. At end of `linux` line, add:
   ```
   video=eDP-1:d
   ```
5. Press **Ctrl+X** or **F10** to boot

### Step 3: Install Ubuntu

Install Ubuntu on a different drive than the original ZettOS NVMe to preserve it as fallback.

During installer:
- Verify target drive selection
- Use guided storage layout
- Create user account
- Complete installation and reboot

Remove USB drive after reboot.

### Step 4: Initial System Configuration

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install lm-sensors smartmontools curl git -y
```

## Known Hardware Support in Ubuntu 26.04

| Component | Status |
|-----------|--------|
| Fans | Fully supported via `zettlab_d8_fans` DKMS module |
| Front LCD | Connected as `eDP-1`; disabled during live boot with kernel parameter |
| Networking (RTL8127) | Works out-of-the-box; use r8127 DKMS driver for optimal stability |
| CPU | Intel Core Ultra 5 125H; PL1/PL2 locked at 45 W / 93 W |