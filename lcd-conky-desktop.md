# LCD Dashboard – Minimal Desktop (Conky) for Zettlab D6/D8 Ultra

**What This Achieves**
- Keeps the **front LCD** (3.49-inch, 640×172) turned **on** at all times with a clean real-time dashboard
- HDMI output runs at **full native resolution** (1080p or 4K) — completely unaffected
- Uses a dedicated low-privilege user (`nasuser`) with auto-login so the dashboard starts immediately after boot
- Your personal account stays fully password-protected
- Uses GNOME autostart + wrapper script

## Prerequisites
- Ubuntu **Desktop Minimal** 26.04 installed and booted
- Fan kernel module already installed and working (`zettlab_d8_fans`)
- `lm-sensors` and `smartmontools` installed
- You know your HDMI output name (usually `HDMI-A-1`)

## Step-by-Step

### Step 1: Create Dedicated Dashboard User (`nasuser`)
```bash
sudo adduser --disabled-password --gecos "NAS User" nasuser
sudo usermod -aG video,disk nasuser
```

### Step 2: Fix HDMI Resolution (HDMI-only)
```bash
sudo nano /etc/default/grub
```

Set the line to:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash video=HDMI-A-1:1920x1080@60M"
```

- Change `HDMI-A-1` if needed (check with `xrandr` later)
- Change to `3840x2160@60M` for 4K

Apply:
```bash
sudo update-grub
```

### Step 3: Install Conky
```bash
sudo apt install conky-all -y
```

### Step 4: Create the LCD-Only Conky Config
```bash
sudo -u nasuser mkdir -p /home/nasuser/.config/conky
sudo -u nasuser nano /home/nasuser/.config/conky/zettlab-lcd.conf
```

Paste this config:

```lua
conky.config = {
    alignment = 'top_left',
    background = true,
    border_width = 1,
    cpu_avg_samples = 2,
    default_color = 'white',
    double_buffer = true,
    draw_outline = false,
    draw_shades = false,
    font = 'DejaVu Sans Mono:size=8',
    gap_x = 0,
    gap_y = 0,
    minimum_height = 172,
    minimum_width = 640,
    own_window = true,
    own_window_type = 'desktop',
    own_window_transparent = true,
    own_window_argb_visual = true,
    own_window_hints = 'undecorated,below,sticky,skip_taskbar,skip_pager',
    update_interval = 2,
    use_xft = true,
    xftalpha = 0.9,
    xinerama_head = 0,   -- Force Conky to the primary monitor (LCD)
}

conky.text = [[
${alignc}${color lightblue}ZETTLAB D6/D8 ULTRA${color}
${hr}
CPU: ${cpu}%   ${freq_g} GHz   Temp: ${exec cat /sys/class/hwmon/hwmon7/temp1_input | awk '{print $1/1000}' }°C
CPU Fan: ${exec cat /sys/class/hwmon/hwmon8/fan3_input} RPM
Disk Fans: ${exec cat /sys/class/hwmon/hwmon8/fan1_input}/${exec cat /sys/class/hwmon/hwmon8/fan2_input} RPM
${hr}
Max HDD Temp: ${exec sudo smartctl -A /dev/sda 2>/dev/null | awk '/194/ {print $10 "°C"; exit}' || echo "N/A"} 
RAM: ${memperc}%   Swap: ${swapperc}%
${hr}
IP: ${exec ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1}
Storage (/tank): ${fs_free /tank} free of ${fs_size /tank}
]]
```

Save & exit.

### Step 5: Create the LCD Startup Wrapper Script
```bash
sudo -u nasuser nano /home/nasuser/.config/lcd-startup.sh
```

Paste this:

```bash
#!/bin/bash
sleep 10
# Make LCD primary so Conky stays on it
xrandr --output eDP-1 --mode 640x172 --primary --right-of HDMI-A-1
# Start Conky on the LCD
conky -c /home/nasuser/.config/conky/zettlab-lcd.conf --display=:0 &
```

Save & exit, then make executable:
```bash
sudo -u nasuser chmod +x /home/nasuser/.config/lcd-startup.sh
```

### Step 6: Create GNOME Autostart Entry
```bash
sudo -u nasuser nano /home/nasuser/.config/autostart/zettlab-lcd.desktop
```

Paste this:

```ini
[Desktop Entry]
Type=Application
Name=Zettlab LCD Dashboard
Exec=/home/nasuser/.config/lcd-startup.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
```

Save & exit.

### Step 7: Force Xorg Session (required for xrandr)
```bash
sudo nano /etc/gdm3/custom.conf
```

Set the `[daemon]` section to:

```ini
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=nasuser
WaylandEnable=false
```

Save & exit.

### Step 8: Activate Everything
```bash
sudo systemctl restart gdm3
```

Reboot once:
```bash
sudo reboot
```

### Quick Management Commands
```bash
# Restart dashboard manually (after login as nasuser)
sudo -u nasuser /home/nasuser/.config/lcd-startup.sh

# Check if Conky is running
ps -u nasuser | grep conky

# Emergency LCD fix (run as nasuser)
xrandr --output eDP-1 --mode 640x172 --primary --right-of HDMI-A-1
```

## Troubleshooting
- LCD still blank or wrong size → Run `xrandr --output eDP-1 --mode 640x172 --primary --right-of HDMI-A-1` as `nasuser`
- Conky appears on HDMI instead → Check that `xinerama_head = 0` is in the Conky config and `--primary` is used in the wrapper
- No HDD temperature → `sudo usermod -aG disk nasuser` and reboot
- Wrong HDMI name → Run `xrandr | grep connected` after login
- Session still on Wayland → Double-check `WaylandEnable=false` and reboot

This is the **stable, community-tested** setup for the Zettlab D6/D8 Ultra after all kernel-level workarounds failed. HDMI stays perfect, the LCD shows the dashboard immediately after boot, and your personal account remains secure.