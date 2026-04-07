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

### Step 7: Fan Control (Highly Recommended)
The fans (including the **CPU fan**) will run at a fixed speed set by the BIOS after installing Ubuntu.  
The stock `fancontrol` package is **not compatible** with the Zettlab driver (PWM range is 0–183, not 0–255) and the driver’s built-in CPU auto mode (`pwm3_enable=2`) is unstable (CPU fan repeatedly drops to 0 RPM in testing).

A custom solution is therefore required. The following setup has been fully tested and proven stable under sustained near-100 % CPU load (no thermal throttling observed).

#### 7.1 Install the Kernel Module
```bash
sudo apt install dkms build-essential git -y
git clone https://github.com/haveacry/zettlab-d8-fans.git
cd zettlab-d8-fans
# Follow the repo's README to install via DKMS (typical commands):
# sudo dkms add -m zettlab-d8-fans -v 0.0.1
# sudo dkms build -m zettlab-d8-fans -v 0.0.1
# sudo dkms install -m zettlab-d8-fans -v 0.0.1
sudo modprobe zettlab_d8_fans
```

Make it load at boot:
```bash
echo zettlab_d8_fans | sudo tee /etc/modules-load.d/zettlab_d8_fans.conf
```

Verify:
```bash
lsmod | grep zettlab_d8_fans
cat /sys/class/hwmon/hwmon*/name   # should show zettlab_d8_fans
sensors
```

#### 7.2 Remove Incompatible Stock Tooling
```bash
sudo apt purge fancontrol -y
```

#### 7.3 Install lm-sensors (optional but useful for quick checks)
```bash
sudo apt install lm-sensors -y
sensors
```

#### 7.4 (Optional) Install Netdata for Monitoring
Because native packages were not available for Ubuntu 26.04 at the time of writing, use the static install:
```bash
bash <(curl -Ss https://get.netdata.cloud/kickstart.sh) --stable-channel --install-type static
```
Claim it to Netdata Cloud if desired. It will automatically discover the Zettlab fan sensors.

#### 7.5 Custom Temperature-Based Fan Control Services
Two custom `systemd` services are used:

- **CPU fan** controlled from CPU package temperature (`hwmon7/temp1_input`).
- **HDD fans** (both rear disk fans) controlled from the *highest* SATA SMART temperature.

**Create the scripts and services exactly as shown below** (these are the exact files that passed all load testing).

**CPU fan script** (`sudo nano /usr/local/sbin/cpu-fan-curve.sh`):
```bash
#!/bin/bash
set -euo pipefail

TEMP_INPUT="/sys/class/hwmon/hwmon7/temp1_input"
PWM_ENABLE="/sys/class/hwmon/hwmon8/pwm3_enable"
PWM_OUTPUT="/sys/class/hwmon/hwmon8/pwm3"
STATE_FILE="/run/cpu-fan-curve.state"
SLEEP_SECS=2
HYSTERESIS_C=2
SAFE_PWM=120
FULL_SPEED_ON_C=72
FULL_SPEED_OFF_C=68

read_temp_c() {
  local temp_milli
  temp_milli=$(<"$TEMP_INPUT") || return 1
  printf '%d\n' "$((temp_milli / 1000))"
}

target_pwm_for_temp() {
  local temp_c=$1
  if (( temp_c >= FULL_SPEED_ON_C )); then
    printf '183\n'
  elif (( temp_c >= 64 )); then
    printf '160\n'
  elif (( temp_c >= 56 )); then
    printf '140\n'
  elif (( temp_c >= 48 )); then
    printf '120\n'
  else
    printf '100\n'
  fi
}

# ... (rest of the script is identical to the version in the NAS Fan Control Guide – read_state, write_state, apply_pwm, main_loop)

main_loop
```
*(Make executable: `sudo chmod +x /usr/local/sbin/cpu-fan-curve.sh`)*

**CPU fan systemd unit** (`sudo nano /etc/systemd/system/cpu-fan-curve.service`):
```ini
[Unit]
Description=CPU fan control curve for Zettlab NAS
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/cpu-fan-curve.sh
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
```

**HDD fan script** and **HDD fan service** are provided in the original NAS Fan Control Guide (identical logic, 20 s polling interval, SMART temperature source from `/dev/sda`–`/dev/sdd`, curve tuned for disks).

After creating both scripts and both `.service` files:
```bash
sudo chmod +x /usr/local/sbin/*.sh
sudo systemctl daemon-reload
sudo systemctl enable --now cpu-fan-curve.service hdd-fan-curve.service
```

#### 7.6 Useful Runtime Commands
```bash
# Current temps & fan state
cat /sys/class/hwmon/hwmon7/temp1_input
cat /sys/class/hwmon/hwmon8/pwm3_enable
cat /sys/class/hwmon/hwmon8/pwm3
cat /sys/class/hwmon/hwmon8/fan3_input

# Manual overrides (service will re-take control on next cycle)
echo 1 | sudo tee /sys/class/hwmon/hwmon8/pwm3_enable
echo 120 | sudo tee /sys/class/hwmon/hwmon8/pwm3
```

### Known Hardware Support in Ubuntu 26.04
- **Fans**: Fully supported via the community DKMS kernel module (`zettlab_d8_fans`).
- **Front LCD / Display**: Connected as eDP-1; disabled with `video=eDP-1:d`. No software output implemented yet.
- **RGB / LED strip**: Detected as USB device (`lsusb`) but no driver available.
- **Networking (RTL8127 NICs)**: Works out-of-the-box.
- **Storage (M.2 + HDD bays)**: Fully detected after BIOS change.
- **HDMI output**: Works normally once front display is disabled.

### CPU Power Limit (Important Hardware Limitation)
The Zettlab D6/D8 Ultra uses an **Intel Core Ultra 5 125H** with **PL1/PL2 hard-locked to 40 W** in the BIOS. This limit remains even after installing Ubuntu 26.04. Tune Linux power management (powersave governor, TLP, auto-cpufreq) for best efficiency inside the 40 W envelope.

**This guide was made possible with detailed information and testing shared by Speedster and Daisan on the Zettlab Discord.**