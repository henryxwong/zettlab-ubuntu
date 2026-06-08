# Fan Control Configuration

> Implements dynamic, temperature-adaptive fan control for both CPU and disk fans on Zettlab D6/D8 Ultra using the `zettlab_d8_fans` kernel module.

## Overview

This guide supports both D6 (6-bay) and D8 (8-bay) variants. The control logic maintains:

- **CPU Package Temperature**: Idle 42–52 °C, Sustained load ≤68 °C
- **HDD Temperatures**: Idle 35–40 °C, Sustained load ≤45 °C

The fan curves are designed to be:

- Highly responsive when temperatures are rising (fast fan ramp-up)
- Much less responsive when temperatures are falling (fans stay higher longer)
- Protected against excessive PWM changes using **timer-based hysteresis**

Both CPU and HDD controllers follow consistent design principles:

- EMA smoothing is calculated before the emergency full-speed check
- Emergency override uses the smoothed temperature (protected against single raw sensor spikes)
- Identical anti-chatter timer logic and asymmetric rise/fall response
- On any temperature sensor read failure, the system forces full fan speed (183 PWM) for safety

## Fan Mapping

| Fan   | Target Component     |
|-------|----------------------|
| fan1  | Rear disk fan 1      |
| fan2  | Rear disk fan 2      |
| fan3  | CPU fan              |

## Prerequisites

- Ubuntu 26.04 Server installed
- User account with `sudo` privileges
- Zettlab D6/D8 Ultra hardware
- `linux-headers-generic` package installed (recommended for reliable DKMS behavior after kernel updates)

## Kernel Module Installation

### Step 1: Install via DKMS

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

### Step 2: Enable Automatic Loading

```bash
echo zettlab_d8_fans | sudo tee /etc/modules-load.d/zettlab_d8_fans.conf
```

### Step 3: Verify Installation

```bash
lsmod | grep zettlab_d8_fans

for d in /sys/class/hwmon/hwmon*; do
    [ -f "$d/name" ] && echo "$d: $(cat "$d/name")"
done

sensors
```

## After Kernel Updates

When Ubuntu installs a new kernel, the `zettlab_d8_fans` DKMS module must be rebuilt for the new kernel version. This is the most common cause of the module not loading after `apt upgrade` (you may see `Exec format error`).

### Recommended One-Time Setup

Install the generic kernel headers package so future kernel updates can be handled more smoothly by DKMS:

```bash
sudo apt install linux-headers-generic
```

### Normal Workflow After Kernel Updates

After any kernel update and reboot, run:

```bash
sudo dkms autoinstall
sudo systemctl restart cpu-fan-curve.service hdd-fan-curve.service
```

### Full Recovery Procedure

If the module fails to load after a kernel update, run this recovery sequence:

```bash
sudo dkms remove -m zettlab-d8-fans -v 0.0.1 --all
sudo apt install linux-headers-$(uname -r) linux-headers-generic
sudo dkms add -m zettlab-d8-fans -v 0.0.1
sudo dkms build -m zettlab-d8-fans -v 0.0.1 -k $(uname -r)
sudo dkms install -m zettlab-d8-fans -v 0.0.1 -k $(uname -r)
sudo modprobe zettlab_d8_fans
sudo systemctl restart cpu-fan-curve.service hdd-fan-curve.service
```

Then verify the module is loaded:

```bash
lsmod | grep zettlab_d8_fans
for d in /sys/class/hwmon/hwmon*; do
    [ -f "$d/name" ] && echo "$d: $(cat "$d/name")"
done
```

### Why This Happens

The `Exec format error` occurs when the compiled kernel module was built against a different kernel version than the one currently running. The steps above force a clean rebuild against the exact running kernel.

## CPU Fan Control

### Script Location

`/usr/local/sbin/cpu-fan-curve.sh`

### Key Parameters

| Parameter                | Default | Description                                      |
|--------------------------|---------|--------------------------------------------------|
| `TARGET_CPU_C`           | 54      | Ideal CPU temperature target (°C)                |
| `MIN_SAFE_PWM`           | 65      | Absolute minimum PWM (fans may stall below this) |
| `MAX_SAFE_TEMP_C`        | 95      | Emergency full speed threshold                   |
| `GAIN_TENTHS`            | 20      | Proportional gain × 10                           |
| `RISE_EMA_HUNDREDTHS`    | 25      | Faster response when temperature rising          |
| `FALL_EMA_HUNDREDTHS`    | 8       | Slower response when temperature falling         |
| `HOLD_TIME_AFTER_UP_SECS`| 90      | Minimum seconds to hold PWM after upward change  |
| `SLEEP_SECS`             | 6       | Interval between temperature readings            |

### Installation

1. Copy the script to `/usr/local/sbin/cpu-fan-curve.sh`
2. Make it executable: `sudo chmod +x /usr/local/sbin/cpu-fan-curve.sh`
3. Create the systemd service:

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

Save as `/etc/systemd/system/cpu-fan-curve.service`.

4. Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cpu-fan-curve.service
```

## HDD Fan Control

### Script Location

`/usr/local/sbin/hdd-fan-curve.sh`

### Key Parameters

| Parameter                | Default | Description                                      |
|--------------------------|---------|--------------------------------------------------|
| `TARGET_HDD_C`           | 44      | Ideal maximum HDD temperature (°C)               |
| `MIN_SAFE_PWM`           | 58      | Absolute minimum PWM for disk fans               |
| `MAX_SAFE_TEMP_C`        | 65      | Emergency full speed threshold                   |
| `GAIN_TENTHS`            | 32      | Proportional gain × 10                           |
| `RISE_EMA_HUNDREDTHS`    | 35      | Faster response when temperature rising          |
| `FALL_EMA_HUNDREDTHS`    | 10      | Slower response when temperature falling         |
| `HOLD_TIME_AFTER_UP_SECS`| 120     | Minimum seconds to hold PWM after upward change  |
| `SLEEP_SECS`             | 20      | Interval between temperature readings            |

The script automatically detects all SATA drives (`/dev/sd[a-h]`) and monitors the maximum temperature.

### Installation

1. Copy the script to `/usr/local/sbin/hdd-fan-curve.sh`
2. Make it executable: `sudo chmod +x /usr/local/sbin/hdd-fan-curve.sh`
3. Create the systemd service:

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

Save as `/etc/systemd/system/hdd-fan-curve.service`.

4. Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now hdd-fan-curve.service
```

## Service Management

### Start and Enable Both Services

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now cpu-fan-curve.service hdd-fan-curve.service
```

### Verify Status

```bash
systemctl status cpu-fan-curve.service
systemctl status hdd-fan-curve.service

# View live logs
journalctl -u cpu-fan-curve.service -f
journalctl -u hdd-fan-curve.service -f
```

## Runtime Commands

### Read Current Values

```bash
# Read hwmon device names
for d in /sys/class/hwmon/hwmon*; do
    [ -f "$d/name" ] && echo "$d: $(cat "$d/name")"
done

# Read temperature values
cat /sys/class/hwmon/hwmon*/temp1_input 2>/dev/null | head -n 5

# Read PWM values
cat /sys/class/hwmon/hwmon*/pwm[1-3] 2>/dev/null
```

### Manual Override Example

```bash
ZETTLAB=$(for d in /sys/class/hwmon/hwmon*; do
    [ -f "$d/name" ] && [[ "$(cat "$d/name")" == "zettlab_d8_fans" ]] && echo "$d"
done)

echo 1 | sudo tee "$ZETTLAB/pwm3_enable"
echo 120 | sudo tee "$ZETTLAB/pwm3"
```

## Expected Behavior

- Fast response on temperature **rise**
- Slow response on temperature **fall** (90s hold for CPU, 120s hold for HDD)
- Very few downward PWM changes after 24–48 hours of mixed load (this is normal and desired)

**Optional fine-tuning**: If your CPU consistently idles 2–3 °C above target, edit `TARGET_CPU_C` in the script.

## Safety Notes

- The curves are intentionally conservative and anti-chatter focused
- PWM values below ~60–80 can cause fan stalling
- Thermal lag is significant (30–120+ seconds)
- All scripts include hard-coded minimum safe PWM and emergency full-speed overrides
- If any temperature sensor fails, the system forces full speed (183 PWM)
- Timer-based hysteresis prevents frequent speed adjustments after any upward change
```