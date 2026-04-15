# Storage Pool Setup: mergerfs + SnapRAID

> Configures XFS data disks with Btrfs parity disk, using mergerfs for pooling and SnapRAID for backup on Zettlab D6/D8 Ultra NAS.

## Overview

**Disk Assumptions:**
- `/dev/sda` to `/dev/sde`: **5 data disks**
- `/dev/sdf`: **dedicated parity disk**

> **Important**: Device names (`/dev/sdX`) are not persistent and may change after reboots. Always verify with `lsblk` and use UUIDs in `/etc/fstab`.

**Filesystem Configuration:**
- **Data disks**: XFS (optimal performance; no 16 TB file-size limit)
- **Parity disk**: Btrfs (enables snapshot-based replication with `btrfs send | receive`)

**Directory Structure:**
- `/mnt/disk1` – `/mnt/disk5`: Individual data disks
- `/mnt/parity`: Parity disk
- `/mnt/pool`: mergerfs pooled mount point

## Prerequisites

- Ubuntu 26.04 Server installed and updated
- Fan control module installed and running
- Disks detected (`lsblk`) with complete backup

## Disk Preparation

### Step 1: Identify Disks

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,UUID
sudo ls /dev/disk/by-id/
```

### Step 2: Format Disks

```bash
# Data disks (XFS – recommended)
for dev in sda sdb sdc sdd sde; do
    sudo wipefs -af /dev/$dev
    sudo parted -s /dev/$dev mklabel gpt
    sudo parted -s /dev/$dev mkpart primary 0% 100%
    sudo mkfs.xfs -f -L disk${dev: -1} /dev/${dev}1
done

# Parity disk (Btrfs – recommended for snapshots)
sudo wipefs -af /dev/sdf
sudo parted -s /dev/sdf mklabel gpt
sudo parted -s /dev/sdf mkpart primary 0% 100%
sudo mkfs.btrfs -f -L parity /dev/sdf1
```

### Step 3: Create Mount Points

```bash
sudo mkdir -p /mnt/disk{1..5} /mnt/parity /mnt/pool
```

### Step 4: Configure Filesystem Mounts

Obtain UUIDs:

```bash
sudo blkid
```

Add entries to `/etc/fstab` using UUIDs:

```
# Data disks (XFS)
UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /mnt/disk1 xfs defaults,noatime 0 2
UUID=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy /mnt/disk2 xfs defaults,noatime 0 2
UUID=zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz /mnt/disk3 xfs defaults,noatime 0 2
UUID=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa /mnt/disk4 xfs defaults,noatime 0 2
UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb /mnt/disk5 xfs defaults,noatime 0 2

# Parity disk (Btrfs)
UUID=cccccccc-cccc-cccc-cccc-cccccccccccc /mnt/parity btrfs defaults,noatime,compress=no,autodefrag 0 2
```

Test mounts:

```bash
sudo systemctl daemon-reload
sudo mount -a
df -h | grep -E 'disk|parity|pool'
```

## Software Installation

### Step 1: Install SnapRAID

```bash
sudo apt update
sudo apt install snapraid -y
```

### Step 2: Install mergerfs

Check for latest release at https://github.com/trapexit/mergerfs/releases

```bash
cd /tmp
wget https://github.com/trapexit/mergerfs/releases/download/2.41.1/mergerfs_2.41.1.ubuntu-noble_amd64.deb
sudo dpkg -i mergerfs_*.deb
mergerfs -V
```

## Pool Configuration

### Step 1: Configure mergerfs in fstab

Add the following line to `/etc/fstab`:

```
/mnt/disk* /mnt/pool fuse.mergerfs defaults,nonempty,allow_other,use_ino,cache.files=off,moveonenospc=true,dropcacheonclose=true,minfreespace=20G,category.create=epmfs,fsname=mergerfs,x-systemd.requires-mounts-for=/mnt/disk1,x-systemd.requires-mounts-for=/mnt/disk2,x-systemd.requires-mounts-for=/mnt/disk3,x-systemd.requires-mounts-for=/mnt/disk4,x-systemd.requires-mounts-for=/mnt/disk5 0 0
```

### Step 2: Mount Pool

```bash
sudo systemctl daemon-reload
sudo mount -a
ls /mnt/pool
```

### mergerfs Policy Reference

| Policy | Description |
|--------|-------------|
| **epmfs** (default) | Existing-path most-free-space; preserves directory path |
| eplfs | Existing-path least-free-space |
| mfs | Most-free-space (always picks disk with most space) |
| ff | First-found (creates on first disk with space) |

To change policy, edit the mergerfs line in `/etc/fstab` and run:
```bash
sudo systemctl daemon-reload && sudo mount -a
```

## Parity File Configuration

```bash
sudo mount -a

# Create parity file on Btrfs root
sudo touch /mnt/parity/snapraid.parity

# Disable CoW on parity file to prevent fragmentation
sudo chattr +C /mnt/parity/snapraid.parity

# Verify
lsattr /mnt/parity/snapraid.parity   # should show "C"
```

## SnapRAID Configuration

```bash
sudo nano /etc/snapraid.conf
```

Configuration file:

```
# Parity
parity /mnt/parity/snapraid.parity

# Content files (for quick content listing)
content /var/snapraid.content
content /mnt/disk1/.snapraid.content
content /mnt/disk2/.snapraid.content
content /mnt/disk3/.snapraid.content
content /mnt/disk4/.snapraid.content
content /mnt/disk5/.snapraid.content

# Data disks
data d1 /mnt/disk1/
data d2 /mnt/disk2/
data d3 /mnt/disk3/
data d4 /mnt/disk4/
data d5 /mnt/disk5/

# Excludes
exclude /lost+found/
exclude *.unrecoverable
exclude /tmp/
exclude .snapraid.content

autosave 1000
```

### Initial Sync

```bash
sudo snapraid -c /etc/snapraid.conf diff
sudo snapraid -c /etc/snapraid.conf sync
```

## Maintenance and Automation

### Create Maintenance Script

```bash
sudo nano /usr/local/bin/snapraid-maintenance.sh
```

Script content:

```bash
#!/bin/bash
LOG=/var/log/snapraid.log
echo "=== SnapRAID maintenance started at $(date) ===" >> $LOG
snapraid -c /etc/snapraid.conf sync >> $LOG 2>&1
snapraid -c /etc/snapraid.conf scrub -p 8 -o 0 >> $LOG 2>&1
echo "=== SnapRAID maintenance finished at $(date) ===" >> $LOG
```

Make executable:

```bash
sudo chmod +x /usr/local/bin/snapraid-maintenance.sh
```

### Schedule Maintenance

```bash
sudo crontab -e
```

Add cron entry:

```
0 3 * * * /usr/local/bin/snapraid-maintenance.sh