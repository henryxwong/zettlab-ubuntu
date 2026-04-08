# LCD Dashboard – Minimal Desktop (Conky) for Zettlab D6/D8 Ultra

**What This Achieves**
- Keeps the **front LCD** (3.49-inch, 640×172) turned **on** at all times
- HDMI output runs at **full native resolution** (1080p, 4K, etc.) — no more forced low-res mirroring
- A lightweight **systemd service** automatically takes over **only the LCD** and shows custom real-time information (CPU temp/fan speeds, HDD temps, RAM/CPU usage, IP address, storage, etc.)
- The main HDMI desktop remains completely clean and unaffected

This is done **entirely after** you have finished the original Ubuntu 26.04 installation guide.  
**99 % of the work can be done via SSH** — you only need an HDMI monitor plugged in for one final verification reboot.

**Recommended only if you want a minimal desktop environment.**  
For pure headless Ubuntu Server, use the **[Python Direct DRM version](lcd-python-headless.md)** instead — it is lighter and requires no X11/GNOME.

## Prerequisites
- Ubuntu **Desktop Minimal** (or full Desktop) 26.04 installed and booted
- Fan kernel module already installed and working (`zettlab_d8_fans` loaded)
- `lm-sensors` and `smartmontools` installed
- You know your HDMI output name (usually `HDMI-A-1` or `HDMI-1`) and preferred resolution
- You are logged in to the graphical desktop at least once so that `DISPLAY=:0` exists

## Step-by-Step (SSH-Friendly)

### Step 1: Fix HDMI Resolution While Keeping LCD On
```bash
sudo nano /etc/default/grub
```

Find the line starting with `GRUB_CMDLINE_LINUX_DEFAULT=`

**Replace** it with the following (adjust HDMI part to your monitor):
```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash video=eDP-1:640x172M,HDMI-A-1:1920x1080@60M"
```
- Common HDMI names: `HDMI-A-1`, `HDMI-1`, `HDMI-2`
- Common resolutions: `1920x1080@60M` (1080p) or `3840x2160@60M` (4K)

Save & exit (Ctrl+O → Enter → Ctrl+X).

Apply the change:
```bash
sudo update-grub
```

### Step 2: Reboot (First Time LCD + Full HDMI)
```bash
sudo reboot
```

**Important:** Plug in an HDMI monitor (or keep it plugged in) before rebooting so you can verify the result.

After reboot:
- HDMI should now be at full resolution
- Front LCD should be on (showing the normal Ubuntu desktop sliver for now)

SSH back in.

### Step 3: Install Conky
```bash
sudo apt install conky-all -y
```

### Step 4: Fix SMARTCTL Permissions (for HDD temperature)
```bash
sudo usermod -aG disk $USER
```
**Reboot once** after this command so the group change takes effect.

### Step 5: Create the LCD-Only Conky Config
```bash
mkdir -p ~/.config/conky
nano ~/.config/conky/zettlab-lcd.conf
```

Paste this ready-to-use config (tuned for 640×172):

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

### Step 6: Create the Systemd Service
```bash
sudo nano /etc/systemd/system/zettlab-lcd.service
```

Paste:

```ini
[Unit]
Description=Zettlab Front LCD Custom Status Display
After=multi-user.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=yourusername          # ← CHANGE TO YOUR ACTUAL USERNAME
Environment="DISPLAY=:0"
ExecStart=/usr/bin/conky -c /home/yourusername/.config/conky/zettlab-lcd.conf --display=:0
Restart=always
RestartSec=3
Nice=19

[Install]
WantedBy=multi-user.target
```

Replace `yourusername` in both places with your actual login name.

### Step 7: Activate the Service
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now zettlab-lcd.service
```

Check it is running:
```bash
systemctl status zettlab-lcd.service
```

### Step 8: Final Verification
- Look at the physical front LCD — Conky should now be displayed on it.
- HDMI monitor should still be at full resolution.
- You can now unplug the HDMI monitor permanently if you wish.

## Quick Management Commands (via SSH anytime)
```bash
# Restart dashboard
sudo systemctl restart zettlab-lcd.service

# View live logs
journalctl -u zettlab-lcd.service -f

# Stop temporarily
sudo systemctl stop zettlab-lcd.service
```

## Troubleshooting
- Conky not appearing on LCD → `xrandr --output eDP-1 --mode 640x172` then restart service
- Permission error on `smartctl` → Ensure you ran `usermod -aG disk $USER` and rebooted
- Using Wayland instead of Xorg → Log out and choose **Ubuntu on Xorg** at the login screen
- Wrong HDMI output name → Run `xrandr | grep connected` while HDMI is plugged in

This setup uses almost zero CPU, survives reboots, and gives you a clean, always-on status panel just like (or better than) ZettOS.

**Note:** If you later switch to pure headless Server, switch to the Python Direct DRM dashboard instead.