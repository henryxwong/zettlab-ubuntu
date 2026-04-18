# Realtek RTL8127 10GbE Networking Configuration (Zettlab D6/D8 Ultra)

> Recommended stable setup using the **stock in-kernel r8169 driver**

## Overview

On the Zettlab D6/D8 Ultra, the **stock `r8169` driver** has proven significantly more stable than the third-party `r8127` DKMS driver for sustained video streaming and general use.  
It eliminates the random disconnects and packet drops that many users experience with r8127 (especially under light-to-medium load).

**Recommendation:** Use the built-in `r8169` driver + the minimal stability tunings below.

## Step 1: Required Kernel Parameters

Edit GRUB configuration:

```bash
sudo nano /etc/default/grub
```

Change the `GRUB_CMDLINE_LINUX_DEFAULT` line to include:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash pcie_aspm=off pcie_port_pm=off"
```

Apply the changes:

```bash
sudo update-grub
```

## Step 2: Minimal Network Stability Tuning

```bash
cat << EOF | sudo tee -a /etc/sysctl.conf

# Zettlab D6/D8 Ultra 10GbE minimal stable tuning (r8169)
net.core.netdev_max_backlog = 10000
net.core.netdev_budget = 60000
net.core.rps_sock_flow_entries = 32768
EOF

sudo sysctl -p
```

## Step 3: Reboot

```bash
sudo reboot
```

## Verification

After reboot, confirm you are using the stock driver:

```bash
ethtool -i enp88s0 | grep driver
ethtool -i enp89s0 | grep driver
```

Expected output:
```
driver: r8169
```

## Samba Stability Note (Critical for Video Playback)

In `/etc/samba/smb.conf`, use:
```conf
smb encrypt = desired
```

This setting, combined with the above network parameters, provides the best stability for 10GbE movie streaming on macOS and other clients.

## Optional: Trying the r8127 DKMS Driver

Only recommended if you have a specific need for the r8127 driver. Most users on the Zettlab D6/D8 Ultra get better long-term stability with the stock `r8169` driver.

## Troubleshooting

| Issue                    | Resolution |
|--------------------------|------------|
| Movie hiccups / stuttering | Use `smb encrypt = desired` in Samba and ensure `pcie_aspm=off pcie_port_pm=off` |
| Still seeing issues      | Verify parameters with `cat /proc/cmdline` and test with NFS instead of Samba |

This configuration is the minimal stable setup after extensive testing on the Zettlab D6/D8 Ultra.