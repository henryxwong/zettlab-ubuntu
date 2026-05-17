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

| Component | Details |
|-----------|---------|
| CPU | Intel Core Ultra 5 125H (PL1/PL2 locked to **45 W / 93 W**) |
| Front LCD | 3.49-inch, 640×172 resolution (`eDP-1`) |
| Audio | Intel Meteor Lake iGPU audio DSP |
| Fans | 3× PWM fans via `zettlab_d8_fans` module (0–183 range) |
| Networking | Dual 10GbE (Realtek RTL8127: `enp88s0` + `enp89s0`) — **abandoned**, using USB-C Ethernet instead |
| RGB/LED | USB device detected; no driver available |

---

## Table of Contents

| Guide | Description |
|-------|-------------|
| [Ubuntu Installation](ubuntu-installation.md) | Installing Ubuntu 26.04 Server |
| [Kernel Parameters](kernel-parameters.md) | Centralized list of all recommended kernel parameters |
| [Network Driver](networking-r8127.md) | Realtek r8127 status (now using USB Ethernet adapter) |
| [Fan Control](hardware-fan-control.md) | Dynamic temperature-based fan control |
| [Graphics Driver](graphics-iGPU.md) | Intel Arc iGPU compute/media stack |
| [Audio Configuration](audio-HDA-driver.md) | Fixing "Dummy Output" issue |
| [Storage Pool](storage-mergerfs-snapraid.md) | mergerfs + SnapRAID configuration |
| [Btrfs Data Replication](btrfs-data-replication.md) | Dedicated `/data` subvolume + btrbk snapshot replication to parity disk |
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