#!/bin/bash
set -euo pipefail

# ================== USER-CONFIGURABLE SETTINGS ==================
TARGET_HDD_C=40          # Ideal maximum HDD temperature (°C)
MIN_SAFE_PWM=58          # Absolute minimum PWM for disk fans
MAX_SAFE_TEMP_C=63       # Emergency full speed if smoothed temperature exceeds this
GAIN_TENTHS=45           # Proportional gain ×10

# Asymmetric response & timer-based anti-chatter
RISE_EMA_HUNDREDTHS=35   # Faster response when temperature is rising
FALL_EMA_HUNDREDTHS=10   # Much slower response when temperature is falling
HOLD_TIME_AFTER_UP_SECS=120   # Minimum seconds to hold PWM after any upward change
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
            # SAFETY: Force full speed on any sensor read failure
            apply_pwm 183
            last_pwm=183
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