**# Audio Setup Guide – Zettlab D6/D8 Ultra (Ubuntu 26.04 Desktop)**

**Purpose**  
Fix the very common **“Dummy Output”** issue on the Intel Core Ultra 5 125H (Meteor Lake audio DSP).

The modern **SOF** (Sound Open Firmware) driver frequently fails to load the topology file on this exact NAS hardware → no real audio devices appear.  
We force the **stable legacy HDA driver** (the same one used successfully on thousands of Meteor Lake laptops).

This gives you proper headphone, speaker, and HDMI audio output with zero performance impact on the Arc iGPU or video playback.

**When to run this guide**
- After you have completed the **[Intel Arc iGPU Drivers](intel-igpu.md)**
- After a fresh Ubuntu 26.04 Desktop Minimal install (or after any kernel update)

## Prerequisites
- Ubuntu 26.04 Desktop Minimal installed
- Intel iGPU stack already installed
- User account with `sudo` rights

## Installation Steps

### 1. Install required audio firmware and snapd
```bash
sudo apt update && sudo apt install -y firmware-sof-signed snapd
```

### 2. Force the stable legacy HDA audio driver
```bash
sudo nano /etc/default/grub
```

Find the line that starts with `GRUB_CMDLINE_LINUX_DEFAULT=` and change it to **exactly** this:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash video=eDP-1:d loglevel=3 snd_intel_dspcfg.dsp_driver=1"
```

Save (Ctrl+O → Enter → Ctrl+X).

### 3. Apply the changes and reboot
```bash
sudo update-grub
sudo reboot
```

## Verification (after reboot)

1. Open **Settings → Sound**  
   → You should now see real output devices (Speakers, Headphones, HDMI, etc.) instead of only “Dummy Output”.

2. Run these commands and check the output:
```bash
# Should show Intel Meteor Lake audio card using HDA (not SOF)
aplay -l | grep -E 'card|Intel'

# Should list real sound cards
pactl list short cards
```

**Expected result**:
- You see something like `card 0: PCH` or `sof-soundwire` disabled
- Sound Settings shows working outputs

3. Quick audio test:
```bash
speaker-test -c 2 -t sine
```
(You should hear a clear test tone from your speakers/headphones. Press Ctrl+C to stop.)

### Optional: Install GUI volume control (recommended)
```bash
sudo apt install -y pavucontrol
```
Launch it with `pavucontrol` for easy per-app volume, profiles, and advanced routing.

## Important Notes

- **Why this works**: `snd_intel_dspcfg.dsp_driver=1` tells the kernel to ignore the broken SOF driver and use the older, rock-solid HDA driver instead.
- **Kernel updates**: After any `apt upgrade` that installs a new kernel, run `sudo dkms autoinstall` and reboot. The audio fix usually survives, but always check Sound Settings.
- **Reverting to SOF (experimental)**: Remove `snd_intel_dspcfg.dsp_driver=1` from the GRUB line and reboot if you want to try the newer driver again in the future.
- **No impact on iGPU**: This parameter only affects audio. Your video acceleration (VA-API / Quick Sync) remains untouched.

Your audio is now stable and ready for VLC, mpv, browsers, etc.

Run the verification commands above and paste the output here if you still see “Dummy Output” after reboot — we’ll fix it immediately.

Everything else (fan control, storage pool, etc.) is now ready whenever you want the next guide!