# Fan Control Guide for Zettlab D6/D8 Ultra on Ubuntu 26.04

## Scope
This document captures what was implemented on this NAS to expose fan telemetry and control the fans with custom temperature-based services on Ubuntu.

The target hardware is a Zettlab D8 Ultra class NAS using the `zettlab_d8_fans` kernel module.  
**This guide now fully supports both D6 (6-bay) and D8 (8-bay) variants.**

## What Is Implemented
1. A DKMS-installed kernel module exposes the NAS fans in `hwmon`.
2. `lm-sensors` is installed for local sensor visibility.
3. **(Optional)** Netdata is installed for monitoring (graphs + Netdata Cloud).
4. A custom `systemd` service controls the CPU fan in manual mode based on CPU package temperature.
5. A second custom `systemd` service controls the HDD fans from the highest SATA SMART temperature (works on both D6 and D8).
6. The stock `fancontrol` package was tested and removed because it is not compatible with this driver.

## Package Installation (Required First Step)
Run these commands **before** anything else:

```bash
sudo apt update

# Install required packages
sudo apt install dkms build-essential git smartmontools lm-sensors -y

# Remove incompatible stock fancontrol package
sudo apt remove --purge fancontrol -y
```

## Why A Custom Service Was Needed
The Zettlab fan driver accepts PWM values in the range `0-183`.

Ubuntu's stock `fancontrol` tooling assumes a `0-255` style PWM range during probing and startup:

- `pwmconfig` reported no usable PWM outputs.
- `fancontrol` failed when it tried to write an invalid PWM max value for this driver.

The custom service avoids that issue by writing only valid `0-183` values.

## Fan Layout
- `fan1`: rear disk fan 1
- `fan2`: rear disk fan 2
- `fan3`: CPU fan

On this system:

- disk fans are manual only through this driver
- CPU auto mode via `pwm3_enable=2` was unstable in testing
- CPU fan is therefore kept in manual mode and driven by the custom service
- HDD fans are driven from SATA SMART temperatures by a separate service

## Important Paths
- Kernel module source: `/usr/src/zettlab-d8-fans-0.0.1`
- CPU fan controller script: `/usr/local/sbin/cpu-fan-curve.sh`
- CPU fan controller service: `/etc/systemd/system/cpu-fan-curve.service`
- HDD fan controller script: `/usr/local/sbin/hdd-fan-curve.sh`
- HDD fan controller service: `/etc/systemd/system/hdd-fan-curve.service`
- Runtime state file: `/run/cpu-fan-curve.state`
- HDD runtime state file: `/run/hdd-fan-curve.state`
- Zettlab hwmon node: `/sys/class/hwmon/hwmon8`
- CPU package temp input: `/sys/class/hwmon/hwmon7/temp1_input`

## Optional: Netdata Setup
Netdata is **optional** — skip this section if you only want basic fan control.

```bash
sudo bash <(curl -Ss https://get.netdata.cloud/kickstart.sh) --stable-channel --install-type static
```

Netdata status can be checked with:

```bash
systemctl status netdata
curl -fsS http://127.0.0.1:19999/api/v1/info
```

## Kernel Module Setup

### DKMS Install Flow
```bash
git clone https://github.com/haveacry/zettlab-d8-fans.git
cd zettlab-d8-fans

sudo mkdir -p /usr/src/zettlab-d8-fans-0.0.1
sudo cp -r * /usr/src/zettlab-d8-fans-0.0.1/

sudo dkms add -m zettlab-d8-fans -v 0.0.1
sudo dkms build -m zettlab-d8-fans -v 0.0.1
sudo dkms install -m zettlab-d8-fans -v 0.0.1
sudo modprobe zettlab_d8_fans
```

Automatic module load at boot:

```bash
echo zettlab_d8_fans | sudo tee /etc/modules-load.d/zettlab_d8_fans.conf
```

### Verifying The Module
```bash
lsmod | grep zettlab_d8_fans
cat /sys/class/hwmon/hwmon*/name
sensors
```

Expected `hwmon` name: `zettlab_d8_fans`

## lm-sensors Notes
`lm-sensors` works without extra configuration.

Useful command:

```bash
sensors
```

## Final CPU Fan Control Design

### Why CPU Auto Mode Was Not Used
The driver's documented CPU auto mode (`pwm3_enable=2`) was unstable in testing (fan sometimes dropped to 0 RPM).  
The custom service forces manual mode and uses a reliable temperature curve.

### Active Curve
- `<48 °C` → `100`
- `48-55 °C` → `120`
- `56-63 °C` → `140`
- `64-71 °C` → `160`
- `≥72 °C` → `183`

Top-end hysteresis: stays at 183 until temperature drops below 68 °C.

## Exact Script Code – CPU Fan

File: `/usr/local/sbin/cpu-fan-curve.sh`

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

Make executable:
```bash
sudo chmod +x /usr/local/sbin/cpu-fan-curve.sh
```

## CPU Fan systemd Service

File: `/etc/systemd/system/cpu-fan-curve.service`

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

## HDD Fan Control Design (D6 + D8 Support)

The HDD fan controller **automatically detects all existing SATA drives** (sda–sdh).  
This supports both:
- D6 Ultra (up to 6 bays)
- D8 Ultra (up to 8 bays)

If a drive/bay is empty or does not exist, it is skipped gracefully.  
If no SATA drives are detected at all, the service safely falls back to `SAFE_PWM`.

## Exact Script Code – HDD Fan (Updated for D6/D8)

File: `/usr/local/sbin/hdd-fan-curve.sh`

```bash
#!/bin/bash
set -euo pipefail

# Dynamically detect all existing SATA drives (supports D6 + D8)
DRIVES=()
for dev in /dev/sd[a-h]; do
    if [[ -b "$dev" ]]; then
        DRIVES+=("$dev")
    fi
done

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

Make executable:
```bash
sudo chmod +x /usr/local/sbin/hdd-fan-curve.sh
```

## HDD Fan systemd Service

File: `/etc/systemd/system/hdd-fan-curve.service`

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

## Service Management
After creating both scripts and service files:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cpu-fan-curve.service hdd-fan-curve.service
```

Check status:
```bash
systemctl status cpu-fan-curve.service
systemctl status hdd-fan-curve.service
journalctl -u hdd-fan-curve.service -f
```

## Useful Runtime Commands

**Important:** Always use `echo … | sudo tee …` when writing to sysfs files.

```bash
# Read current values
cat /sys/class/hwmon/hwmon7/temp1_input
cat /sys/class/hwmon/hwmon8/pwm3_enable
cat /sys/class/hwmon/hwmon8/pwm3
cat /sys/class/hwmon/hwmon8/fan3_input

# Force manual mode (example)
echo 1 | sudo tee /sys/class/hwmon/hwmon8/pwm3_enable

# Set PWM manually (example)
echo 120 | sudo tee /sys/class/hwmon/hwmon8/pwm3
```

## Recommended Sharing Notes
1. Install the Zettlab fan module through DKMS
2. Verify fans appear in `hwmon`
3. Install `lm-sensors`
4. (Optional) Install Netdata if you want remote monitoring
5. Do **not** rely on stock `fancontrol`
6. Use custom scripts that only write valid `0-183` PWM values
7. The HDD script now automatically supports both D6 and D8