# Installing Ubuntu 26.04 Server on Zettlab D6/D8 Ultra NAS

**Official Reference**  
Before proceeding, read the official Zettlab documentation:  
[Third-party system flashing](https://wiki.zettlab.com/guide/FAQ/Third-party%20system%20flashing.html)

**Disclaimer**  
This is a **community rewrite** still in draft status. Use at your own risk. A complete backup of the original ZettOS installation is **mandatory**.

## Prerequisites
- HDMI display and USB keyboard
- USB flash drive ≥ 32 GB
- Ubuntu **Server** 26.04 ISO (nightly/daily image)
- Another computer on the same local network with enough free storage for the full ZettOS backup (~size of internal M.2 drive)
- Stable wired Ethernet connection (highly recommended)

## Step 1: Create the Bootable Ubuntu 26.04 USB
1. Download the Ubuntu Server 26.04 ISO.
2. Verify the ISO checksum (mandatory – instructions on ubuntu.com).
3. Write it to the USB using Rufus, Ventoy, balenaEtcher, or `dd`.

## Step 2: Enter BIOS and Configure Settings
1. Power off the NAS.
2. Connect HDMI display and USB keyboard.
3. Power on and tap **F2** repeatedly to enter BIOS.
4. **Security** tab → Set **Secure Boot** to **Disabled**.
5. **Advanced** → **Storage / Power** → Enable **“HDD power on sequence”** (or “HDD power up”).
6. Save changes and exit (**F10**).

Power off the NAS.

## Step 3: Boot the Ubuntu Server Live Environment with Front-Display Fix
1. Insert the USB and power on the NAS.
2. Tap **F12** for the boot menu and select the USB.
3. At the GRUB menu, highlight the **Ubuntu Server** entry.
4. Press **E** to edit.
5. At the very end of the line starting with `linux`, add:
   ```
   video=eDP-1:d
   ```
6. Press **Ctrl+X** or **F10** to boot.

The system will now boot with the front LCD disabled (preventing low-resolution mirroring issues).

## Step 4: Backup ZettOS (Internal System Storage) – Do This BEFORE Installing
**Important:** This step creates a full image backup of the internal M.2 drive that contains ZettOS. Perform it now while the original system is still intact.

1. In the live environment, open a terminal or switch to console (Alt+F2).
2. Install and start SSH server:
   ```bash
   sudo apt update
   sudo apt install openssh-server -y
   sudo systemctl start ssh
   sudo passwd ubuntu
   ```
3. Note the NAS IP address:
   ```bash
   ip -4 addr show | grep inet
   ```

4. **From your other computer**, SSH into the live environment:
   ```bash
   ssh ubuntu@NAS-IP-ADDRESS
   ```

5. **Identify the internal M.2 drive (ZettOS)** – run these commands and note the output:
   ```bash
   lsblk -d -o NAME,SIZE,MODEL,TRAN
   sudo nvme list
   sudo fdisk -l | grep -E 'Disk /dev/nvme'
   ```
   - The internal system drive is **almost always `/dev/nvme0n1`**.
   - Confirm by size (it will be the smallest NVMe drive, usually 256 GB or 512 GB).

6. **Backup ZettOS over the network** (run on your remote computer):
   ```bash
   ssh ubuntu@NAS-IP-ADDRESS "sudo dd if=/dev/nvme0n1 bs=4M status=progress conv=fsync" | pv > zettos-backup.img
   ```
   - Replace `/dev/nvme0n1` if your identification step showed a different device.
   - `pv` (pipe viewer) gives a nice progress bar on the remote machine (install with `sudo apt install pv` if missing).

**Warning:**  
Wrong device selection can permanently erase data. Triple-check with `lsblk` before running `dd`.  
**Do not proceed to installation until the backup is complete and verified.**

## Step 5: Install Ubuntu Server 26.04
1. Return to the installer console (**Alt+F1**).
2. Continue with the Ubuntu Server installer.
3. Select the internal M.2 NVMe drive (`/dev/nvme0n1`) as the installation target.
4. Use guided storage configuration (entire disk is fine for most users).
5. Create your user account, set a strong password, and choose a hostname (e.g., `zettlab-nas`).
6. Skip additional snaps if desired.
7. Complete the installation and reboot when prompted.
8. Remove the USB drive after reboot.

After reboot, log in via SSH using the username and password you created.

## Step 6: First Boot Post-Installation Commands
```bash
sudo apt update && sudo apt upgrade -y
sudo apt install lm-sensors smartmontools curl git -y
```

## Known Hardware Support in Ubuntu 26.04
- **Fans**: Fully supported via the community DKMS kernel module (`zettlab_d8_fans`).
- **Front LCD / Display**: Connected as eDP-1; disabled with `video=eDP-1:d`. No software output implemented yet.
- **RGB / LED strip**: Detected as USB device (`lsusb`) but no driver available.
- **Networking (RTL8127 NICs)**: Works out-of-the-box.
- **Storage (M.2 + HDD bays)**: Fully detected after BIOS change.
- **HDMI output**: Works normally once front display is disabled.

**CPU Power Limit (Important Hardware Limitation)**  
The Zettlab D6/D8 Ultra uses an **Intel Core Ultra 5 125H** processor with **PL1/PL2 hard-locked to 40 W** in the BIOS. This limit remains even after installing Ubuntu 26.04.

## Next Steps
- **[Fan Control Guide](fan-control.md)** – Install the Zettlab fan kernel module and custom temperature-based services (strongly recommended).
- **[LCD Dashboard – Headless Server](lcd-python-headless.md)** – Pure Python direct framebuffer dashboard (recommended for Server installs).
- **[LCD Dashboard – Minimal Desktop](lcd-conky-desktop.md)** – Only if you later decide to install a minimal desktop environment.