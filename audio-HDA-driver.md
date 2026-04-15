# Audio Configuration

> Fixes the "Dummy Output" issue on Intel Core Ultra 5 125H (Meteor Lake audio DSP) by forcing the stable legacy HDA driver instead of SOF.

## Prerequisites

- Ubuntu 26.04 Desktop installed
- Intel iGPU stack already installed  
- User account with `sudo` privileges

## Installation Procedure

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

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Dummy Output persists after reboot | Verify kernel parameter is set correctly in `/etc/default/grub`; run `sudo update-grub` |
| Kernel upgrade breaks audio | Run `sudo dkms autoinstall` after kernel update, then reboot |
| Want to revert to SOF driver | Remove `snd_intel_dspcfg.dsp_driver=1` from GRUB config and reboot |

## Notes

- **Driver mechanism**: The `snd_intel_dspcfg.dsp_driver=1` kernel parameter forces use of the legacy HDA driver instead of SOF.
- **iGPU impact**: This setting affects audio only. Video acceleration (VA-API/Quick Sync) remains unaffected.