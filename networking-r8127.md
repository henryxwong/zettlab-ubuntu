# Realtek r8127 DKMS Driver Installation

> Replaces the in-kernel `r8169` driver with the official Realtek `r8127` DKMS driver for improved stability on RTL8127A 10GbE NICs.

## Prerequisites

- Ubuntu 26.04 Server installed with internet access
- `git`, `dkms`, and build tools

## Installation Procedure

### Step 1: Install Build Dependencies

```bash
sudo apt update
sudo apt install dkms build-essential git -y
```

### Step 2: Clone and Install the r8127 DKMS Driver

```bash
git clone https://github.com/PeterSuh-Q3/r8127.git
cd r8127
sudo ./autorun.sh
```

### Step 3: Blacklist the r8169 Driver

```bash
echo "blacklist r8169" | sudo tee /etc/modprobe.d/blacklist-r8169.conf
sudo update-initramfs -u
```

### Step 4: Reboot

```bash
sudo reboot
```

## Verification

After reboot, verify the driver is active:

### Driver Information

```bash
ethtool -i enp88s0
ethtool -i enp89s0
```

Expected output includes `driver: r8127`.

### Network Status

```bash
ip link show enp88s0
ip link show enp89s0
sudo ethtool enp88s0 | grep -E "Speed|Link detected"
```

### Kernel Messages

```bash
dmesg | grep -E 'r8127|RTL8127'
```

## Updating the Driver

```bash
cd ~/r8127
git pull
sudo ./autorun.sh
sudo update-initramfs -u
sudo reboot
```

## Reverting to r8169 Driver

```bash
sudo rm /etc/modprobe.d/blacklist-r8169.conf
sudo update-initramfs -u
cd ~/r8127
sudo ./autorun.sh --uninstall
sudo reboot
```

## Troubleshooting

| Issue | Resolution |
|-------|------------|
| Build fails | Install headers: `sudo apt install linux-headers-$(uname -r) -y`; rerun `./autorun.sh` |
| NICs not detected after reboot | Boot previous kernel from GRUB and revert changes |
| r8169 still shown in ethtool | Verify blacklist file; run `update-initramfs -u` |
| Link speed drops to 1 Gbps | Force link: `sudo ethtool -s enp88s0 speed 2500 duplex full autoneg off` |