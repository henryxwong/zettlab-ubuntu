# Zettlab D6/D8 Ultra – Ubuntu 26.04 Guide

> Community-driven documentation for running Ubuntu 26.04 on Zettlab D6/D8 Ultra NAS devices.

## Overview

This guide provides step-by-step instructions for installing and configuring Ubuntu 26.04 on Zettlab D6/D8 Ultra NAS devices. It covers everything from initial installation to advanced storage pool configuration.

**⚠ Disclaimer:** All information is provided as-is. Test thoroughly before applying to production systems. Always backup data before making system changes.

**Acknowledgement:** This guide was made possible with testing and feedback from Speedster and Daisan on the Zettlab Discord.

---

## Hardware Specifications

| Component | Details |
|-----------|---------|
| CPU | Intel Core Ultra 5 125H (PL1/PL2 locked to **45 W / 93 W**) |
| Front LCD | 3.49-inch, 640×172 resolution (`eDP-1`) |
| Audio | Intel Meteor Lake iGPU audio DSP |
| Fans | 3× PWM fans via `zettlab_d8_fans` module (0–183 range) |
| Networking | Dual 10GbE (Realtek RTL8127: `enp88s0` + `enp89s0`) |
| RGB/LED | USB device detected; no driver available |

---

## Table of Contents

| Guide | Description |
|-------|-------------|
| [Ubuntu Installation](ubuntu-installation.md) | Installing Ubuntu 26.04 Server |
| [Network Driver](networking-r8127.md) | Realtek r8127 DKMS driver setup |
| [Fan Control](hardware-fan-control.md) | Dynamic temperature-based fan control |
| [Graphics Driver](graphics-iGPU.md) | Intel Arc iGPU compute/media stack |
| [Audio Configuration](audio-HDA-driver.md) | Fixing "Dummy Output" issue |
| [Storage Pool](storage-mergerfs-snapraid.md) | mergerfs + SnapRAID configuration |

---

## Prerequisites

- HDMI display and USB keyboard
- USB flash drive (≥ 8 GB)
- Ubuntu Server 26.04 ISO
- Recommended: Secondary NVMe SSD (preserves original ZettOS)

---

## Quick Reference

### Required Kernel Parameters

| Purpose | Parameter |
|---------|-----------|
| Front LCD (live boot) | `video=eDP-1:d` |
| Audio HDA driver | `snd_intel_dspcfg.dsp_driver=1` |

### DKMS Modules

| Module | Purpose |
|--------|---------|
| `zettlab-d8-fans` | Fan control |
| `r8127` | Network driver |