# Realtek RTL8127 Networking – Current Status (Zettlab D6/D8 Ultra)

> **Update (May 2026):** The onboard Realtek RTL8127 NIC remains unstable even with extensive tuning and the out-of-tree `r8127` driver. After repeated packet drops, stuttering during Samba playback, and SSH disconnects, the onboard NIC has been abandoned.

## Current Recommendation

Use a **USB-C Ethernet adapter** (or USB 3.0 Gigabit adapter) as the primary network connection. This has proven far more stable for daily use including Samba, SSH, and large file transfers.

## Disabling the Onboard NIC

See the full list of recommended kernel parameters here:

**[Kernel Parameters Reference](kernel-parameters.md)**

The networking-related parameter is `modprobe.blacklist=r8169`.

## Network Stack Tuning (Still Recommended)

Even when using a USB Ethernet adapter, the following sysctl tuning helps with Samba and large transfers:

```bash
sudo nano /etc/sysctl.conf
```

Add or update:

```conf
# Zettlab D6/D8 Ultra – network stability tuning
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 25000
net.core.netdev_budget = 80000
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_mem = 16777216 25165824 33554432
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
```

Apply changes:

```bash
sudo sysctl -p
```

## SSH Keepalive Settings

Prevent "Broken pipe" errors during long transfers or directory listings:

```bash
sudo nano /etc/ssh/sshd_config
```

Add at the bottom:

```conf
ClientAliveInterval 10
ClientAliveCountMax 60
TCPKeepAlive yes
```

Then restart SSH:

```bash
sudo systemctl restart sshd
```

## Verification

Check that the onboard NIC is not active:

```bash
ip link show | grep -E 'enp88s0|enp89s0'
```

You should not see these interfaces (or they should be down and without carrier).

Check your USB Ethernet adapter:

```bash
ip -br addr show
ethtool -i enx<your-usb-mac> | grep driver
```

## Notes

- The `r8127` DKMS driver and extensive BIOS C-state changes are no longer required.
- Only the in-tree driver (`r8169`) is blacklisted.
- USB-C Ethernet adapters have shown significantly better stability on this hardware.