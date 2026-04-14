# Zettlab D6/D8 Ultra – Ubuntu 26.04 Guide

**Disclaimer**  
This is a community-driven total rewrite of the original guides. All information is still in draft status and has not been fully verified across every hardware revision or firmware version. Use at your own risk. Always perform a complete backup of the original ZettOS installation before proceeding.

**Acknowledgement**  
This guide was made possible with detailed information and testing shared by Speedster and Daisan on the Zettlab Discord.

## Hardware Specifications

| Component | Details |
|-----------|---------|
| **CPU** | Intel Core Ultra 5 125H (PL1/PL2 hard-locked to **45 W / 93 W** in the BIOS) |
| **Front LCD** | 3.49-inch, 640×172 resolution, connected as `eDP-1` |
| **Audio** | Intel Meteor Lake integrated audio DSP (requires kernel parameter `snd_intel_dspcfg.dsp_driver=1` for stable HDA driver) |
| **Fans** | Controlled via community kernel module `zettlab_d8_fans` (PWM values 0–183) |
| **Fan Mapping** | `fan1`: rear disk fan 1, `fan2`: rear disk fan 2, `fan3`: CPU fan |
| **Networking** | Dual 10GbE LAN Ports (Realtek RTL8127 chipset: `enp88s0` + `enp89s0`) |
| **RGB / LED strip** | Detected as USB device but no driver available |

## Table of Contents

| Guide | Description |
|-------|-------------|
| [Installation](ubuntu-installation.md) | Ubuntu 26.04 Server installation procedure |
| [Network Driver](networking-r8127.md) | Realtek r8127 DKMS driver installation |
| [Fan Control](hardware-fan-control.md) | Dynamic fan control via `zettlab_d8_fans` module |
| [Graphics](graphics-iGPU.md) | Intel Arc iGPU driver installation |
| [Audio](audio-HDA-driver.md) | Fixing "Dummy Output" via HDA driver configuration |
| [Storage](storage-mergerfs-snapraid.md) | mergerfs + SnapRAID pool setup |

## Prerequisites

- HDMI display and USB keyboard (needed for BIOS and first boot)
- USB flash drive ≥ 8 GB
- Ubuntu Server 26.04 ISO
- Recommended: Secondary NVMe SSD for Ubuntu installation (keeps ZettOS intact)