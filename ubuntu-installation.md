# Installing Ubuntu 26.04 Server on Zettlab D6/D8 Ultra

**Reference**  
Zettlab Third-party System Flashing: [Official Documentation](https://wiki.zettlab.com/guide/FAQ/Third-party%20system%20flashing.html)

## Hardware Note

The Zettlab D6/D8 Ultra has an internal M.2 NVMe system drive plus support for additional M.2 slots. Installing Ubuntu to a secondary NVMe drive is strongly recommended so the original ZettOS installation remains intact as a fallback.

## Prerequisites

- HDMI display and USB keyboard (needed for BIOS and first boot)
- USB flash drive ≥ 8 GB
- Ubuntu Server 26.04 ISO
- Recommended: Secondary NVMe SSD for the Ubuntu installation

## BIOS Configuration

1. Power on and press **F2** to enter BIOS setup.
2. **Disable Watchdog Timer (WDT)** — prevents random reboots during installation.
3. Disable **Secure Boot**.
4. Enable **HDD power on sequence** (or "HDD power up").
5. Save settings and exit (F10).

## Installation Procedure

### Step 1: Create Bootable USB

Download the Ubuntu Server 26.04 ISO and write it to the USB drive using your preferred tool (Rufus, balenaEtcher, etc.).

### Step 2: Boot the Installer with Front LCD Fix

1. Insert the USB drive and power on.
2. Press **F12** to open boot menu; select the USB drive.
3. At the GRUB menu, highlight the Ubuntu Server entry and press **E**.
4. At the end of the `linux` line, add a space and append:
   ```
   video=eDP-1:d
   ```
5. Press **Ctrl+X** or **F10** to boot.

### Step 3: Install Ubuntu

Install Ubuntu on a different drive than the original ZettOS NVMe. This preserves the original installation.

During the installer:
- Verify target drive selection (double-check device name).
- Use guided storage layout.
- Create a user account.
- Complete the installation and reboot.

Remove the USB drive after reboot.

### Step 4: Initial System Configuration

After the system boots into the new Ubuntu installation, run:

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