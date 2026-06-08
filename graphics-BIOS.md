**BIOS Graphics Configuration Guide**  
**For Maximum Local AI Performance on Zettlab D6/D8 Ultra**

### Goal
Optimize the onboard Intel Arc iGPU for local AI workloads (large language models, inference, etc.) while keeping the system stable as a NAS.

### Enter BIOS
1. Power on the device.
2. Press **F2** repeatedly to enter BIOS Setup.
3. Go to the **Advanced** tab → **Graphics Configuration**.

### Recommended Changes

Only change the following settings:

| Setting                                      | Change To       | Notes |
|----------------------------------------------|-----------------|-------|
| **Skip Scanning of External Gfx Card**       | **Enabled**     | Skip unnecessary PCIe scan (you are staying on iGPU) |
| **Primary Display**                          | **IGFX**        | Force internal Arc iGPU as primary |
| **Internal Graphics**                        | **Enabled**     | Ensure iGPU is always active |
| **Igfx Gsm2**                                | **4GB**         | **Most important change** — gives solid dedicated VRAM without starving system RAM |
| **GT RC1p Support**                          | **Disabled**    | Reduces potential throttling during long inference |
| **Media RC1p Support**                       | **Disabled**    | Same reason as above |

### What to Leave Unchanged
- **DVMT Pre-Allocated** — Already at maximum (128M)
- All other settings (VDD Enable, Configure GT/Media, PAVP, etc.) — Keep at current/default values

### Save and Exit
1. Press **F10**.
2. Select **Yes** to save changes and exit.
3. The system will reboot.

### After Reboot – Quick Verification
Run these commands to confirm the iGPU is properly configured:

```bash
# Check iGPU detection
lspci | grep -i "VGA\|Display"

# Monitor iGPU in real time (recommended during AI workloads)
sudo intel_gpu_top
```

### Summary of Changes
| Priority | Setting                        | New Value   |
|----------|--------------------------------|-------------|
| Highest  | **Igfx Gsm2**                  | **4GB**     |
| High     | Primary Display                | **IGFX**    |
| High     | Skip Scanning of External Gfx Card | **Enabled** |
| Medium   | GT RC1p Support                | **Disabled** |
| Medium   | Media RC1p Support             | **Disabled** |
| High     | Internal Graphics              | **Enabled** |

This configuration provides a good balance between dedicated iGPU memory and available system RAM for running large models (30B–70B class) efficiently.

Would you like a version of this guide formatted for your existing documentation (e.g. as a new `.md` file)?