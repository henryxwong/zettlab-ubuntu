# Realtek RTL8127 10GbE Networking Configuration (Zettlab D6/D8 Ultra)

> Recommended stable setup using the **stock in-kernel r8169 driver**

## Overview

On the Zettlab D6/D8 Ultra, the **stock `r8169` driver** has proven significantly more stable than the third-party `r8127` DKMS driver.  
It eliminates the random disconnects and packet drops that many users experience with r8127 (especially under CPU load).

**Recommendation:** Use the built-in `r8169` driver + the stability tunings below.

## Step 1: Apply Stability Kernel Parameters

Edit GRUB configuration:

```bash
sudo nano /etc/default/grub
```

Change the `GRUB_CMDLINE_LINUX_DEFAULT` line to include (or add) the following:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash pcie_aspm.policy=performance pcie_port_pm=off"
```

Apply the changes:

```bash
sudo update-grub
```

## Step 2: Apply Network High-Load Tuning

```bash
cat << EOF | sudo tee -a /etc/sysctl.conf

# Zettlab D6/D8 Ultra 10GbE stability tuning (r8169)
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

Monitor packet drops (should stay at 0 even under load):

```bash
watch -n 2 'echo "=== enp88s0 ==="; ethtool -S enp88s0 | grep rx_missed; echo "=== enp89s0 ==="; ethtool -S enp89s0 | grep rx_missed'
```

## Optional: Trying the r8127 DKMS Driver

Only recommended if you have a specific need for the r8127 driver. Most users on the Zettlab D6/D8 Ultra get better stability with the stock `r8169` driver.

## Troubleshooting

| Issue                    | Resolution |
|--------------------------|------------|
| Still seeing disconnects | Verify `pcie_aspm.policy=performance` is active (`cat /proc/cmdline`) |
| High `rx_missed` counters| Increase the sysctl values further or check cable/switch |