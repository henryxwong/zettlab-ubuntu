# Kernel Parameters Reference

> Centralized list of recommended kernel command line parameters for Zettlab D6/D8 Ultra running Ubuntu 26.04.

This page collects all kernel parameters used across the guides to avoid duplication and make maintenance easier.

## Recommended Combined Parameters

Edit `/etc/default/grub`:

```bash
sudo nano /etc/default/grub
```

Set `GRUB_CMDLINE_LINUX_DEFAULT` to:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash modprobe.blacklist=r8169 video=eDP-1:d snd_intel_dspcfg.dsp_driver=1"
```

Then apply:

```bash
sudo update-grub
sudo reboot
```

> **Note**: The `crashkernel=` parameter is automatically added by Ubuntu when kdump is enabled. You can safely leave it as-is.

## Parameter Breakdown

| Parameter                              | Purpose                                      | Required?     | Related Guide                  |
|----------------------------------------|----------------------------------------------|---------------|--------------------------------|
| `modprobe.blacklist=r8169`             | Prevent in-tree Realtek driver from loading  | Recommended   | [Networking](networking-r8127.md) |
| `video=eDP-1:d`                        | Disable front LCD during boot (prevents hang)| Yes           | [Installation](ubuntu-installation.md) |
| `snd_intel_dspcfg.dsp_driver=1`        | Force legacy HDA audio driver (fix Dummy Output) | Yes        | [Audio](audio-HDA-driver.md)   |

## Current Status Notes

- The onboard Realtek RTL8127 NIC has been abandoned due to instability. A USB-C Ethernet adapter is used instead.
- Only the in-tree driver (`r8169`) is blacklisted. The out-of-tree `r8127` driver is not installed.
- `pcie_aspm=off` and `pcie_port_pm=off` have been removed (no longer needed after abandoning the onboard NIC).

## How to View Current Parameters

```bash
cat /proc/cmdline
```

## Future Additions

When adding new kernel parameters in other guides, please also update this file so everything stays in sync.