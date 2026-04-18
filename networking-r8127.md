# Realtek RTL8127 Networking Stability Guide (Zettlab D6/D8 Ultra)

> Stable configuration for Samba / mergerfs video playback on Zettlab D6/D8 Ultra running Ubuntu 26.04.

## Overview

The built-in Realtek RTL8127A (2.5 GbE) is sensitive to PCIe power management and CPU C-states during sustained sequential reads.  
The **stock in-kernel `r8169` driver** is the most stable option. The out-of-tree `r8127` DKMS driver frequently increases packet drops and stuttering on this hardware.

**Tested symptoms resolved:** video hiccups over Samba, SSH session drops during light-to-medium load.

## BIOS Settings (Mandatory)

Enter BIOS (F2 at boot) and set the following:

**CPU → Power Management Control**
- PCIe Gen Speed Downgrade → **[Disabled]**
- Package C-State Limit → **[C1]**
- C-State Auto Demotion → **[C0]**
- C-State Un-demotion → **[C0]**
- Package C-State Demotion → **[Disabled]**
- Package C-State Un-demotion → **[Disabled]**

Save and exit (F10).

## Step 1: Kernel Parameters

Edit GRUB configuration:

```bash
sudo nano /etc/default/grub
```

Change the `GRUB_CMDLINE_LINUX_DEFAULT` line to:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash pcie_aspm=off pcie_port_pm=off"
```

Apply:

```bash
sudo update-grub
```

## Step 2: Strong Network Stack Tuning

```bash
sudo nano /etc/sysctl.conf
```

Add/replace with:

```conf
# Zettlab D6/D8 Ultra – aggressive stability tuning (r8169)
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 25000
net.core.netdev_budget = 80000
net.core.rps_sock_flow_entries = 65536
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_mem = 16777216 25165824 33554432
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
```

Apply:

```bash
sudo sysctl -p
```

## Step 3: Disable Problematic Offloads (Permanent)

```bash
sudo nano /etc/rc.local
```

Replace content with:

```bash
#!/bin/bash
# Zettlab D6/D8 Ultra – r8169 stability fixes
for nic in enp88s0 enp89s0; do
    ethtool -K $nic tso off gso off gro on 2>/dev/null || true
done
```

Make executable and enable:

```bash
sudo chmod +x /etc/rc.local
sudo systemctl daemon-reload
sudo systemctl start rc-local.service
```

## Verification

```bash
ethtool -i enp88s0 | grep driver   # must show r8169
ethtool -S enp88s0 | grep -E 'error|drop|miss|queue'
```

During video playback the counters should stay at zero and playback should be smooth with no SSH drops.

## Notes

- Do **not** install the r8127 DKMS driver — it worsens symptoms on this hardware.
- BIOS changes slightly increase idle power (5–15 W) and fan activity.
- All changes are reversible in BIOS.