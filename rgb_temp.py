#!/usr/bin/env python3
"""CPU temperature -> RGB LED control via rgb_control.py.

Reads CPU die temperature from Netdata (24h + 30d).
Combines both windows for accurate min/max range:
  - min = min(24h_min, 30d_min) — never miss cool temps
  - max = max(24h_max, 30d_max) — capture peaks even if smoothed
Maps current temp to a blue-to-red color gradient with intensity scaling.
"""

import os
os.environ["PYTHONUNBUFFERED"] = "1"

import argparse
import json
import os
import subprocess
import sys
import time


NETDATA_URL = "http://localhost:19999"
CPU_TEMP_CHART = (
    "sensors.temperature_coretemp-isa-0000_temp1_Package_id_0_input"
)
HWMON_PATH = "/sys/class/hwmon/hwmon6/temp1_input"
RGB_CONTROL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "rgb_control.py")


def netdata_query(chart_id: str, before: int = -2592000, after: int = 0):
    """Fetch temperature data from Netdata API.

    Returns (min_val, max_val, latest_val) or (None, None, None) on failure.
    """
    try:
        result = subprocess.run(
            ["curl", "-s", f"{NETDATA_URL}/api/v1/data?chart={chart_id}&before={before}&after={after}"],
            capture_output=True, text=True, timeout=30
        )
        data = json.loads(result.stdout)
    except Exception:
        return None, None, None

    points = data.get("data", [])
    vals = []
    for point in points:
        if isinstance(point, list) and len(point) > 1 and point[1] is not None:
            try:
                vals.append(float(point[1]))
            except (ValueError, TypeError):
                continue

    if not vals:
        return None, None, None

    latest = vals[-1]
    min_val = min(vals)
    max_val = max(vals)
    return min_val, max_val, latest


def read_hwmon():
    """Read CPU package temperature from hwmon sensor (unsmoothed, live).

    Returns temperature in °C or None on failure.
    """
    try:
        with open(HWMON_PATH) as f:
            return int(f.read().strip()) / 1000.0
    except Exception:
        return None


def get_temp_range():
    """Get min/max temp range from 24h + 30d Netdata windows.

    Strategy:
      - min = min(24h_min, 30d_min) — never miss cool temps
      - max = max(24h_max, 30d_max) — capture peaks even if smoothed

    Returns (min_temp, max_temp) or (None, None) on failure.
    """
    nd_24h_min, nd_24h_max, _ = netdata_query(CPU_TEMP_CHART, before=-86400)
    nd_30d_min, nd_30d_max, _ = netdata_query(CPU_TEMP_CHART, before=-2592000)

    if nd_24h_min is None and nd_30d_min is None:
        return None, None

    min_temp = nd_24h_min if nd_30d_min is None else (nd_24h_min if nd_24h_min < nd_30d_min else nd_30d_min)
    max_temp = nd_24h_max if nd_30d_max is None else (nd_24h_max if nd_24h_max > nd_30d_max else nd_30d_max)

    return min_temp, max_temp


def compute_color(temp: float, min_temp: float, max_temp: float):
    """Compute RGB values from temperature.

    Color gradient: blue (cool) -> red (hot).
    Brightness: cool = dim, hot = 25%.

    Returns (r, g, b) tuple with values 0-255.
    """
    if max_temp == min_temp:
        return 0, 0, 1

    t = (temp - min_temp) / (max_temp - min_temp)
    t = max(0.0, min(1.0, t))

    # Color: blue (t=0) -> red (t=1)
    r = int(t * 255)
    g = 0
    b = int((1 - t) * 255)

    # Brightness: scales with temperature, max 25%
    # t=0 -> 10% * 0.25 = 2.5%, t=1 -> 100% * 0.25 = 25%
    brightness = (0.1 + t * 0.9) * 0.25

    r = int(r * brightness)
    b = int(b * brightness)

    return r, g, b


def set_rgb(r: int, g: int, b: int, mode: int = 6, speed: int = 5):
    """Call rgb_control.py to set the LED color."""
    try:
        result = subprocess.run(
            ["python3", RGB_CONTROL, str(mode), str(r), str(g), str(b),
             str(r), str(g), str(b), str(speed)],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode != 0:
            print(f"rgb_control.py error: {result.stderr.strip()}", file=sys.stderr)
            return False
        return True
    except FileNotFoundError:
        print(f"ERROR: rgb_control.py not found at {RGB_CONTROL}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"ERROR calling rgb_control.py: {e}", file=sys.stderr)
        return False


def main():
    parser = argparse.ArgumentParser(description="CPU temp -> RGB LED controller")
    parser.add_argument("--once", action="store_true", help="Read once and exit")
    args = parser.parse_args()

    interval = 20
    range_update_interval = 3600  # refresh min/max every 1 hour

    print(f"rgb_temp: CPU temp -> RGB LED controller")
    print(f"  Temp interval: {interval}s, Range refresh: every {range_update_interval//60}min")
    print(f"  Mode: solid (6), Color: blue(cool) -> red(hot)")
    print(f"  Range: hybrid 24h+30d Netdata (min of mins, max of maxs)")
    print(f"  Brightness: 2.5% (cool) -> 25% (hot)")
    print()

    last_range_update = time.time() - range_update_interval  # force initial read
    prev_color = None

    while True:
        now = time.time()

        # Update min/max range every hour or on first run
        if now - last_range_update >= range_update_interval:
            min_temp, max_temp = get_temp_range()
            last_range_update = now
            if min_temp is None or max_temp is None:
                print(f"[{time.strftime('%H:%M:%S')}] Netdata unavailable, skipping", file=sys.stderr)
                time.sleep(interval)
                continue

        current = read_hwmon()
        if current is None:
            print(f"[{time.strftime('%H:%M:%S')}] hwmon unavailable, skipping", file=sys.stderr)
            time.sleep(interval)
            continue

        r, g, b = compute_color(current, min_temp, max_temp)
        t = (current - min_temp) / (max_temp - min_temp) if max_temp != min_temp else 0

        # Only send to LED if color changed
        new_color = (r, g, b)
        if new_color != prev_color:
            ok = set_rgb(r, g, b, mode=6, speed=5)
            status = "OK" if ok else "FAILED"
            print(f"[{time.strftime('%H:%M:%S')}] [{status}] temp={current:.1f}C "
                  f"range=[{min_temp:.1f}, {max_temp:.1f}]C t={t:.2f} "
                  f"color=({r},{g},{b})")
            prev_color = new_color

        if args.once:
            break

        time.sleep(interval)


if __name__ == "__main__":
    main()
