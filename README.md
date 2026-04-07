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

### Step 7: Fan Control (Highly Recommended – Especially if the Unit Runs Hot)
After installing Ubuntu the fans (including the CPU fan) run at a fixed speed set by the BIOS.

**Scope**  
This section captures what was implemented on this NAS to expose fan telemetry, monitor it with Netdata, and control the CPU fan with a custom temperature-based service on Ubuntu.  
The target hardware is a Zettlab D6/D8 Ultra class NAS using the `zettlab_d8_fans` kernel module.

**What Is Implemented**
1. A DKMS-installed kernel module exposes the NAS fans in `hwmon`.
2. `lm-sensors` is installed for local sensor visibility.
3. Netdata is installed and claimed to Netdata Cloud for monitoring.
4. A custom `systemd` service controls the CPU fan in manual mode based on CPU package temperature.
5. A second custom `systemd` service controls the HDD fans from the highest SATA SMART temperature.
6. The stock `fancontrol` package was tested and removed because it is not compatible with this driver as shipped on Ubuntu.

**Why A Custom Service Was Needed**  
The Zettlab fan driver accepts PWM values in the range `0-183`.  
Ubuntu's stock `fancontrol` tooling assumes a `0-255` style PWM range during probing and startup:
- `pwmconfig` reported no usable PWM outputs.
- `fancontrol` failed when it tried to write an invalid PWM max value for this driver.

The custom service avoids that issue by writing only valid `0-183` values.

**Fan Layout**
- `fan1`: rear disk fan 1
- `fan2`: rear disk fan 2
- `fan3`: CPU fan

On this system:
- disk fans are manual only through this driver
- CPU auto mode via `pwm3_enable=2` was unstable in testing
- CPU fan is therefore kept in manual mode and driven by the custom service
- HDD fans are driven from SATA SMART temperatures by a separate service

**Important Paths**
- Kernel module source: `/usr/src/zettlab-d8-fans-0.0.1`
- CPU fan controller script: `/usr/local/sbin/cpu-fan-curve.sh`
- CPU fan controller service: `/etc/systemd/system/cpu-fan-curve.service`
- HDD fan controller script: `/usr/local/sbin/hdd-fan-curve.sh`
- HDD fan controller service: `/etc/systemd/system/hdd-fan-curve.service`
- Runtime state file: `/run/cpu-fan-curve.state`
- HDD runtime state file: `/run/hdd-fan-curve.state`
- Zettlab hwmon node: `/sys/class/hwmon/hwmon8`
- CPU package temp input: `/sys/class/hwmon/hwmon7/temp1_input`

**Installed Packages**
- `dkms`
- `build-essential`
- `lm-sensors`
- `smartmontools`
- Netdata static install under `/opt/netdata`

Removed:
- `fancontrol`

#### 7.1 Install the Kernel Module
```bash
sudo apt install dkms build-essential git smartmontools lm-sensors -y
git clone https://github.com/haveacry/zettlab-d8-fans.git
cd zettlab-d8-fans

sudo mkdir -p /usr/src/zettlab-d8-fans-0.0.1
sudo cp -r * /usr/src/zettlab-d8-fans-0.0.1/

sudo dkms add -m zettlab-d8-fans -v 0.0.1
sudo dkms build -m zettlab-d8-fans -v 0.0.1
sudo dkms install -m zettlab-d8-fans -v 0.0.1
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

#### 7.3 (Optional) Install Netdata for Monitoring
Native packages were not available for Ubuntu 26.04, so the static install was used:
```bash
bash <(curl -Ss https://get.netdata.cloud/kickstart.sh) --stable-channel --install-type static
```
Netdata successfully discovered the Zettlab fan sensors and exposed the CPU fan RPM chart.

#### 7.4 Custom Temperature-Based Fan Control Services

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

read_state() {
if [[ -r "$STATE_FILE" ]]; then
# shellcheck disable=SC1090
source "$STATE_FILE"
else
last_pwm=-1
last_temp=-1000
fi
}

write_state() {
umask 022
cat >"$STATE_FILE" <<EOF
last_pwm=$1
last_temp=$2
EOF
}

apply_pwm() {
local pwm=$1
printf '1\n' >"$PWM_ENABLE"
printf '%s\n' "$pwm" >"$PWM_OUTPUT"
}

main_loop() {
local temp_c target_pwm

read_state

while true; do
if ! temp_c=$(read_temp_c); then
apply_pwm "$SAFE_PWM"
write_state "$SAFE_PWM" -1000
sleep "$SLEEP_SECS"
continue
fi

target_pwm=$(target_pwm_for_temp "$temp_c")

if (( last_pwm == -1 )); then
apply_pwm "$target_pwm"
last_pwm=$target_pwm
last_temp=$temp_c
write_state "$last_pwm" "$last_temp"
sleep "$SLEEP_SECS"
continue
fi

if (( temp_c >= FULL_SPEED_ON_C && last_pwm < 183 )); then
apply_pwm 183
last_pwm=183
last_temp=$temp_c
write_state "$last_pwm" "$last_temp"
sleep "$SLEEP_SECS"
continue
fi

if (( last_pwm == 183 && temp_c >= FULL_SPEED_OFF_C )); then
write_state "$last_pwm" "$last_temp"
sleep "$SLEEP_SECS"
continue
fi

if (( target_pwm > last_pwm )); then
apply_pwm "$target_pwm"
last_pwm=$target_pwm
last_temp=$temp_c
write_state "$last_pwm" "$last_temp"
sleep "$SLEEP_SECS"
continue
fi

if (( target_pwm < last_pwm && temp_c <= last_temp - HYSTERESIS_C )); then
apply_pwm "$target_pwm"
last_pwm=$target_pwm
last_temp=$temp_c
write_state "$last_pwm" "$last_temp"
sleep "$SLEEP_SECS"
continue
fi

write_state "$last_pwm" "$last_temp"
sleep "$SLEEP_SECS"
done
}

main_loop
```

```bash
sudo chmod +x /usr/local/sbin/cpu-fan-curve.sh
```

**CPU fan service** (`sudo nano /etc/systemd/system/cpu-fan-curve.service`):
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

**HDD fan script** (`sudo nano /usr/local/sbin/hdd-fan-curve.sh`):
```bash
#!/bin/bash
set -euo pipefail

DRIVES=(/dev/sda /dev/sdb /dev/sdc /dev/sdd)
PWM_OUTPUTS=("/sys/class/hwmon/hwmon8/pwm1" "/sys/class/hwmon/hwmon8/pwm2")
STATE_FILE="/run/hdd-fan-curve.state"
SLEEP_SECS=20
HYSTERESIS_C=1
SAFE_PWM=120
FULL_SPEED_ON_C=46
FULL_SPEED_OFF_C=44

read_drive_temp() {
local drive=$1 temp
temp=$(smartctl -A "$drive" 2>/dev/null | awk '/^194[[:space:]]+Temperature_Celsius/ {print $10; exit}')
if [[ -z "${temp:-}" ]]; then
temp=$(smartctl -A "$drive" 2>/dev/null | awk '/^190[[:space:]]+Airflow_Temperature_Cel/ {print $10; exit}')
fi
[[ -n "${temp:-}" ]] || return 1
printf '%s\n' "$temp"
}

read_max_hdd_temp() {
local drive temp max_temp=-1
for drive in "${DRIVES[@]}"; do
if temp=$(read_drive_temp "$drive"); then
(( temp > max_temp )) && max_temp=$temp
fi
done
(( max_temp >= 0 )) || return 1
printf '%s\n' "$max_temp"
}

target_pwm_for_temp() {
local temp_c=$1

if (( temp_c >= FULL_SPEED_ON_C )); then
printf '183\n'
elif (( temp_c >= 43 )); then
printf '140\n'
elif (( temp_c >= 40 )); then
printf '120\n'
elif (( temp_c >= 35 )); then
printf '100\n'
else
printf '80\n'
fi
}

read_state() {
if [[ -r "$STATE_FILE" ]]; then
# shellcheck disable=SC1090
source "$STATE_FILE"
else
last_pwm=-1
last_temp=-1000
fi
}

write_state() {
umask 022
cat >"$STATE_FILE" <<EOF
last_pwm=$1
last_temp=$2
EOF
}

apply_pwm() {
local pwm=$1 output
for output in "${PWM_OUTPUTS[@]}"; do
printf '%s\n' "$pwm" >"$output"
done
}

main_loop() {
local temp_c target_pwm

read_state

while true; do
if ! temp_c=$(read_max_hdd_temp); then
apply_pwm "$SAFE_PWM"
write_state "$SAFE_PWM" -1000
sleep "$SLEEP_SECS"
continue
fi

target_pwm=$(target_pwm_for_temp "$temp_c")

if (( last_pwm == -1 )); then
apply_pwm "$target_pwm"
last_pwm=$target_pwm
last_temp=$temp_c
write_state "$last_pwm" "$last_temp"
sleep "$SLEEP_SECS"
continue
fi

if (( temp_c >= FULL_SPEED_ON_C && last_pwm < 183 )); then
apply_pwm 183
last_pwm=183
last_temp=$temp_c
write_state "$last_pwm" "$last_temp"
sleep "$SLEEP_SECS"
continue
fi

if (( last_pwm == 183 && temp_c >= FULL_SPEED_OFF_C )); then
write_state "$last_pwm" "$last_temp"
sleep "$SLEEP_SECS"
continue
fi

if (( target_pwm > last_pwm )); then
apply_pwm "$target_pwm"
last_pwm=$target_pwm
last_temp=$temp_c
write_state "$last_pwm" "$last_temp"
sleep "$SLEEP_SECS"
continue
fi

if (( target_pwm < last_pwm && temp_c <= last_temp - HYSTERESIS_C )); then
apply_pwm "$target_pwm"
last_pwm=$target_pwm
last_temp=$temp_c
write_state "$last_pwm" "$last_temp"
sleep "$SLEEP_SECS"
continue
fi

write_state "$last_pwm" "$last_temp"
sleep "$SLEEP_SECS"
done
}

main_loop
```

```bash
sudo chmod +x /usr/local/sbin/hdd-fan-curve.sh
```

**HDD fan service** (`sudo nano /etc/systemd/system/hdd-fan-curve.service`):
```ini
[Unit]
Description=HDD fan control curve for Zettlab NAS
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/hdd-fan-curve.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Activate both services:
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cpu-fan-curve.service hdd-fan-curve.service
```

#### 7.5 Service Management & Runtime Commands
Reload and restart after editing:
```bash
systemctl daemon-reload
systemctl restart cpu-fan-curve.service hdd-fan-curve.service
```

Useful runtime commands:
```bash
cat /sys/class/hwmon/hwmon7/temp1_input
cat /sys/class/hwmon/hwmon8/pwm3_enable
cat /sys/class/hwmon/hwmon8/pwm3
cat /sys/class/hwmon/hwmon8/fan3_input
```

**Final CPU Fan Control Design**  
CPU auto mode was unstable (fan dropped to 0 RPM).  
Active curve and hysteresis are exactly as coded in the scripts above.  
Fail-safe: if temp read fails, set PWM to 120.  
Tested under near-100% CPU load with no thermal throttling.

### Known Hardware Support in Ubuntu 26.04
- **Fans**: Fully supported via the community DKMS kernel module (`zettlab_d8_fans`).
- **Front LCD / Display**: Connected as eDP-1; disabled with `video=eDP-1:d`. No software output implemented yet.
- **RGB / LED strip**: Detected as USB device (`lsusb`) but no driver available.
- **Networking (RTL8127 NICs)**: Works out-of-the-box.
- **Storage (M.2 + HDD bays)**: Fully detected after BIOS change.
- **HDMI output**: Works normally once front display is disabled.

### CPU Power Limit (Important Hardware Limitation)
The Zettlab D6/D8 Ultra uses an **Intel Core Ultra 5 125H** processor with **PL1/PL2 hard-locked to 40 W** in the BIOS. This limit remains even after installing Ubuntu 26.04.

**This guide was made possible with detailed information and testing shared by Speedster and Daisan on the Zettlab Discord.**