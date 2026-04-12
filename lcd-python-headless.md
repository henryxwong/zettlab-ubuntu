# LCD Dashboard – Headless Server (Python Direct DRM) for Zettlab D6/D8 Ultra

**What This Achieves**
- Keeps the **front LCD** (3.49-inch, 640×172) turned **on** at all times  
- Displays custom real-time status (CPU %, temp, fans, max HDD temp, IP, storage)  
- **Zero X11 / Wayland / GNOME** — runs directly on the Linux framebuffer (`/dev/fb0`)  
- Extremely lightweight (< 15 MB RAM, < 1 % CPU)  
- Fully headless-friendly (works even if HDMI is unplugged)  
- HDMI runs at full native resolution (1080p/4K) — **no more forced low-res mirroring**

### 2. Prerequisites
- Ubuntu Server 26.04 installed and booted  
- Fan kernel module installed and loaded (`zettlab_d8_fans`)  
- `lm-sensors` and `smartmontools` already installed  
- SSH access

### 3. Step 1: Fix HDMI Resolution (Mandatory)
The kernel must be told the correct modes for both outputs, otherwise HDMI gets forced to 640×172.

```bash
sudo nano /etc/default/grub
```

Replace the `GRUB_CMDLINE_LINUX_DEFAULT` line with:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash video=eDP-1:640x172M,HDMI-A-1:1920x1080@60M"
```

**Adjustments you may need:**
- HDMI output name: `HDMI-A-1`, `HDMI-1`, or `HDMI-2` (check later with `cat /sys/class/drm/card*-HDMI*/status`)
- Resolution: `1920x1080@60M` (1080p) or `3840x2160@60M` (4K)

Save & exit, then apply:

```bash
sudo update-grub
sudo reboot
```

After reboot, SSH back in and verify:
```bash
cat /sys/class/drm/card*-HDMI*/status   # should say "connected"
cat /sys/class/drm/card*-eDP-1/status    # should say "connected"
```

### 4. Step 2: Install Required Packages
```bash
sudo apt update
sudo apt install python3-pil python3-psutil smartmontools -y
```

### 5. Step 3: Identify the Correct Framebuffer
```bash
ls /dev/fb*
cat /sys/class/drm/card1-eDP-1/status
```

Most Zettlab units use `/dev/fb0`. If yours is different, change `FB_DEV` in the script below.

### 6. Step 4: Create the Python Dashboard Script
```bash
sudo nano /usr/local/bin/zettlab-lcd-dashboard.py
```

Paste the complete script:

```python
#!/usr/bin/env python3
import time
import subprocess
import psutil
from PIL import Image, ImageDraw, ImageFont

# ================== CONFIG ==================
FB_DEV = "/dev/fb0"          # ← Change to /dev/fb1 if needed
WIDTH, HEIGHT = 640, 172
UPDATE_INTERVAL = 2

# Change this to your actual storage mountpoint
# Common options: "/tank", "/mnt/tank", "/data", "/" (root), or wherever you mounted your big drives
STORAGE_PATH = "/tank"
# ===========================================

def get_sensor(path):
    try:
        return int(open(path).read().strip())
    except:
        return 0

def get_max_hdd_temp():
    try:
        # Works with the most common SMART attributes (194 or 190)
        output = subprocess.check_output(
            "smartctl -A /dev/sda 2>/dev/null | awk '/194/ || /190/ {print $10; exit}' || echo 0",
            shell=True, text=True
        ).strip()
        return int(output) if output.isdigit() else 0
    except:
        return 0

def render():
    img = Image.new("RGB", (WIDTH, HEIGHT), (0, 0, 0))
    draw = ImageDraw.Draw(img)
    font = ImageFont.load_default()

    # Gather data
    cpu_percent = psutil.cpu_percent(interval=None)
    cpu_temp = get_sensor("/sys/class/hwmon/hwmon7/temp1_input") // 1000
    cpu_fan = get_sensor("/sys/class/hwmon/hwmon8/fan3_input")
    fan1 = get_sensor("/sys/class/hwmon/hwmon8/fan1_input")
    fan2 = get_sensor("/sys/class/hwmon/hwmon8/fan2_input")
    hdd_temp = get_max_hdd_temp()
    
    # Fixed IP extraction (no more SyntaxWarning)
    ip = subprocess.getoutput(
        r"ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1"
    ) or "No IP"

    # Storage with safe fallback
    try:
        storage = psutil.disk_usage(STORAGE_PATH)
        storage_free_gb = storage.free // (1024**3)
        storage_str = f"{storage_free_gb} GB free"
    except FileNotFoundError:
        storage_str = "N/A (check STORAGE_PATH)"

    # Draw text on LCD
    y = 8
    draw.text((10, y), "ZETTLAB D6/D8 ULTRA", fill=(0, 255, 255))
    y += 18
    draw.text((10, y), f"CPU: {cpu_percent:5.1f}%   {cpu_temp}°C   Fan: {cpu_fan} RPM", fill=(255, 255, 255))
    y += 15
    draw.text((10, y), f"Disk Fans: {fan1:4}/{fan2:4} RPM    Max HDD: {hdd_temp}°C", fill=(255, 255, 255))
    y += 15
    draw.text((10, y), f"IP: {ip}     Storage: {storage_str}", fill=(200, 200, 200))

    # Write to framebuffer
    with open(FB_DEV, "wb") as f:
        f.write(img.tobytes())

if __name__ == "__main__":
    print("Zettlab LCD Dashboard started (Direct DRM)")
    while True:
        render()
        time.sleep(UPDATE_INTERVAL)
```

Make the script executable:
```bash
sudo chmod +x /usr/local/bin/zettlab-lcd-dashboard.py
```

### 7. Step 5: Create the Systemd Service
```bash
sudo nano /etc/systemd/system/zettlab-lcd.service
```

Paste:

```ini
[Unit]
Description=Zettlab Front LCD Dashboard (Direct DRM / Python)
After=multi-user.target

[Service]
Type=simple
ExecStart=/usr/local/bin/zettlab-lcd-dashboard.py
Restart=always
RestartSec=3
Nice=19
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### 8. Step 6: Activate the Service
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now zettlab-lcd.service
```

Check status:
```bash
systemctl status zettlab-lcd.service
journalctl -u zettlab-lcd.service -f
```

### 9. Management Commands
```bash
sudo systemctl restart zettlab-lcd.service     # restart dashboard
sudo systemctl stop zettlab-lcd.service        # temporary stop
journalctl -u zettlab-lcd.service -f           # live logs
```

### 10. Troubleshooting
- LCD stays black → Check `FB_DEV` and reboot once
- Wrong HDMI resolution → Double-check the `video=` line in GRUB
- No sensor data → Confirm `lsmod | grep zettlab_d8_fans` and `sensors`
- Storage shows “N/A” → Edit `STORAGE_PATH` in the Python script and restart the service

This is the **recommended** LCD solution for Ubuntu Server installations — clean, stable, and truly headless.