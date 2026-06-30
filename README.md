# Zettlab D6/D8 Ultra – Ubuntu 26.04 Guide

> Community-driven documentation for running Ubuntu 26.04 on Zettlab D6/D8 Ultra NAS devices.

## Overview

This guide provides step-by-step instructions for installing and configuring Ubuntu 26.04 on Zettlab D6/D8 Ultra NAS devices. It covers everything from initial installation to advanced storage pool configuration and data protection.

**⚠ Disclaimer:** All information is provided as-is. Test thoroughly before applying to production systems. Always backup data before making system changes.

## Credits & Acknowledgements

- **Community Testing & Feedback**: Speedster and Daisan on the Zettlab Discord
- **Fan Control Kernel Module** (`zettlab-d8-fans`): Developed by [haveacry](https://github.com/haveacry) — [zettlab-d8-fans](https://github.com/haveacry/zettlab-d8-fans). The module is provided without an explicit license and is used here with attribution.

---

## Hardware Specifications

This table reflects the **Zettlab D6 Ultra** and **D8 Ultra** models (tested on Ubuntu 26.04).

| Component     | D6 Ultra                          | D8 Ultra                          | Notes |
|---------------|-----------------------------------|-----------------------------------|-------|
| **CPU**       | Intel Core Ultra 5 125H           | Intel Core Ultra 5 125H           | PL1/PL2 locked to 45 W / 93 W |
| **Bays**      | 6× 3.5" HDD bays                  | 8× 3.5" HDD bays                  | Hot-swappable |
| **Front LCD** | 3.49-inch, 640×172 (`eDP-1`)      | 3.49-inch, 640×172 (`eDP-1`)      | Disabled during boot with `video=eDP-1:d` |
| **Audio**     | Intel Meteor Lake iGPU DSP        | Intel Meteor Lake iGPU DSP        | Fixed with `snd_intel_dspcfg.dsp_driver=1` |
| **Fans**      | 3× PWM fans                       | 3× PWM fans                       | Controlled via `zettlab_d8_fans` DKMS module (0–183 range) |
| **Networking**| 2× 10GbE (Realtek RTL8127)        | 2× 10GbE (Realtek RTL8127)        | Onboard NIC unstable — using USB-C Ethernet adapter instead |
| **RGB/LED**   | USB-controlled                    | USB-controlled                    | See [RGB/LED Control](rgb-led-control.md) — protocol via `/dev/ttyACM0` |

---

## Table of Contents

| Guide | Description |
|-------|-------------|
| [Ubuntu Installation](ubuntu-installation.md) | Installing Ubuntu 26.04 Server |
| [Kernel Parameters](kernel-parameters.md) | Centralized list of all recommended kernel parameters |
| [Network Driver](networking-r8127.md) | Realtek r8127 status (now using USB Ethernet adapter) |
| [Fan Control](hardware-fan-control.md) | Dynamic temperature-based fan control |
| [BIOS Graphics Configuration](graphics-BIOS.md) | Intel Arc iGPU BIOS settings for AI workloads |
| [Graphics Driver](graphics-iGPU.md) | Intel Arc iGPU compute/media stack |
| [LLM Inference](llm-inference.md) | Vulkan & SYCL setup for local LLMs (llama.cpp) |
| [Audio Configuration](audio-HDA-driver.md) | Fixing "Dummy Output" issue |
| [Storage Pool](storage-mergerfs-snapraid.md) | mergerfs + SnapRAID configuration |
| [Btrfs Data Replication](btrfs-data-replication.md) | Dedicated `/data` subvolume + btrbk snapshot replication to parity disk |
| [RGB/LED Control](rgb-led-control.md) | USB RGB controller protocol (`/dev/ttyACM0`, VID:0x5759 PID:0x4358) |
| [Samba Shares](samba-shares.md) | Home + /data + mergerfs pool Samba shares |

---

## Prerequisites

- HDMI display and USB keyboard
- USB flash drive (≥ 8 GB)
- Ubuntu Server 26.04 ISO
- Recommended: Secondary NVMe SSD (preserves original ZettOS)

---

## Quick Reference

### Required Kernel Parameters

All kernel parameters are now documented in one place:

→ **[Kernel Parameters Reference](kernel-parameters.md)**

### DKMS Modules

| Module | Purpose |
|--------|---------|
| `zettlab-d8-fans` | Fan control |