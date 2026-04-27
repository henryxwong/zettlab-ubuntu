#!/bin/bash
set -euo pipefail

# ================== USER-CONFIGURABLE SETTINGS ==================
TARGET_CPU_C=54          # Ideal CPU temperature target (°C)
MIN_SAFE_PWM=65          # Absolute minimum PWM (do not go lower or fans may stall)
MAX_SAFE_TEMP_C=95       # Emergency full speed if smoothed temperature exceeds this
GAIN_TENTHS=20           # Proportional gain ×10

# Asymmetric response & timer-based anti-chatter
RISE_EMA_HUNDREDTHS=25   # Faster response when temperature is rising
FALL_EMA_HUNDREDTHS=8    # Much slower response when temperature is falling
HOLD_TIME_AFTER_UP_SECS=90    # Minimum seconds to hold PWM after any upward change
SLEEP_SECS=6             # Interval between temperature readings (seconds)
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