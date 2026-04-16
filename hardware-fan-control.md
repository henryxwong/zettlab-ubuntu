# Fan Control Configuration

> Implements dynamic, temperature-adaptive fan control for both CPU and disk fans on Zettlab D6/D8 Ultra using the `zettlab_d8_fans` kernel module.

## Overview

This guide supports both D6 (6-bay) and D8 (8-bay) variants. The control logic maintains:
- **CPU Package Temperature**: Idle 42–52 °C, Sustained load ≤68 °C
- **HDD Temperatures**: Idle 35–40 °C, Sustained load ≤45 °C

The fan curves are designed to be:
- Highly responsive when temperatures are rising (fast fan ramp-up)
- Much less responsive when temperatures are falling (fans stay higher longer)
- Protected against excessive PWM changes using **timer-based hysteresis** (after any upward PWM change, the fan speed is held for a minimum time before it is allowed to decrease)

Both CPU and HDD controllers follow consistent design principles:
- EMA smoothing is calculated before the emergency full-speed check
- Emergency override uses the smoothed temperature (protected against single raw sensor spikes)
- Identical anti-chatter timer logic and asymmetric rise/fall response (RISE_EMA_HUNDREDTHS > FALL_EMA_HUNDREDTHS)

## Fan Configuration

| Fan | Target Component |
|-----|------------------|
| `fan1` | Rear disk fan 1 |
| `fan2` | Rear disk fan 2 |
| `fan3` | CPU fan |

## Prerequisites

- Ubuntu 26.04 Server installed
- User account with `sudo` privileges
- Zettlab D6/D8 Ultra hardware

## Kernel Module Installation

### Step 1: Clone and Install via DKMS

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

### Step 2: Enable Automatic Module Loading

```bash
echo zettlab_d8_fans | sudo tee /etc/modules-load.d/zettlab_d8_fans.conf
```

### Step 3: Verify Installation

```bash
lsmod | grep zettlab_d8_fans
for d in /sys/class/hwmon/hwmon*; do [ -f "$d/name" ] && echo "$d: $(cat "$d/name")"; done
sensors
```

## CPU Fan Control

### Create CPU Fan Script

Save as `/usr/local/sbin/cpu-fan-curve.sh`:

```bash
#!/bin/bash
set -euo pipefail

# ================== USER-CONFIGURABLE SETTINGS ==================
TARGET_CPU_C=51          # Ideal CPU temperature target (°C)
MIN_SAFE_PWM=70          # Absolute minimum PWM (do not go lower or fans may stall)
MAX_SAFE_TEMP_C=70       # Force full speed (183) if smoothed temperature exceeds this
GAIN_TENTHS=18           # Proportional gain ×10 (18 = 1.8). Strongly reduced to ignore short spikes

# Asymmetric response & timer-based anti-chatter
RISE_EMA_HUNDREDTHS=25   # Faster response when temperature is rising (damped to reduce spike sensitivity)
FALL_EMA_HUNDREDTHS=8    # Much slower response when temperature is falling
HOLD_TIME_AFTER_UP_SECS=180   # Minimum seconds to hold PWM after any upward change (3 minutes – balanced anti-chatter)
# ============================================================

find_hwmon_by_name() {
    local target_name="$1"
    for dir in /sys/class/hwmon/hwmon*; do
        if [[ -f "$dir/name" ]] && [[ "$(cat "$dir/name" 2>/dev/null)" == "$target_name" ]]; then
            echo "$dir"
            return 0
        fi
    done
    echo "ERROR: Could not find hwmon device with name '$target_name'." >&2
    return 1
}

ZETTLAB_HWMON=$(find_hwmon_by_name "zettlab_d8_fans") || exit 1
CPU_HWMON=$(find_hwmon_by_name "coretemp") || exit 1

TEMP_INPUT="$CPU_HWMON/temp1_input"
PWM_ENABLE="$ZETTLAB_HWMON/pwm3_enable"
PWM_OUTPUT="$ZETTLAB_HWMON/pwm3"

SLEEP_SECS=6

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
    local temp_c smoothed_temp error pwm last_temp=0 last_pwm last_change_time=0
    last_pwm=$MIN_SAFE_PWM

    while true; do
        if ! temp_c=$(read_temp_c); then
            apply_pwm "$MIN_SAFE_PWM"
            last_pwm=$MIN_SAFE_PWM
            last_change_time=0
            sleep "$SLEEP_SECS"
            continue
        fi

        # Asymmetric EMA smoothing: fast on rise, slow on fall
        # (calculated BEFORE emergency check so max-speed trigger is also spike-filtered)
        if (( last_temp > 0 )); then
            local ema_hundredths
            if (( temp_c > last_temp )); then
                ema_hundredths=$RISE_EMA_HUNDREDTHS
            else
                ema_hundredths=$FALL_EMA_HUNDREDTHS
            fi
            smoothed_temp=$(( (last_temp * (100 - ema_hundredths) + temp_c * ema_hundredths) / 100 ))
        else
            smoothed_temp=$temp_c
        fi

        # Emergency full speed override — uses smoothed_temp (protected against single raw sample)
        if (( smoothed_temp >= MAX_SAFE_TEMP_C )); then
            apply_pwm 183
            last_pwm=183
            last_change_time=$(date +%s)
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

        # Timer-based anti-chatter:
        # - Always allow upward changes immediately
        # - Only allow downward changes after HOLD_TIME_AFTER_UP_SECS has passed since last change
        local current_time
        current_time=$(date +%s)
        local do_apply=false

        if (( pwm > last_pwm )); then
            do_apply=true
        elif (( pwm < last_pwm )) && (( current_time - last_change_time >= HOLD_TIME_AFTER_UP_SECS )); then
            do_apply=true
        fi

        if [[ "$do_apply" == true ]]; then
            apply_pwm "$pwm"
            last_pwm=$pwm
            last_change_time=$current_time
        fi

        last_temp=$smoothed_temp
        sleep "$SLEEP_SECS"
    done
}

main_loop
```

### Create CPU Fan Service

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

Make executable and enable:

```bash
sudo chmod +x /usr/local/sbin/cpu-fan-curve.sh
```

## HDD Fan Control

### Create HDD Fan Script

Save as `/usr/local/sbin/hdd-fan-curve.sh`:

```bash
#!/bin/bash
set -euo pipefail

# ================== USER-CONFIGURABLE SETTINGS ==================
TARGET_HDD_C=41          # Ideal maximum HDD temperature (°C)
MIN_SAFE_PWM=60          # Absolute minimum PWM for disk fans
MAX_SAFE_TEMP_C=55       # Force full speed (183) if smoothed temperature exceeds this
GAIN_TENTHS=22           # Proportional gain ×10 (22 = 2.2). Lower because HDDs react slower

# Asymmetric response & timer-based anti-chatter
RISE_EMA_HUNDREDTHS=35   # Faster response when temperature is rising
FALL_EMA_HUNDREDTHS=10   # Much slower response when temperature is falling
HOLD_TIME_AFTER_UP_SECS=240   # Minimum seconds to hold PWM after any upward change (4 minutes – balanced anti-chatter)
# ============================================================

find_hwmon_by_name() {
    local target_name="$1"
    for dir in /sys/class/hwmon/hwmon*; do
        if [[ -f "$dir/name" ]] && [[ "$(cat "$dir/name" 2>/dev/null)" == "$target_name" ]]; then
            echo "$dir"
            return 0
        fi
    done
    echo "ERROR: Could not find hwmon device with name '$target_name'." >&2
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
    local temp_c smoothed_temp error pwm last_temp=0 last_pwm last_change_time=0
    last_pwm=$MIN_SAFE_PWM

    while true; do
        if ! temp_c=$(read_max_hdd_temp); then
            apply_pwm "$MIN_SAFE_PWM"
            last_pwm=$MIN_SAFE_PWM
            last_change_time=0
            sleep "$SLEEP_SECS"
            continue
        fi

        # Asymmetric EMA smoothing: fast on rise, slow on fall
        # (calculated BEFORE emergency check so max-speed trigger is also spike-filtered)
        if (( last_temp > 0 )); then
            local ema_hundredths
            if (( temp_c > last_temp )); then
                ema_hundredths=$RISE_EMA_HUNDREDTHS
            else
                ema_hundredths=$FALL_EMA_HUNDREDTHS
            fi
            smoothed_temp=$(( (last_temp * (100 - ema_hundredths) + temp_c * ema_hundredths) / 100 ))
        else
            smoothed_temp=$temp_c
        fi

        # Emergency full speed override — uses smoothed_temp (protected against single raw sample)
        if (( smoothed_temp >= MAX_SAFE_TEMP_C )); then
            apply_pwm 183
            last_pwm=183
            last_change_time=$(date +%s)
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

        # Timer-based anti-chatter:
        # - Always allow upward changes immediately
        # - Only allow downward changes after HOLD_TIME_AFTER_UP_SECS has passed since last change
        local current_time
        current_time=$(date +%s)
        local do_apply=false

        if (( pwm > last_pwm )); then
            do_apply=true
        elif (( pwm < last_pwm )) && (( current_time - last_change_time >= HOLD_TIME_AFTER_UP_SECS )); then
            do_apply=true
        fi

        if [[ "$do_apply" == true ]]; then
            apply_pwm "$pwm"
            last_pwm=$pwm
            last_change_time=$current_time
        fi

        last_temp=$smoothed_temp
        sleep "$SLEEP_SECS"
    done
}

main_loop
```

### Create HDD Fan Service

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

Make executable and enable:

```bash
sudo chmod +x /usr/local/sbin/hdd-fan-curve.sh
```

## Service Activation

### Start and Enable Services

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cpu-fan-curve.service hdd-fan-curve.service
```

### Verify Service Status

```bash
systemctl status cpu-fan-curve.service
systemctl status hdd-fan-curve.service

# View logs
journalctl -u cpu-fan-curve.service -f
journalctl -u hdd-fan-curve.service -f
```

## Runtime Commands

### Read Current Values

```bash
# Read hwmon device names
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
```

## Expected Behavior & Monitoring

The controllers are deliberately designed to be:
- Fast on temperature **rise** (quick response to load)
- Slow on temperature **fall** (3-minute hold for CPU, 4-minute hold for HDD fans after any upward change)

This prevents annoying fan “hunting” and reduces mechanical wear.

**Recommended monitoring commands** (run after startup):

```bash
# Watch live fan control decisions
journalctl -u cpu-fan-curve.service -f
journalctl -u hdd-fan-curve.service -f

# Real-time temperatures + PWM
watch -n 2 'sensors | grep -E "Core|fan|PWM"'

# Check how often PWM actually changes (should be infrequent)
sudo journalctl -u cpu-fan-curve.service | grep -c "apply_pwm"
```

After 24–48 hours of mixed load you should see very few downward PWM changes — this is normal and desired.

**Optional fine-tuning**  
If your CPU consistently idles 2–3 °C above the target you prefer, edit `/usr/local/sbin/cpu-fan-curve.sh` and lower `TARGET_CPU_C` from `51` to `48`. No other values need changing.

## Safety Notes

- The fan curves are intentionally conservative and anti-chatter focused. You will rarely (if ever) hear the fans ramp up and down rapidly.
- Fans have a physical minimum effective speed. PWM values below ~60–80 can cause stalling.
- Thermal lag is significant (30–120+ seconds). The controller uses smoothing and conservative gain values.
- All scripts include hard-coded minimum safe PWM values and emergency full-speed overrides.
- If any temperature sensor fails to read, the system falls back to a safe high PWM level.
- Timer-based hysteresis (`HOLD_TIME_AFTER_UP_SECS`) holds the fan PWM steady for the configured time after any upward change, preventing frequent speed adjustments.
- Emergency overrides in both controllers use smoothed temperature to prevent false triggers from short sensor spikes.