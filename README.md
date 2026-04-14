# Zettlab D6/D8 Ultra – Ubuntu 26.04 Guide

**Disclaimer**  
This is a **community-driven total rewrite** of the original guides. All information is still in **draft status** and has **not been fully verified** across every hardware revision or firmware version. Use at your own risk. Always perform a complete backup of the original ZettOS installation before proceeding.

**Acknowledgement**  
This guide was made possible with detailed information and testing shared by **Speedster** and **Daisan** on the Zettlab Discord.

## Hardware Specifications
- **CPU**: Intel Core Ultra 5 125H (PL1/PL2 hard-locked to **45 W / 93 W** in the BIOS — cannot be changed even after installing Ubuntu)
- **Front LCD**: 3.49-inch, 640×172 resolution, connected as `eDP-1`
- **Fans**: Controlled via community kernel module `zettlab_d8_fans` (PWM values strictly 0–183)
- **Fan mapping**:
  - `fan1`: rear disk fan 1
  - `fan2`: rear disk fan 2
  - `fan3`: CPU fan
- **Networking**: RTL8127 NICs (works out-of-the-box)
- **RGB / LED strip**: Detected as USB device (`lsusb`) but no driver available

## Table of Contents

- **[Installation Guide](ubuntu-installation.md)**
- **[Fan Control Guide](fan-control.md)**
- **[Intel Arc iGPU Drivers](intel-igpu.md)**
- **[Storage Pool – mergerfs + SnapRAID](mergefs-snapraid.md)**

**Recommended Workflow**
1. Start with **[Installation Guide](ubuntu-installation.md)**.
2. Immediately follow **[Fan Control Guide](fan-control.md)**.
3. Set up the iGPU with **[Intel Arc iGPU Drivers](intel-igpu.md)**
4. Set up your storage pool with **[Storage Pool – mergerfs + SnapRAID](mergefs-snapraid.md)**.