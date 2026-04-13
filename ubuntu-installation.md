# Installing Ubuntu 26.04 Server on Zettlab D6/D8 Ultra NAS

**Official Reference**  
Before proceeding, read the official Zettlab documentation:  
[Third-party system flashing](https://wiki.zettlab.com/guide/FAQ/Third-party%20system%20flashing.html)

## Hardware Note
The Zettlab D6/D8 Ultra has an internal M.2 NVMe system drive plus support for additional M.2 slots. Installing Ubuntu to a **secondary NVMe drive** is strongly recommended so you can keep the original ZettOS installation intact as a fallback.

## Prerequisites
- HDMI display and USB keyboard (needed for BIOS and first boot)
- USB flash drive ≥ 8 GB
- Ubuntu **Server** 26.04 ISO
- (Recommended) A secondary NVMe SSD for the Ubuntu installation

## BIOS Settings (Important)
1. Power on and tap **F2** to enter BIOS.
2. **Disable Watchdog Timer** (WDT) — this prevents random reboots during installation.
3. Disable **Secure Boot**.
4. Enable **“HDD power on sequence”** (or “HDD power up”).
5. Save & exit (F10).

## Step 1: Create Bootable USB
Download the Ubuntu Server 26.04 ISO and write it to the USB drive using your preferred tool (Rufus, balenaEtcher, etc.).

## Step 2: Boot the Installer with Front LCD Fix
1. Insert the USB and power on.
2. Tap **F12** → select the USB drive.
3. At the GRUB menu, highlight the Ubuntu Server entry and press **E**.
4. At the very end of the `linux` line, add a space and type:
   ```
   video=eDP-1:d
   ```
5. Press **Ctrl+X** or **F10** to boot.

## Step 3: Install Ubuntu
**Important recommendation**:  
Install Ubuntu on a **different drive** than your original ZettOS NVMe (preferably a secondary NVMe SSD). This keeps your original ZettOS installation untouched.

During the installer:
- Choose the correct target drive (double-check the device name).
- Use the guided storage layout.
- Create your user account.
- Finish the installation and reboot.

Remove the USB drive after reboot.

## Step 4: First Boot Commands
After the system boots into the new Ubuntu installation, run:
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install lm-sensors smartmontools curl git -y
```

## Known Hardware Support in Ubuntu 26.04
- **Fans**: Fully supported via the `zettlab_d8_fans` DKMS module
- **Front LCD**: Connected as `eDP-1` (disabled during live boot with the parameter above)
- **Networking (RTL8127)**: Works out-of-the-box
- **CPU**: Intel Core Ultra 5 125H – PL1/PL2 locked at 45 W / 93 W

## Next Steps
1. Immediately follow the **[Fan Control Guide](fan-control.md)** (install the DKMS fan module + the two custom fan-curve services).
2. Then choose your LCD dashboard:
   - **[LCD Dashboard – Headless Server (Recommended)](lcd-python-headless.md)**
   - **[LCD Dashboard – Minimal Desktop](lcd-conky-desktop.md)**