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
- On any temperature sensor read failure, the system forces full fan speed (183 PWM) for safety

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

### Script Location

The CPU fan control script is located at: `/usr/local/sbin/cpu-fan-curve.sh`

### Configuration

Key parameters (edit in the script):

| Parameter | Default | Description |
|-----------|---------|-------------|
| `TARGET_CPU_C` | 50 | Ideal CPU temperature target (°C) |
| `MIN_SAFE_PWM` | 65 | Absolute minimum PWM (fans may stall below this) |
| `MAX_SAFE_TEMP_C` | 88 | Emergency full speed if smoothed temp exceeds this |
| `GAIN_TENTHS` | 32 | Proportional gain × 10 |
| `RISE_EMA_HUNDREDTHS` | 25 | Faster response when temperature rising |
| `FALL_EMA_HUNDREDTHS` | 8 | Slower response when temperature falling |
| `HOLD_TIME_AFTER_UP_SECS` | 90 | Minimum seconds to hold PWM after upward change |

### Installation

1. Copy the script to `/usr/local/sbin/cpu-fan-curve.sh`
2. Make it executable: `sudo chmod +x /usr/local/sbin/cpu-fan-curve.sh`
3. Create the systemd service at `/etc/systemd/system/cpu-fan-curve.service`:

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

4. Enable and start: `sudo systemctl daemon-reload && sudo systemctl enable --now cpu-fan-curve.service`

## HDD Fan Control

### Script Location

The HDD fan control script is located at: `/usr/local/sbin/hdd-fan-curve.sh`

### Configuration

Key parameters (edit in the script):

| Parameter | Default | Description |
|-----------|---------|-------------|
| `TARGET_HDD_C` | 40 | Ideal maximum HDD temperature (°C) |
| `MIN_SAFE_PWM` | 58 | Absolute minimum PWM for disk fans |
| `MAX_SAFE_TEMP_C` | 63 | Emergency full speed if smoothed temp exceeds this |
| `GAIN_TENTHS` | 45 | Proportional gain × 10 |
| `RISE_EMA_HUNDREDTHS` | 35 | Faster response when temperature rising |
| `FALL_EMA_HUNDREDTHS` | 10 | Slower response when temperature falling |
| `HOLD_TIME_AFTER_UP_SECS` | 120 | Minimum seconds to hold PWM after upward change |

The script automatically detects all SATA drives (/dev/sd[a-h]) and monitors the maximum temperature.

### Installation

1. Copy the script to `/usr/local/sbin/hdd-fan-curve.sh`
2. Make it executable: `sudo chmod +x /usr/local/sbin/hdd-fan-curve.sh`
3. Create the systemd service at `/etc/systemd/system/hdd-fan-curve.service`:

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

4. Enable and start: `sudo systemctl daemon-reload && sudo systemctl enable --now hdd-fan-curve.service`

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

The controllers are designed to be:
- Fast on temperature **rise** (quick response to load)
- Slow on temperature **fall** (90-second hold for CPU, 120-second hold for HDD fans after any upward change)

This prevents annoying fan "hunting" and reduces mechanical wear.

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
If your CPU consistently idles 2–3 °C above the target you prefer, edit `/usr/local/sbin/cpu-fan-curve.sh` and lower `TARGET_CPU_C` from `50` to `48`. No other values need changing.

## Safety Notes

- The fan curves are intentionally conservative and anti-chatter focused. You will rarely (if ever) hear the fans ramp up and down rapidly.
- Fans have a physical minimum effective speed. PWM values below ~60–80 can cause stalling.
- Thermal lag is significant (30–120+ seconds). The controller uses smoothing and conservative gain values.
- All scripts include hard-coded minimum safe PWM values and emergency full-speed overrides.
- If any temperature sensor fails to read, the system forces full-speed (183 PWM).
- Timer-based hysteresis (`HOLD_TIME_AFTER_UP_SECS`) holds the fan PWM steady for the configured time after any upward change, preventing frequent speed adjustments.
- Emergency overrides in both controllers use smoothed temperature to prevent false triggers from short sensor spikes.