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

## Step 4: Backup ZettOS over SSH (Critical!) – Using Ctrl+Alt+F2 method
1. On the live installer machine, press **Ctrl + Alt + F2** (or try **F3** / **F4**) to switch to a root console.  
   You should now be at a `#` root prompt.

2. Get your IP address:
   ```bash
   ip -4 addr show
   ```
(Look for the line that starts with `inet` under your network interface — usually `enp*` or `eth*`. Example: `inet 192.168.1.45/24` → your IP is **192.168.1.45**)

3. Set a password for the `ubuntu-server` user:
   ```bash
   passwd ubuntu-server
   ```
   (Type your chosen password twice when prompted.)

4. Press **Ctrl + Alt + F1** to return to the main installer screen.

5. On your **remote computer**, run the backup (use the password you just set):

   ```bash
   ssh ubuntu-server@NAS-IP "sudo dd if=/dev/nvme0n1 bs=4M status=progress conv=fsync" | pv > zettos-backup.img
   ```

   (Replace `NAS-IP` with the IP you found in step 2.)

6. **Verify the backup integrity (mandatory)**  
   After the backup finishes:

   - On your **remote computer**:
     ```bash
     sha256sum zettos-backup.img | tee zettos-backup.img.sha256
     ```

   - Then run the following command **on the live installer** (open a new SSH session with `ubuntu-server` or use the existing one):
     ```bash
     sudo sha256sum /dev/nvme0n1
     ```

   - Compare the two long hashes.  
     **They must be identical.** If they match, your backup is verified and safe to use.

**Do not proceed until the backup is complete AND the checksums match.**

## Step 5: Connect to the Installer over SSH (for installation)
1. On the main installer screen, go to **Help** → **Help on SSH Access**.
2. The Help screen will display the exact SSH command and temporary password for the **`installer`** user.

   Example:
   ```
   ssh installer@192.168.1.XXX
   Password: [random temporary password]
   ```

3. From your other computer, connect using the command and password shown in Help.

You are now fully inside the installer over SSH and can continue with the installation.

## Step 6: Perform the Installation
Continue through the installer over SSH:
- Select the internal M.2 drive (`/dev/nvme0n1`)
- Use guided storage layout
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
- **[Fan Control Guide](fan-control.md)**
- **[LCD Dashboard – Headless Server](lcd-python-headless.md)**
- **[LCD Dashboard – Minimal Desktop](lcd-conky-desktop.md)**