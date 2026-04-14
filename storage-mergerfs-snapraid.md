# Storage Pool Setup: mergerfs + SnapRAID

**Disk Assumptions**

This guide assumes:
- `/dev/sda` to `/dev/sde` are **5 data disks**
- `/dev/sdf` is the dedicated **parity disk**

**Important**: Device names (`/dev/sdX`) are not persistent and may change after reboots, kernel updates, or SATA reordering. Always verify with `lsblk` and use UUIDs (or `/dev/disk/by-id/`) in `/etc/fstab` and `snapraid.conf`.

## Filesystem Configuration

**Recommended / default configuration**:
- **Data disks** (`/dev/sda`–`/dev/sde`): **XFS** (optimal performance; no 16 TB file-size limit)
- **Parity disk** (`/dev/sdf`): **Btrfs** (enables snapshot-based replication with `btrfs send | receive`)

Alternative configurations:
- Use `ext4` on data disks if the parity file stays under 16 TB.
- Use `XFS` on parity for simpler setup with slightly faster performance if snapshots are not required.
- Avoid `Btrfs` on data disks due to CoW overhead negatively impacting SnapRAID performance.

**Directory structure**:
- `/mnt/disk1` – `/mnt/disk5`: Individual data disks
- `/mnt/parity`: Parity disk
- `/mnt/pool`: mergerfs pooled mount point (daily use)

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

Modify `mkfs.*` commands if a different filesystem is selected.

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

```conf
# Data disks (XFS)
UUID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx /mnt/disk1 xfs defaults,noatime 0 2
UUID=yyyyyyyy-yyyy-yyyy-yyyy-yyyyyyyyyyyy /mnt/disk2 xfs defaults,noatime 0 2
UUID=zzzzzzzz-zzzz-zzzz-zzzz-zzzzzzzzzzzz /mnt/disk3 xfs defaults,noatime 0 2
UUID=aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa /mnt/disk4 xfs defaults,noatime 0 2
UUID=bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb /mnt/disk5 xfs defaults,noatime 0 2

# Parity disk (Btrfs)
UUID=cccccccc-cccc-cccc-cccc-cccccccccccc /mnt/parity btrfs defaults,noatime,compress=no,autodefrag 0 2
```

Reload systemd and test mounts:

```bash
sudo systemctl daemon-reload
sudo mount -a
df -h | grep -E 'disk|parity|pool'
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

## Software Installation

### Install SnapRAID and mergerfs

```bash
sudo apt update
sudo apt install snapraid -y
```

Install latest mergerfs:

```bash
cd /tmp
# Check https://github.com/trapexit/mergerfs/releases for latest Ubuntu 26.04 .deb
wget https://github.com/trapexit/mergerfs/releases/download/2.41.1/mergerfs_2.41.1.ubuntu-noble_amd64.deb
sudo dpkg -i mergerfs_*.deb
mergerfs -V
```

## Pool Configuration

Add the following line to `/etc/fstab`:

```conf
/mnt/disk* /mnt/pool fuse.mergerfs defaults,nonempty,allow_other,use_ino,cache.files=off,moveonenospc=true,dropcacheonclose=true,minfreespace=20G,category.create=epmfs,fsname=mergerfs,x-systemd.requires-mounts-for=/mnt/disk1,x-systemd.requires-mounts-for=/mnt/disk2,x-systemd.requires-mounts-for=/mnt/disk3,x-systemd.requires-mounts-for=/mnt/disk4,x-systemd.requires-mounts-for=/mnt/disk5 0 0
```

Reload systemd and mount:

```bash
sudo systemctl daemon-reload
sudo mount -a
ls /mnt/pool
```

### mergerfs Policy Reference

The `category.create` option controls where new files and directories are created.

**Default policy: `epmfs` (recommended for media/NAS)**
- **epmfs** = existing-path most-free-space
  - Preserves full directory path when possible.
  - Picks disk with most free space when path exists on multiple disks.
  - Falls back to most-free-space when path does not exist.

**Alternative policies:**
- **eplfs**: existing-path least-free-space (prefers disk with least free space)
- **pfrd**: percentage-free random distribution
- **ff**: first-found (fastest; creates on first disk with space)
- **mfs**: most-free-space (always picks disk with most free space)
- **rand**: random among disks with sufficient space
- **lfs/lus**: least-free-space / least-used-space

To change policy:
1. Edit the mergerfs line in `/etc/fstab`.
2. Run `sudo systemctl daemon-reload && sudo mount -a`.
3. Existing files are unaffected; only new creations follow the new policy.

Reference: [mergerfs Policy Descriptions](https://github.com/trapexit/mergerfs#policy-descriptions)

## SnapRAID Configuration

```bash
sudo nano /etc/snapraid.conf
```

Configuration file:

```conf
# Parity
parity /mnt/parity/snapraid.parity

# Content files
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

Initial sync:

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
```

**Note**: The parity disk is formatted as Btrfs for future snapshot-based replication. The disk is ready whenever needed.