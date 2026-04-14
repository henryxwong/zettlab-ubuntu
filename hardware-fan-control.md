# Fan Control Configuration

**Purpose**

This guide implements fan control for the Zettlab D6/D8 Ultra running Ubuntu 26.04 using the `zettlab_d8_fans` kernel module. It provides dynamic, temperature-adaptive fan control for both CPU and disk fans.

This guide supports both D6 (6-bay) and D8 (8-bay) variants.

## Fan Configuration

| Fan | Target Component |
|-----|------------------|
| `fan1` | Rear disk fan 1 |
| `fan2` | Rear disk fan 2 |
| `fan3` | CPU fan |

## Temperature Targets

The control logic maintains the following targets:

| Component | Idle Range | Maximum Load |
|-----------|------------|--------------|
| CPU Package Temperature | 42–50 °C | 65 °C |
| HDD Temperatures | 32–37 °C | ≤38 °C |

## Safety Considerations

- Fans have a physical minimum effective speed. PWM values below ~60–80 can cause stalling.
- Thermal lag is significant (30–120+ seconds). The controller uses smoothing and conservative gain values.
- All scripts include hard-coded minimum safe PWM values and emergency full-speed overrides.
- If any temperature sensor fails to read, the system falls back to a safe high PWM level.

## Kernel Module Installation

### DKMS Setup

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

### Automatic Module Loading

```bash
echo zettlab_d8_fans | sudo tee /etc/modules-load.d/zettlab_d8_fans.conf
```

### Verification

```bash
lsmod | grep zettlab_d8_fans
for d in /sys/class/hwmon/hwmon*; do [ -f "$d/name" ] && echo "$d: $(cat "$d/name")"; done
sensors
```

## CPU Fan Control

The controller calculates the minimum PWM required to maintain CPU near target temperature using EMA smoothing and configurable parameters.

```bash
#!/bin/bash
set -euo pipefail

# ================== USER-CONFIGURABLE SETTINGS ==================
TARGET_CPU_C=45          # Ideal CPU temperature target (°C)
MIN_SAFE_PWM=80          # Absolute minimum PWM (do not go lower or fans may stall)
MAX_SAFE_TEMP_C=70       # Force full speed (183) if temperature exceeds this
GAIN_TENTHS=40           # Proportional gain ×10 (40 = 4.0). Higher = more aggressive
EMA_HUNDREDTHS=25        # EMA smoothing factor ×100 (25 = 0.25). Lower = slower response
# ============================================================

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

SLEEP_SECS=4

read_temp_c() {
    local temp_milli
    temp_milli=$(<"$TEMP_INPUT") || return 1
    printf '%d\n' "$((temp_milli / 1000))"
}

apply_pwm() {
    local pwm=$1
    printf '1\n' >"$PWM_ENABLE"
    printf '%s\n' "$pwm" >"$PWM_OUTPUT"
}

main_loop() {
    local temp_c smoothed_temp error pwm last_temp=0

    while true; do
        if ! temp_c=$(read_temp_c); then
            apply_pwm "$MIN_SAFE_PWM"
            sleep "$SLEEP_SECS"
            continue
        fi

        # EMA smoothing (integer math)
        if (( last_temp > 0 )); then
            smoothed_temp=$(( (last_temp * (100 - EMA_HUNDREDTHS) + temp_c * EMA_HUNDREDTHS) / 100 ))
        else
            smoothed_temp=$temp_c
        fi

        # Emergency full speed override
        if (( temp_c >= MAX_SAFE_TEMP_C )); then
            apply_pwm 183
            last_temp=$smoothed_temp
            sleep "$SLEEP_SECS"
            continue
        fi

        # Proportional control (integer math)
        error=$(( smoothed_temp - TARGET_CPU_C ))
        pwm=$(( MIN_SAFE_PWM + (GAIN_TENTHS * error) / 10 ))

        # Clamp values
        (( pwm < MIN_SAFE_PWM )) && pwm=$MIN_SAFE_PWM
        (( pwm > 183 )) && pwm=183

        apply_pwm "$pwm"
        last_temp=$smoothed_temp
        sleep "$SLEEP_SECS"
    done
}

main_loop
```

### CPU Fan Service

Save as `/usr/local/sbin/cpu-fan-curve.sh` and make executable:

```bash
sudo chmod +x /usr/local/sbin/cpu-fan-curve.sh
```

Service file: `/etc/systemd/system/cpu-fan-curve.service`

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

## HDD Fan Control

The controller detects all SATA drives (sda–sdh), reads the highest SMART temperature, and controls both rear disk fans. Empty bays are automatically ignored.

```bash
#!/bin/bash
set -euo pipefail

# ================== USER-CONFIGURABLE SETTINGS ==================
TARGET_HDD_C=39          # Ideal maximum HDD temperature (°C)
MIN_SAFE_PWM=60          # Absolute minimum PWM for disk fans
MAX_SAFE_TEMP_C=50       # Force full speed (183) if any drive exceeds this
GAIN_TENTHS=22           # Proportional gain ×10 (22 = 2.2). Lower because HDDs react slower
EMA_HUNDREDTHS=25        # EMA smoothing factor ×100 (25 = 0.25)
# ============================================================

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
SLEEP_SECS=20

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

apply_pwm() {
    local pwm=$1 output
    for output in "${PWM_OUTPUTS[@]}"; do
        printf '%s\n' "$pwm" >"$output"
    done
}

main_loop() {
    local temp_c smoothed_temp error pwm last_temp=0

    while true; do
        if ! temp_c=$(read_max_hdd_temp); then
            apply_pwm "$MIN_SAFE_PWM"
            sleep "$SLEEP_SECS"
            continue
        fi

        # EMA smoothing (integer math)
        if (( last_temp > 0 )); then
            smoothed_temp=$(( (last_temp * (100 - EMA_HUNDREDTHS) + temp_c * EMA_HUNDREDTHS) / 100 ))
        else
            smoothed_temp=$temp_c
        fi

        # Emergency full speed override
        if (( temp_c >= MAX_SAFE_TEMP_C )); then
            apply_pwm 183
            last_temp=$smoothed_temp
            sleep "$SLEEP_SECS"
            continue
        fi

        # Proportional control (integer math)
        error=$(( smoothed_temp - TARGET_HDD_C ))
        pwm=$(( MIN_SAFE_PWM + (GAIN_TENTHS * error) / 10 ))

        # Clamp values
        (( pwm < MIN_SAFE_PWM )) && pwm=$MIN_SAFE_PWM
        (( pwm > 183 )) && pwm=183

        apply_pwm "$pwm"
        last_temp=$smoothed_temp
        sleep "$SLEEP_SECS"
    done
}

main_loop
```

### HDD Fan Service

Save as `/usr/local/sbin/hdd-fan-curve.sh` and make executable:

```bash
sudo chmod +x /usr/local/sbin/hdd-fan-curve.sh
```

Service file: `/etc/systemd/system/hdd-fan-curve.service`

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

## Service Activation

After creating both scripts and service files:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cpu-fan-curve.service hdd-fan-curve.service
```

### Service Status

```bash
systemctl status cpu-fan-curve.service
systemctl status hdd-fan-curve.service
journalctl -u cpu-fan-curve.service -f
journalctl -u hdd-fan-curve.service -f
```

## Runtime Commands

```bash
# Read current hwmon devices and names
for d in /sys/class/hwmon/hwmon*; do [ -f "$d/name" ] && echo "$d: $(cat "$d/name")"; done

# Read temperature values
cat /sys/class/hwmon/hwmon*/temp1_input 2>/dev/null | head -n 5

# Read PWM values
cat /sys/class/hwmon/hwmon*/pwm[1-3] 2>/dev/null
```

### Manual Override

```bash
ZETTLAB=$(for d in /sys/class/hwmon/hwmon*; do [ -f "$d/name" ] && [[ "$(cat "$d/name")" == "zettlab_d8_fans" ]] && echo "$d"; done)
echo 1 | sudo tee "$ZETTLAB/pwm3_enable"
echo 120 | sudo tee "$ZETTLAB/pwm3"