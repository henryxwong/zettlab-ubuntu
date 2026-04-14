# Audio Configuration

**Purpose**

Fixes the "Dummy Output" issue on Intel Core Ultra 5 125H (Meteor Lake audio DSP) by forcing the stable legacy HDA driver.

The modern SOF (Sound Open Firmware) driver frequently fails to load the topology file on this hardware, preventing real audio devices from appearing. The legacy HDA driver provides proper headphone, speaker, and HDMI audio output without impacting iGPU video acceleration.

## Prerequisites

- Ubuntu 26.04 Desktop installed
- Intel iGPU stack already installed
- User account with `sudo` privileges

## Configuration Procedure

### Step 1: Install Required Firmware

```bash
sudo apt update && sudo apt install -y firmware-sof-signed snapd
```

### Step 2: Configure Kernel Command Line

Edit GRUB configuration:

```bash
sudo nano /etc/default/grub
```

Locate the `GRUB_CMDLINE_LINUX_DEFAULT=` line and set it to:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash video=eDP-1:d loglevel=3 snd_intel_dspcfg.dsp_driver=1"
```

Save changes (Ctrl+O → Enter → Ctrl+X).

### Step 3: Apply Configuration and Reboot

```bash
sudo update-grub
sudo reboot
```

## Verification

After reboot, verify audio functionality:

### Sound Settings

Open **Settings → Sound**. Output devices (Speakers, Headphones, HDMI) should appear instead of "Dummy Output".

### Command Line Verification

```bash
aplay -l | grep -E 'card|Intel'
pactl list short cards
```

Expected results:
- Audio card appears as `card 0: PCH` (HDA)
- Sound Settings shows working outputs

### Audio Test

```bash
speaker-test -c 2 -t sine
```

Press Ctrl+C to stop the test tone.

## Optional: Install Volume Control GUI

```bash
sudo apt install -y pavucontrol
```

Launch with `pavucontrol` for per-app volume, profiles, and advanced routing.

## Notes

- **Driver mechanism**: The `snd_intel_dspcfg.dsp_driver=1` kernel parameter forces use of the legacy HDA driver instead of SOF.
- **Kernel updates**: After kernel upgrades, run `sudo dkms autoinstall` and verify audio settings.
- **Reverting to SOF**: Remove `snd_intel_dspcfg.dsp_driver=1` from GRUB configuration and reboot to attempt SOF again.
- **iGPU impact**: This setting affects audio only. Video acceleration (VA-API/Quick Sync) remains unaffected.