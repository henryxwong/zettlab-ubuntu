# Fan Control Guide for Zettlab D6/D8 Ultra on Ubuntu 26.04

## Scope
This document captures the complete fan control implementation for the Zettlab D6/D8 Ultra NAS on Ubuntu 26.04. It exposes fan telemetry via the community `zettlab_d8_fans` kernel module and uses custom systemd services for temperature-based control.

This guide fully supports both D6 (6-bay) and D8 (8-bay) variants.

## Ideal Operating Temperatures
The updated fan curves are designed to maintain these targets for maximum longevity and silence:

- **CPU Package Temperature** (coretemp): 40–50 °C at idle, under 65 °C under typical load.
- **HDD Temperatures** (SMART): Maximum of any drive under 40 °C.

These values balance cooling needs with minimal fan noise. The CPU is Intel Core Ultra 5 125H (PL1/PL2 locked at 45 W / 93 W). NAS HDDs run best and last longest in the 30–40 °C range.

## What Is Implemented
1. A DKMS-installed kernel module exposes the NAS fans in `hwmon`.
2. `lm-sensors` is installed for local sensor visibility.
3. **(Optional)** Netdata is installed for monitoring (graphs + Netdata Cloud).
4. A custom `systemd` service controls the CPU fan in manual mode based on CPU package temperature (with smoothing).
5. A second custom `systemd` service controls the HDD fans from the highest SATA SMART temperature (supports both D6 and D8, with smoothing).
6. The stock `fancontrol` package was removed because it is incompatible with this driver.

## Why A Custom Service Was Needed
The Zettlab fan driver accepts PWM values in the range `0-183`.

Ubuntu's stock `fancontrol` tooling assumes a `0-255` style PWM range and fails during probing and startup.

The custom service writes only valid `0-183` values and includes exponential moving average (EMA) smoothing to ignore short temperature spikes.

## Fan Layout
- `fan1`: rear disk fan 1
- `fan2`: rear disk fan 2
- `fan3`: CPU fan

On this system:
- Disk fans are manual only through this driver.
- CPU auto mode (`pwm3_enable=2`) was unstable in testing and is not used.
- CPU fan is kept in manual mode.
- HDD fans are driven from SATA SMART temperatures by a separate service.

## Important Paths
The scripts use **dynamic hwmon discovery** by device name.  
This ensures compatibility across D6/D8 hardware and different boot configurations.

- Zettlab fan controller: discovered as `zettlab_d8_fans`
- CPU package temperature: discovered as `coretemp`
- Runtime state files: `/run/cpu-fan-curve.state` and `/run/hdd-fan-curve.state`

## Optional: Netdata Setup
Netdata is optional.

```bash
sudo bash <(curl -Ss https://get.netdata.cloud/kickstart.sh) --stable-channel --install-type static
```

Check status:
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
for d in /sys/class/hwmon/hwmon*; do [ -f "$d/name" ] && echo "$d: $(cat "$d/name")"; done
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
CPU auto mode (`pwm3_enable=2`) was unstable. The custom service forces manual mode and uses a reliable temperature curve with EMA smoothing.

### Active Curve
- `<45 °C` → `80`
- `45-52 °C` → `100`
- `53-59 °C` → `120`
- `60-66 °C` → `140`
- `67-73 °C` → `160`
- `≥74 °C` → `183`

Top-end hysteresis: stays at 183 until temperature drops below 70 °C.

### Exact Script Code – CPU Fan
File: `/usr/local/sbin/cpu-fan-curve.sh`

```bash
#!/bin/bash
set -euo pipefail

# === Dynamic hwmon discovery ===
find_hwmon_by_name() {
    local target_name="$1"
    for dir in /sys/class/hwmon/hwmon*; do
        if [[ -f "$dir/name" ]] && [[ "$(cat "$dir/name" 2>/dev/null)" == "$target_name" ]]; then
            echo "$dir"
            return 0
        fi
    done
    echo "ERROR: Could not find hwmon device with name '$target_name'. Is the zettlab_d8_fans module loaded?" >&2
    return 1
}

ZETTLAB_HWMON=$(find_hwmon_by_name "zettlab_d8_fans") || exit 1
CPU_HWMON=$(find_hwmon_by_name "coretemp") || exit 1

TEMP_INPUT="$CPU_HWMON/temp1_input"
PWM_ENABLE="$ZETTLAB_HWMON/pwm3_enable"
PWM_OUTPUT="$ZETTLAB_HWMON/pwm3"

STATE_FILE="/run/cpu-fan-curve.state"
SLEEP_SECS=4
HYSTERESIS_C=4
SAFE_PWM=100
FULL_SPEED_ON_C=74
FULL_SPEED_OFF_C=70

read_temp_c() {
    local temp_milli
    temp_milli=$(<"$TEMP_INPUT") || return 1
    printf '%d\n' "$((temp_milli / 1000))"
}

target_pwm_for_temp() {
    local temp_c=$1
    if (( temp_c >= FULL_SPEED_ON_C )); then
        printf '183\n'
    elif (( temp_c >= 67 )); then
        printf '160\n'
    elif (( temp_c >= 60 )); then
        printf '140\n'
    elif (( temp_c >= 53 )); then
        printf '120\n'
    elif (( temp_c >= 45 )); then
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
    local pwm=$1
    printf '1\n' >"$PWM_ENABLE"
    printf '%s\n' "$pwm" >"$PWM_OUTPUT"
}

main_loop() {
    local temp_c smoothed_temp target_pwm

    read_state

    while true; do
        if ! temp_c=$(read_temp_c); then
            apply_pwm "$SAFE_PWM"
            write_state "$SAFE_PWM" -1000
            sleep "$SLEEP_SECS"
            continue
        fi

        # Exponential moving average smoothing (75% previous, 25% new) to ignore short spikes
        if (( last_temp > 0 )); then
            smoothed_temp=$(( (last_temp * 3 + temp_c) / 4 ))
        else
            smoothed_temp=$temp_c
        fi

        target_pwm=$(target_pwm_for_temp "$smoothed_temp")

        if (( last_pwm == -1 )); then
            apply_pwm "$target_pwm"
            last_pwm=$target_pwm
            last_temp=$smoothed_temp
            write_state "$last_pwm" "$last_temp"
            sleep "$SLEEP_SECS"
            continue
        fi

        if (( temp_c >= FULL_SPEED_ON_C && last_pwm < 183 )); then
            apply_pwm 183
            last_pwm=183
            last_temp=$smoothed_temp
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
            last_temp=$smoothed_temp
            write_state "$last_pwm" "$last_temp"
            sleep "$SLEEP_SECS"
            continue
        fi

        if (( target_pwm < last_pwm && temp_c <= last_temp - HYSTERESIS_C )); then
            apply_pwm "$target_pwm"
            last_pwm=$target_pwm
            last_temp=$smoothed_temp
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

## HDD Fan Control Design (D6 + D8 Support)
The HDD fan controller automatically detects all existing SATA drives (sda–sdh). It supports both D6 Ultra and D8 Ultra. Empty bays are skipped gracefully. If no SATA drives are detected, it falls back safely to `SAFE_PWM`.

### Active Curve
- `<30 °C` → `60`
- `30-34 °C` → `80`
- `35-37 °C` → `100`
- `38-40 °C` → `120`
- `41-43 °C` → `140`
- `≥44 °C` → `183`

Top-end hysteresis: stays at 183 until temperature drops below 41 °C.

### Exact Script Code – HDD Fan
File: `/usr/local/sbin/hdd-fan-curve.sh`

```bash
#!/bin/bash
set -euo pipefail

# === Dynamic hwmon discovery ===
find_hwmon_by_name() {
    local target_name="$1"
    for dir in /sys/class/hwmon/hwmon*; do
        if [[ -f "$dir/name" ]] && [[ "$(cat "$dir/name" 2>/dev/null)" == "$target_name" ]]; then
            echo "$dir"
            return 0
        fi
    done
    echo "ERROR: Could not find hwmon device with name '$target_name'. Is the zettlab_d8_fans module loaded?" >&2
    return 1
}

ZETTLAB_HWMON=$(find_hwmon_by_name "zettlab_d8_fans") || exit 1

# Dynamically detect all existing SATA drives (supports D6 + D8)
DRIVES=()
for dev in /dev/sd[a-h]; do
    if [[ -b "$dev" ]]; then
        DRIVES+=("$dev")
    fi
done

PWM_OUTPUTS=("$ZETTLAB_HWMON/pwm1" "$ZETTLAB_HWMON/pwm2")
STATE_FILE="/run/hdd-fan-curve.state"
SLEEP_SECS=20
HYSTERESIS_C=3
SAFE_PWM=80
FULL_SPEED_ON_C=44
FULL_SPEED_OFF_C=41

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
    elif (( temp_c >= 41 )); then
        printf '140\n'
    elif (( temp_c >= 38 )); then
        printf '120\n'
    elif (( temp_c >= 35 )); then
        printf '100\n'
    elif (( temp_c >= 30 )); then
        printf '80\n'
    else
        printf '60\n'
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
    local temp_c smoothed_temp target_pwm

    read_state

    while true; do
        if ! temp_c=$(read_max_hdd_temp); then
            apply_pwm "$SAFE_PWM"
            write_state "$SAFE_PWM" -1000
            sleep "$SLEEP_SECS"
            continue
        fi

        # Exponential moving average smoothing (75% previous, 25% new) to ignore short spikes
        if (( last_temp > 0 )); then
            smoothed_temp=$(( (last_temp * 3 + temp_c) / 4 ))
        else
            smoothed_temp=$temp_c
        fi

        target_pwm=$(target_pwm_for_temp "$smoothed_temp")

        if (( last_pwm == -1 )); then
            apply_pwm "$target_pwm"
            last_pwm=$target_pwm
            last_temp=$smoothed_temp
            write_state "$last_pwm" "$last_temp"
            sleep "$SLEEP_SECS"
            continue
        fi

        if (( temp_c >= FULL_SPEED_ON_C && last_pwm < 183 )); then
            apply_pwm 183
            last_pwm=183
            last_temp=$smoothed_temp
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
            last_temp=$smoothed_temp
            write_state "$last_pwm" "$last_temp"
            sleep "$SLEEP_SECS"
            continue
        fi

        if (( target_pwm < last_pwm && temp_c <= last_temp - HYSTERESIS_C )); then
            apply_pwm "$target_pwm"
            last_pwm=$target_pwm
            last_temp=$smoothed_temp
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
journalctl -u cpu-fan-curve.service -f
journalctl -u hdd-fan-curve.service -f
```

## Useful Runtime Commands
Always use `echo … | sudo tee …` when writing to sysfs files.

```bash
# Read current values
for d in /sys/class/hwmon/hwmon*; do [ -f "$d/name" ] && echo "$d: $(cat "$d/name")"; done
cat /sys/class/hwmon/hwmon*/temp1_input 2>/dev/null | head -n 5
cat /sys/class/hwmon/hwmon*/pwm[1-3] 2>/dev/null
```

**Manual override example:**
```bash
ZETTLAB=$(for d in /sys/class/hwmon/hwmon*; do [ -f "$d/name" ] && [[ "$(cat "$d/name")" == "zettlab_d8_fans" ]] && echo "$d"; done)
echo 1 | sudo tee "$ZETTLAB/pwm3_enable"
echo 120 | sudo tee "$ZETTLAB/pwm3"
```

## Recommended Notes
1. Install the Zettlab fan module through DKMS.
2. Verify fans appear in `hwmon`.
3. Install `lm-sensors`.
4. (Optional) Install Netdata for remote monitoring.
5. Do **not** rely on stock `fancontrol`.
6. The HDD script automatically supports both D6 and D8.
7. Monitor with `sensors` and Netdata after installation.