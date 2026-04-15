# Intel Arc iGPU Driver Installation

> Installs the Intel Graphics compute and media stack for integrated Arc Graphics (Meteor Lake iGPU) on Intel Core Ultra 5 125H.

## Overview

This guide enables:
- Hardware video decoding/encoding (VA-API / Quick Sync)
- OpenCL and oneAPI Level Zero compute runtime
- Full access to `/dev/dri/renderD*` device nodes
- Proper support for the front LCD (`eDP-1`)

> **Note**: Some advanced packages (intel-gsc, intel-metrics-discovery, libmfx-gen1) are not yet available in Ubuntu 26.04 official repositories.

## Prerequisites

- Ubuntu 26.04 Server installed and booted
- Internet connection
- User account with `sudo` privileges

## Installation Procedure

### Step 1: Update System

```bash
sudo apt update && sudo apt upgrade -y
```

### Step 2: Install Intel iGPU Stack

```bash
sudo apt install -y \
  libze-intel-gpu1 \
  libze1 \
  intel-opencl-icd \
  clinfo \
  intel-ocloc \
  intel-media-va-driver-non-free \
  libvpl2 \
  libvpl-tools \
  va-driver-all \
  vainfo
```

### Step 3: Add User to Render Group

```bash
sudo usermod -aG render $USER
newgrp render
```

### Step 4: Reboot System

```bash
sudo reboot
```

## Verification

After reboot, run the following verification commands:

### Compute Runtime (OpenCL + Level Zero)

```bash
clinfo | grep -E "Platform|Device Name|Version"
```

Expected: Intel platform with Arc Graphics / Meteor Lake device

### Hardware Video Acceleration (Quick Sync)

```bash
vainfo | grep -E "Driver|Profile"
```

Expected: Driver: Intel iHD driver

### GPU Device Nodes

```bash
ls -l /dev/dri/
```

Expected: `card0` and `renderD128` present

## Optional: Real-time GPU Monitor

```bash
sudo apt install -y intel-gpu-tools
intel_gpu_top