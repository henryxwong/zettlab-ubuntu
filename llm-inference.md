# LLM Inference on Intel Arc iGPU (Vulkan & SYCL)

> Setup for running local LLMs using llama.cpp with Vulkan or SYCL backends on Zettlab D6/D8 Ultra (Meteor Lake Arc iGPU).

## Overview

This guide covers two recommended backends for high-performance LLM inference on the integrated Arc Graphics:

- **Vulkan** — Easier setup with good performance and better MTP support on Intel hardware
- **SYCL** — Potentially higher performance via oneAPI / Level Zero (requires more setup)

Both backends benefit from the BIOS settings documented in `graphics-BIOS.md` (especially 4GB `Igfx Gsm2`).

## Prerequisites

- BIOS configured according to `graphics-BIOS.md` (4GB dedicated graphics memory recommended)
- Ubuntu 26.04 with working iGPU drivers (see `graphics-iGPU.md`)
- User added to the `render` group

## Option 1: Vulkan Backend (Recommended)

### Installation

```bash
sudo apt update
sudo apt install -y \
    mesa-vulkan-drivers \
    vulkan-tools \
    vulkan-validationlayers
```

### Verification

```bash
vulkaninfo --summary | grep -E "GPU|deviceName"
```

Expected output:
```
Intel(R) Arc(tm) Graphics (MTL)
```

### Running with Vulkan + MTP

```bash
./llama-cli \
    -m model.gguf \
    -ngl 99 \
    --spec-type draft-mtp \
    --spec-draft-n-max 2
```

## Option 2: SYCL Backend

### Environment Setup

Source the oneAPI environment:

```bash
source /opt/intel/oneapi/setvars.sh
```

### Verification

```bash
sycl-ls
```

Expected output example:
```
[level_zero:gpu][level_zero:0] Intel(R) oneAPI Unified Runtime over Level-Zero, Intel(R) Arc(TM) Graphics
```

### Building and Running llama.cpp with SYCL

Compile with SYCL support:

```bash
cmake -B build -DGGML_SYCL=ON \
    -DCMAKE_C_COMPILER=icx \
    -DCMAKE_CXX_COMPILER=icpx
cmake --build build --config Release
```

Run the model:

```bash
source /opt/intel/oneapi/setvars.sh
./llama-cli -m model.gguf -ngl 99
```

## Recommended Quantizations

For **Qwopus3.6-35B-A3B-v1**:

| Quant     | Approx. Size | Recommendation             |
|-----------|--------------|----------------------------|
| Q4_K_M    | ~21 GB       | Best balance (recommended) |
| Q5_K_M    | ~24.7 GB     | Higher quality             |
| Q3_K_M    | ~18 GB       | Lower memory usage         |

## Notes

- MTP currently works more reliably on the **Vulkan** backend with Intel Arc.
- With 4GB dedicated VRAM + unified memory, offloading most layers with `-ngl 99` is usually feasible.
- Monitor GPU usage with `intel_gpu_top`.

## References

- [graphics-BIOS.md](graphics-BIOS.md) — BIOS settings for AI workloads
- [graphics-iGPU.md](graphics-iGPU.md) — Base Intel Arc iGPU driver installation
