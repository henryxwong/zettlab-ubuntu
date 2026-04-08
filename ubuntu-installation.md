# Installing Ubuntu 26.04 Server on Zettlab D6/D8 Ultra NAS

**Official Reference**  
Before proceeding, read the official Zettlab documentation:  
[Third-party system flashing](https://wiki.zettlab.com/guide/FAQ/Third-party%20system%20flashing.html)

**Disclaimer**  
This is a **community rewrite** still in draft status. Use at your own risk. A complete backup of the original ZettOS installation is **mandatory**.

## Prerequisites
- HDMI display and USB keyboard (only needed for BIOS + first boot)
- USB flash drive ≥ 8 GB
- Ubuntu **Server** 26.04 ISO
- Another computer on the same network for remote backup and installation

## Step 1: Create Bootable USB
Download the Ubuntu Server 26.04 ISO and write it to the USB.

## Step 2: BIOS Settings
1. Power on and tap **F2** to enter BIOS.
2. Disable **Secure Boot**.
3. Enable **“HDD power on sequence”** (or “HDD power up”).
4. Save & exit (F10).

## Step 3: Boot with Front LCD Fix
1. Insert USB and power on.
2. Tap **F12** → select USB.
3. At GRUB menu, highlight the Ubuntu Server entry and press **E**.
4. At the end of the `linux` line, add:
   ```
   video=eDP-1:d
   ```
5. Press **Ctrl+X** or **F10** to boot.

## Step 4: Connect to the Installer over SSH (Recommended)
The installer starts directly in text mode.

1. When the installer screen appears, configure networking (DHCP is fine).
2. The installer will display **SSH connection instructions** on the main screen (or in the Help menu once networking is up).
3. From your other computer, connect using the shown command (usually something like `ssh ubuntu@NAS-IP`).
4. You are now fully inside the installer over SSH.

## Step 5: Backup ZettOS over SSH (Critical!)
While connected via SSH to the live installer:

1. Identify the internal M.2 drive:
   ```bash
   lsblk -d -o NAME,SIZE,MODEL,TRAN
   sudo nvme list
   ```
(It is almost always `/dev/nvme0n1`.)

2. On your **remote computer**, run the backup:
   ```bash
   ssh ubuntu@NAS-IP "sudo dd if=/dev/nvme0n1 bs=4M status=progress conv=fsync" | pv > zettos-backup.img
   ```

**Do not proceed until the backup is complete and verified.**

## Step 6: Perform the Installation
Continue the installer over SSH:
- Choose the internal M.2 drive (`/dev/nvme0n1`)
- Use guided storage
- Create your user account
- Finish installation and reboot

Remove the USB after reboot. SSH will be enabled by default in the installed system.

## Step 7: First Boot Commands (after reboot)
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install lm-sensors smartmontools curl git -y
```

## Known Hardware Support in Ubuntu 26.04
- **Fans**: Fully supported via `zettlab_d8_fans` DKMS module
- **Front LCD**: Connected as eDP-1 (disabled with `video=eDP-1:d`)
- **RGB/LED strip**: Detected but no driver
- **Networking (RTL8127)**: Works out-of-the-box
- **CPU**: Intel Core Ultra 5 125H – PL1/PL2 locked at 40 W

## Next Steps
- **[Fan Control Guide](fan-control.md)** – Install the Zettlab fan kernel module and custom temperature-based services (strongly recommended).
- **[LCD Dashboard – Headless Server](lcd-python-headless.md)** – Pure Python direct framebuffer dashboard (recommended for Server installs).
- **[LCD Dashboard – Minimal Desktop](lcd-conky-desktop.md)** – Only if you later decide to install a minimal desktop environment.