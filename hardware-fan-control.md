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

## Verified sysfs Interface

Confirmed on Ubuntu 26.04, kernel 7.0.0-30-generic:

```
/sys/class/hwmon/hwmonN/     name = zettlab_d8_fans
  pwm1  pwm2  pwm3           0-183   (not 0-255)
  pwm1_enable ...            present, but read-only on this build
  fan1_input  fan2_input  fan3_input    tachometer, RPM
  fan1_label  fan2_label  fan3_label    "Disks 1" / "Disks 2" / "CPU"
```

`fanN_label` confirms the mapping on a live system, so you do not have to trust the
table below — read it off the hardware.

Writing `pwmN_enable` returns `Permission denied`. That is harmless: writing `pwmN`
directly works without it.

Typical readings at idle with the curve services running: disk fans ~920 rpm at PWM 67,
CPU fan ~3550 rpm at PWM 120.

> **DKMS signs the module automatically.** On Ubuntu the build is signed with
> `/var/lib/shim-signed/mok/MOK.priv` as part of `dkms build`. With Secure Boot off it
> loads regardless; with Secure Boot on you still need to enrol that MOK.

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
```

Upstream's Makefile pins the build to the **running** kernel, and `dkms.conf` runs
`make` itself, so DKMS's `-k <target>` never takes effect. Write the corrected Makefile
over the copy before the first build — otherwise the first kernel upgrade after this
install boots without fan control (see [Why This Happens](#why-this-happens)):

```bash
sudo tee /usr/src/zettlab-d8-fans-0.0.1/Makefile >/dev/null <<'EOF'
obj-m += zettlab_d8_fans.o

# DKMS exports KERNELRELEASE for the target kernel; uname -r is only the
# fallback for a hand-run build in the running tree.
KREL := $(if $(KERNELRELEASE),$(KERNELRELEASE),$(shell uname -r))
KDIR := /lib/modules/$(KREL)/build
PWD  := $(shell pwd)

all:
	make -C $(KDIR) M=$(PWD) modules

clean:
	make -C $(KDIR) M=$(PWD) clean
EOF
```

```bash
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

## The First Kernel Upgrade Will Catch You Out

Observed on a real install, and worth understanding before it bites.

`linux-headers-generic` is a **meta-package that pulls the newest kernel**, which is
often newer than the one you are running. So this sequence quietly leaves you exposed:

```
19:58:46  apt install build-essential dkms linux-headers-generic ...
          -> also installs linux-image-7.0.0-31-generic  (you are running -30)
19:59:37  dkms add / build / install
          -> builds for the RUNNING kernel only, -30
```

DKMS' autoinstall hook fires **when a kernel is installed**. At 19:58 the module did not
exist yet, so nothing was built for `-31`. `dkms status` then shows only `-30`, which
looks perfectly healthy — until you reboot into `-31` and the module is simply absent:

```
ERROR: Could not find hwmon device with name 'zettlab_d8_fans'.
hdd-fan-curve.service: Failed with result 'exit-code'.
```

**Both fan services fail and the fans revert to whatever the firmware last set.**

### Cover every installed kernel after adding the module

```bash
sudo dkms autoinstall
sudo dkms status            # expect a line per installed kernel, not just one
```

Or target one explicitly:

```bash
sudo dkms install -m zettlab-d8-fans -v 0.0.1 -k 7.0.0-31-generic
```

Once the module is registered for every installed kernel, later upgrades do rebuild it
automatically — the hook works, it just had nothing to act on the first time.

### Verify before you trust it

`dkms status` showing one kernel is the tell. Compare it against what is installed:

```bash
ls /lib/modules | sort
dkms status
```

Any kernel in the first list that is missing from the second will boot without your
module.

## After Kernel Updates

When Ubuntu installs a new kernel, DKMS should automatically rebuild the `zettlab_d8-fans` module for the new kernel. If it doesn't (you may see `Exec format error` or fan services failing), rebuild manually:

### Recommended One-Time Setup

Ensure the generic kernel headers package is installed so DKMS can always build:

```bash
sudo apt install linux-headers-generic
```

### Manual Rebuild (if DKMS didn't auto-rebuild)

No reboot required — build for the new kernel by name:

```bash
NEWVER=$(ls /lib/modules | sort -V | tail -1)   # e.g. 7.0.0-43-generic
sudo dkms remove  -m zettlab-d8-fans -v 0.0.1 --all
sudo dkms build   -m zettlab-d8-fans -v 0.0.1 -k "$NEWVER" --force
sudo dkms install -m zettlab-d8-fans -v 0.0.1 -k "$NEWVER" --force
```

`modprobe` and the service restarts only apply once you are actually running that
kernel — after a reboot they happen on their own via `modules-load.d`.

Verify the module is loaded:

```bash
lsmod | grep zettlab_d8_fans
for d in /sys/class/hwmon/hwmon*; do
    [ -f "$d/name" ] && echo "$d: $(cat "$d/name")"
done
```

If you built for a kernel you have not booted into yet, read the vermagic straight out
of the built object — it must name the target kernel, not the running one:

```bash
zstd -dc /lib/modules/"$NEWVER"/updates/dkms/zettlab_d8_fans.ko.zst > /tmp/f.ko
modinfo /tmp/f.ko | grep -E '^(vermagic|signer)'
```

### Why This Happens

`Exec format error` (and, on some builds, `disagrees about version of symbol`) means the
compiled module was built against a different kernel than the one booting. The cause is
not DKMS — it is the module's own Makefile: upstream pins the kernel tree to the
**running** kernel.

```make
KDIR := /lib/modules/$(shell uname -r)/build
```

`dkms.conf` sets `MAKE[0]="make"`, so DKMS runs that Makefile verbatim and the `-k
<target>` it was given never reaches the build. Whatever kernel is running at build time
is what the module is compiled for, and `dkms status` still prints `installed` — so a
build for a kernel you have not booted yet looks perfectly healthy and then fails at boot.

Fix it once in `/usr/src/zettlab-d8-fans-0.0.1/Makefile` and DKMS can then build for any
installed kernel, before rebooting:

```make
KREL := $(if $(KERNELRELEASE),$(KERNELRELEASE),$(shell uname -r))
KDIR := /lib/modules/$(KREL)/build
```

DKMS exports `KERNELRELEASE` for the target kernel; `uname -r` stays only as the fallback
for a hand-run `make` in the running tree. After editing, re-run the build/install above
with `-k "$NEWVER" --force` and check the vermagic.

For contrast, the `zettlab_gpio_keys` module builds for the not-yet-booted kernel without
any fix: its Makefile uses `KDIR ?=` and its `dkms.conf` has no `MAKE[0]` line, so DKMS's
own `make -C /lib/modules/<target>/build` invocation wins. The two modules failing and
succeeding differently on the same kernel bump is the tell that a module's Makefile, not
DKMS, is at fault.

### If You Must Fix Before Rebooting

If `apt upgrade` leaves packages broken and you can't reboot yet, the old kernel headers may be incomplete (missing `autoconf.h`). Fix with:

```bash
sudo apt install -y flex bison libelf-dev
cd /usr/src/linux-headers-<old-version>  # e.g., 7.0.0-22-generic
sudo make syncconfig
cd ~
sudo dkms build -m zettlab-d8-fans -v 0.0.1
sudo dkms install -m zettlab-d8-fans -v 0.0.1
sudo apt --fix-broken install
```

This generates the missing files in the old headers so DKMS can build. Reboot into the new kernel afterwards; with the Makefile fix above a further rebuild is not needed, without it the module must be rebuilt once you are running the new kernel.

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
After=systemd-modules-load.service multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/cpu-fan-curve.sh
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
```

> **Note:** The `After=systemd-modules-load.service` ensures the `zettlab_d8_fans` module is loaded before the fan script starts. Without this, the service will fail because it cannot find the hwmon device.

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

The script automatically detects all SATA drives (`/dev/sd[a-h]`) and monitors the maximum temperature. If none are present, it holds the disk fans at `MIN_SAFE_PWM` instead of treating that as a sensor failure (which would force full speed).

### Installation

1. Copy the script to `/usr/local/sbin/hdd-fan-curve.sh`
2. Make it executable: `sudo chmod +x /usr/local/sbin/hdd-fan-curve.sh`
3. Create the systemd service:

```ini
[Unit]
Description=HDD fan control curve for Zettlab NAS
After=systemd-modules-load.service multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/sbin/hdd-fan-curve.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

> **Note:** The `After=systemd-modules-load.service` ensures the `zettlab_d8_fans` module is loaded before the fan script starts.

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

## Post-Kernel-Upgrade Checklist

After any kernel update, verify everything is working:

```bash
# 1. DKMS modules rebuilt?
sudo dkms status | grep zettlab

# 2. Modules loaded?
lsmod | grep -E 'zettlab_d8_fans|zettlab_gpio_keys'

# 3. hwmon device visible?
for d in /sys/class/hwmon/hwmon*; do [ -f "$d/name" ] && echo "$(basename $d): $(cat $d/name)"; done | grep zettlab

# 4. Fan services running?
systemctl is-active cpu-fan-curve hdd-fan-curve

# 5. Button service using evdev (not MMIO)?
journalctl -u zettlab-buttons.service --no-pager -n 5 | grep "listening on"

# If any step fails, restart the affected service:
sudo systemctl restart cpu-fan-curve hdd-fan-curve zettlab-buttons
```

If DKMS auto-rebuild failed, manually rebuild:

```bash
# For fans:
sudo dkms build -m zettlab-d8-fans -v 0.0.1
sudo dkms install -m zettlab-d8-fans -v 0.0.1
sudo modprobe zettlab_d8_fans

# For GPIO keys:
sudo dkms build -m zettlab-gpio-keys -v 1.0
sudo dkms install -m zettlab-gpio-keys -v 1.0
sudo modprobe zettlab_gpio_keys

# Then restart all services:
sudo systemctl restart cpu-fan-curve hdd-fan-curve zettlab-buttons
```

## Power Limits: Read the Meter, Not the Register

The RAPL registers and the actual behaviour disagree on this platform, and the
registers are the misleading half.

| | Stock firmware | Ubuntu 26.04 |
|---|---|---|
| PL1 `long_term` in sysfs | 45 W | **200 W** (32 s window) |
| PL2 `short_term` | 93 W | 93 W (2 ms window) |
| PL4 `peak_power` | — | 160 W |
| Chip base power | 28 W | 28 W |
| **Measured sustained draw** | — | **45 W** |

200 W on a 28 W part reads like "no cap", but it is not what the hardware does. Four
consecutive 20-second windows under an 18-thread load measured 44.9, 45.0, 45.1 and
45.0 W. Something below RAPL — platform budget or a firmware limit the sysfs interface
does not expose — holds the package at 45 W regardless.

**Capping PL1 to 45 W therefore changes nothing on this chassis.** Measure before you
tune it:

```bash
R=/sys/class/powercap/intel-rapl:0
a=$(sudo cat $R/energy_uj); sleep 20; b=$(sudo cat $R/energy_uj)
awk -v a=$a -v b=$b 'BEGIN{printf "%.1f W\n", (b-a)/20000000}'
```

Run that under load, not at idle. Idle on this board is about 5 W.

### Sustained thermals

At 45 W sustained across all threads:

```
CPU 77-79 C     fan3 pwm 121, ~3600 rpm
package_throttle_count: 0
```

Zero throttle events against a Tjmax of 110 C.

### The curve behaves differently under burst and sustained load

Worth understanding before you conclude the fan is lazy:

| Load | Peak CPU | Fan response |
|---|---|---|
| Geekbench 6 (bursty) | 85 C | pwm 85, ~2680 rpm |
| All-thread sustained | 79 C | pwm 121, ~3600 rpm |

The bursty run hit a *higher* peak with a *lower* fan speed. That is the EMA smoothing
working as designed: Geekbench swings between 44 and 85 C within tens of seconds, so the
smoothed temperature the curve acts on stays far below the spikes. Sustained load holds
the temperature steady, the smoothed value converges on it, and the fan ramps properly.

For LLM inference — the sustained case — the second row is what you get.

## Safety Notes## Safety Notes

- The curves are intentionally conservative and anti-chatter focused
- PWM values below ~60–80 can cause fan stalling
- Thermal lag is significant (30–120+ seconds)
- All scripts include hard-coded minimum safe PWM and emergency full-speed overrides
- If any temperature sensor fails, the system forces full speed (183 PWM)
- Timer-based hysteresis prevents frequent speed adjustments after any upward change