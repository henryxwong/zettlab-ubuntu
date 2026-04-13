**# Intel Arc iGPU Driver Installation Guide – Zettlab D6/D8 Ultra (Ubuntu 26.04)**

**Purpose**  
This guide installs the Intel Graphics compute and media stack for the integrated **Arc Graphics** (Meteor Lake iGPU) on the Intel Core Ultra 5 125H.

It enables:
- Hardware video decoding/encoding (VA-API / Quick Sync)
- OpenCL and oneAPI Level Zero compute runtime (required for PyTorch XPU, etc.)
- Full access to `/dev/dri/renderD*` devices
- Proper support for the front LCD (`eDP-1`)

**Note for Ubuntu 26.04 Resolute**  
Some advanced packages (intel-gsc, intel-metrics-discovery, libmfx-gen1) are not yet available in the official repositories. The trimmed list below contains only packages that exist in Ubuntu 26.04.

**When to run this guide**  
After completing:
1. [Installation Guide](ubuntu-installation.md)
2. [Fan Control Guide](fan-control.md)

## Prerequisites
- Ubuntu 26.04 Server installed and booted
- Internet connection
- User account with `sudo` rights

## Installation Steps

### 1. Update the system
```bash
sudo apt update && sudo apt upgrade -y
```

### 2. Install the Intel iGPU stack (working packages only)
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

### 3. Add your user to the `render` group
```bash
sudo usermod -aG render $USER
newgrp render
```

### 4. Reboot
```bash
sudo reboot
```

## Verification (after reboot)

Run these commands:

```bash
# 1. Compute runtime (OpenCL + Level Zero)
clinfo | grep -E "Platform|Device Name|Version"

# 2. Hardware video acceleration (Quick Sync)
vainfo | grep -E "Driver|Profile"

# 3. GPU device nodes
ls -l /dev/dri/
```

**Expected results**
- `clinfo` shows **Intel** platform with **Arc Graphics / Meteor Lake** device
- `vainfo` shows **Driver: Intel iHD driver**
- `/dev/dri/` contains `card0` and `renderD128`

### Optional: Real-time GPU monitor
```bash
sudo apt install -y intel-gpu-tools
intel_gpu_top
```