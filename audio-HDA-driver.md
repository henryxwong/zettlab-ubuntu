# Audio Configuration

> Fixes the "Dummy Output" issue on Intel Core Ultra 5 125H (Meteor Lake audio DSP) by forcing the stable legacy HDA driver instead of SOF.

## Prerequisites

- Ubuntu 26.04 Server installed
- Intel iGPU stack already installed
- User account with `sudo` privileges

## Installation Procedure

### Step 1: Install Required Firmware

```bash
sudo apt update && sudo apt install -y firmware-sof-signed snapd
```

### Step 2: Configure Kernel Command Line

See the full list of recommended kernel parameters here:

**[Kernel Parameters Reference](kernel-parameters.md)**

The audio-related parameter is `snd_intel_dspcfg.dsp_driver=1`.

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

Test audio output with a simple sine wave:

```bash
speaker-test -t sine -f 1000 -l 3
```

This should play a 1kHz tone through the default output device for a few seconds.

You can also test with a short audio file:

```bash
paplay /usr/share/sounds/sound-icons/trumpet-12.wav
```

(If the file doesn't exist, install `sound-icons` or use any `.wav` file.)