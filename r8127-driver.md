# Realtek r8127 DKMS Driver Installation Guide

**Purpose**  
The in-kernel `r8169` driver used by the RTL8127A NICs can cause packet drops, transmit timeouts, and SSH “Operation timed out / Broken pipe” issues under high CPU load.  
The official Realtek `r8127` DKMS driver provides significantly better stability on this hardware.

This guide is written for **Ubuntu 26.04 Server** on the Zettlab D6/D8 Ultra.

## Prerequisites
- Booted into Ubuntu 26.04 Server with internet access
- `git`, `dkms`, and build tools

## Installation Steps

### 1. Install build dependencies
```bash
sudo apt update
sudo apt install dkms build-essential git -y
```

### 2. Clone and install the r8127 DKMS driver
```bash
git clone https://github.com/PeterSuh-Q3/r8127.git
cd r8127
sudo ./autorun.sh
```

### 3. Blacklist the old r8169 driver
```bash
echo "blacklist r8169" | sudo tee /etc/modprobe.d/blacklist-r8169.conf
sudo update-initramfs -u
```

### 4. Reboot
```bash
sudo reboot
```

## Verification After Reboot

```bash
# Check active driver
ethtool -i enp88s0
ethtool -i enp89s0
```
Expected output includes `driver: r8127`.

```bash
# Confirm network status
ip link show enp88s0
ip link show enp89s0
sudo ethtool enp88s0 | grep -E "Speed|Link detected"
```

```bash
# Check dmesg
dmesg | grep -E 'r8127|RTL8127'
```

## Updating the Driver Later
```bash
cd ~/r8127
git pull
sudo ./autorun.sh
sudo update-initramfs -u
sudo reboot
```

## Reverting (if necessary)
```bash
sudo rm /etc/modprobe.d/blacklist-r8169.conf
sudo update-initramfs -u
cd ~/r8127
sudo ./autorun.sh --uninstall
sudo reboot
```

## Troubleshooting

| Issue                              | Solution |
|------------------------------------|----------|
| Build fails                        | `sudo apt install linux-headers-$(uname -r) -y` then rerun `./autorun.sh` |
| NICs not detected after reboot     | Boot previous kernel from GRUB and revert |
| r8169 still shown in ethtool       | Verify blacklist file and run `update-initramfs -u` |
| Link speed drops to 1 Gbps         | `sudo ethtool -s enp88s0 speed 2500 duplex full autoneg off` |