# zettlab-ubuntu

**Disclaimer:** This guide is still a draft and incomplete.

**Guide: Installing Ubuntu 26.04 on the Zettlab D6 Ultra or D8 Ultra NAS**

### Prerequisites
- HDMI display and USB keyboard  
- USB flash drive ≥ 32 GB  
- Ubuntu 26.04 ISO (nightly/daily image)  
- **External USB drive or SSD with enough free space** (at least as large as your internal M.2 system drive) for the ZettOS backup  
- Internet connection after install  

### Step 1: Create the Bootable Ubuntu 26.04 USB
1. Download the Ubuntu 26.04 ISO.  
2. Write it to the USB using Rufus, Ventoy, or `dd`.  

### Step 2: Enter BIOS and Configure Settings
1. Power off the NAS.  
2. Connect HDMI display and USB keyboard.  
3. Power on and tap **F2** repeatedly to enter BIOS.  
4. **Disable Secure Boot** (Security tab → Disabled).  
5. **Enable “HDD power on sequence”** (or “HDD power up”) under Advanced → Storage/Power.  
6. Save & exit (F10).  

Power off the NAS.

### Step 3: Boot the Ubuntu 26.04 Live Environment with Front-Display Fix
1. Insert the USB and power on the NAS.  
2. Tap **F12** for the boot menu and select the USB.  
3. At the GRUB menu, highlight **“Try Ubuntu”**.  
4. Press **E** to edit.  
5. At the end of the `linux` line, add:  
   ```
   video=eDP-1:d
   ```  
6. Press **Ctrl+X** or **F10** to boot.  

You are now in the Ubuntu 26.04 live desktop.

### Step 4: Backup ZettOS (Internal System Storage) – Do This BEFORE Installing
**Important:** This step creates a full image backup of the internal M.2 drive that contains ZettOS. Perform it now while the original system is still intact.

1. Plug in your external USB backup drive.  
2. Open a **Terminal** (Ctrl+Alt+T).  
3. Identify the drives carefully:  
   ```
   lsblk -f
   ```  
   - Look for your **internal M.2 NVMe drive** (usually `/dev/nvme0n1` – it will show multiple partitions and is **not** labeled as the USB installer).  
   - Confirm the external backup drive (usually `/dev/sdX` where X is a letter).  
   - **Double-check sizes and labels** – do not guess.  

4. Create the backup (replace `/dev/nvme0n1` with your confirmed internal drive and adjust the output path):  
   ```
   sudo dd if=/dev/nvme0n1 of=/media/ubuntu/<your-external-drive-name>/zettos-backup.img bs=4M status=progress conv=fsync
   ```  
   This may take 10–30+ minutes depending on drive size.  

5. When finished, verify the backup file exists and has the correct size:  
   ```
   ls -lh /media/ubuntu/<your-external-drive-name>/zettos-backup.img
   ```  

**Warning:**  
- Wrong device selection can permanently erase data. Triple-check with `lsblk` before running `dd`.  
- Do **not** proceed to installation until the backup completes successfully.  

### Step 5: Install Ubuntu 26.04
1. Launch the **Install Ubuntu** icon on the desktop.  
2. The M.2 drive and HDD bays are now visible.  
3. Choose your partitioning and complete the installation.  
4. Reboot and remove the USB.  

The `video=eDP-1:d` parameter is automatically saved.

### Step 6: Post-Installation (Ubuntu 26.04)
1. Boot into the new system and run:  
   ```
   sudo apt update && sudo apt upgrade -y
   ```

### Step 7: Fan Control (Optional but Recommended)
1. Install build tools:  
   ```
   sudo apt install dkms build-essential git -y
   ```  
2. Clone the repo:  
   ```
   git clone https://github.com/haveacry/zettlab-d8-fans.git
   ```  
3. Follow the README in the repo to install via DKMS and load the module (`zettlab_d8_fans`).  
4. Add to auto-load:  
   ```
   echo zettlab_d8_fans | sudo tee /etc/modules-load.d/zettlab_d8_fans.conf
   ```

### Known Hardware Support in Ubuntu 26.04
- **Fans**: Fully supported via the community DKMS kernel module (`zettlab_d8_fans`). Exposes fan speed (RPM) and PWM control through the standard hwmon interface.  
- **Front LCD / Display**: Connected as an additional iGPU output (eDP-1). Disabled by the `video=eDP-1:d` kernel parameter to prevent the HDMI output from being resized to the panel’s native 172×640 resolution. No software output to the front LCD has been implemented yet.  
- **RGB / LED strip**: Detected as a standard USB device (`lsusb` will show it), but no driver or control software is currently available.  
- **Networking (RTL8127 NICs)**: Works out-of-the-box on Ubuntu 26.04.  
- **Storage (M.2 + HDD bays)**: Fully detected after enabling “HDD power on sequence” in BIOS.  
- **HDMI output**: Works normally once the front display is disabled.  

**This guide was made possible with detailed information and testing shared by Speedster on the Zettlab Discord.**
