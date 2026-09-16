# Storage Pool Setup: mergerfs + SnapRAID

> Configures XFS data disks with Btrfs parity disk, using mergerfs for pooling and SnapRAID for backup on Zettlab D6/D8 Ultra NAS.

## Disk Layout Assumptions

This guide uses a 5-data + 1-parity layout as a running example. Adjust the counts, device names, and mount points to your own hardware — mergerfs and SnapRAID scale from 2 data disks up to many, and the parity disk must simply be at least as large as your largest data disk.

| Disks          | Role              | Filesystem |
|----------------|-------------------|------------|
| 5× data disks (e.g. `/dev/sda`–`/dev/sde`) | Data           | XFS        |
| 1× parity disk (e.g. `/dev/sdf`)           | Dedicated parity | Btrfs      |

> **Important**: Device names (`/dev/sdX`) are not persistent. Always verify with `lsblk` and use UUIDs in `/etc/fstab`.

## Directory Structure

| Mount Point     | Purpose                          |
|-----------------|----------------------------------|
| `/mnt/disk1`–`/mnt/disk5` | Individual data disks       |
| `/mnt/parity`   | Btrfs parity disk                |
| `/mnt/pool`     | mergerfs pooled storage          |

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

Replace the device list with your own data disks. Do **not** format the parity disk here — use it in the parity step below.

```bash
# Data disks (XFS) — example for 5 disks named sda..sde
for dev in sda sdb sdc sdd sde; do
    sudo wipefs -af /dev/$dev
    sudo parted -s /dev/$dev mklabel gpt
    sudo parted -s /dev/$dev mkpart primary 0% 100%
    sudo mkfs.xfs -f -L disk${dev: -1} /dev/${dev}1
done

# Parity disk (Btrfs) — example device sdf
sudo wipefs -af /dev/sdf
sudo parted -s /dev/sdf mklabel gpt
sudo parted -s /dev/sdf mkpart primary 0% 100%
sudo mkfs.btrfs -f -L parity /dev/sdf1
```

### Step 3: Create Mount Points

```bash
# Example for 5 data disks
sudo mkdir -p /mnt/disk{1..5} /mnt/parity /mnt/pool
```

### Step 4: Configure Filesystem Mounts

Obtain UUIDs:

```bash
sudo blkid
```

Add entries to `/etc/fstab`:

```bash
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

### Install SnapRAID

> **Note**: Ubuntu's LTS repositories freeze the SnapRAID version at release time — 26.04 LTS (resolute) ships 13.0, while the next development release (26.10) already carries 14.9; LTS users won't see 14.x during this release's life. SnapRAID 14 adds useful features for mergerfs users: `.snapraidignore` files for per-directory excludes, `**` recursive globbing, a 'relocated' file state that cleanly detects files moved between disks, and support for the optional SnapRAID daemon.

Install the current official release from GitHub instead of apt:

```bash
# Check https://github.com/amadvance/snapraid/releases for the latest version,
# then download the .deb for your architecture:
cd /tmp
wget https://github.com/amadvance/snapraid/releases/download/v14.9/snapraid_14.9-1_amd64.deb
sha256sum snapraid_14.9-1_amd64.deb   # compare against the digest on the release page
sudo dpkg -i snapraid_14.9-1_amd64.deb
snapraid --version
```

If you installed snapraid via apt previously, `dpkg -i` upgrades it in place; just remember that future `apt upgrade` attempts may try to downgrade it — you can `sudo apt-mark hold snapraid` after installing.

> **Upgrading an existing array**: the content file format is updated on the first 14.x `sync`. Back up your content files (`/var/snapraid.content` and the copies on each data disk) before upgrading — downgrading afterwards is not guaranteed.

### Install mergerfs

Check the latest release at: https://github.com/trapexit/mergerfs/releases

Ubuntu's repository version also lags (26.04 ships 2.40.x while upstream is 2.42.x), so the official .deb from GitHub releases is recommended on any release:

```bash
# Check the releases page for the latest version and your Ubuntu codename
cd /tmp
wget https://github.com/trapexit/mergerfs/releases/download/<VERSION>/mergerfs_<VERSION>.ubuntu-<CODENAME>_amd64.deb
sudo dpkg -i mergerfs_*.deb
mergerfs -V
```

Plain `sudo apt install mergerfs` works if you don't mind the older version.

> **Upgrading from ≤2.40.x**: mergerfs 2.41 changed the default `category.create` policy from `epmfs` to `pfrd`. The fstab line in this guide sets `category.create=epmfs` explicitly, so behavior stays the same either way.

## Pool Configuration

### Configure mergerfs in fstab

Add this line to `/etc/fstab` (example for 5 data disks; add one `x-systemd.requires-mounts-for=` per disk):

```bash
/mnt/disk* /mnt/pool fuse.mergerfs defaults,nonempty,allow_other,use_ino,cache.files=off,moveonenospc=true,dropcacheonclose=true,minfreespace=20G,category.create=epmfs,fsname=mergerfs,x-systemd.requires-mounts-for=/mnt/disk1,x-systemd.requires-mounts-for=/mnt/disk2,x-systemd.requires-mounts-for=/mnt/disk3,x-systemd.requires-mounts-for=/mnt/disk4,x-systemd.requires-mounts-for=/mnt/disk5 0 0
```

### Mount the Pool

```bash
sudo systemctl daemon-reload
sudo mount -a
ls /mnt/pool
```

### mergerfs Policy Reference

| Policy | Description                              |
|--------|------------------------------------------|
| `epmfs` (default) | Existing-path most-free-space           |
| `eplfs` | Existing-path least-free-space           |
| `mfs`   | Most-free-space                          |
| `ff`    | First-found                              |

To change policy, edit the line in `/etc/fstab` and run `sudo mount -a`.

## Parity File Setup

```bash
sudo mount -a

# Create parity file on Btrfs root
sudo touch /mnt/parity/snapraid.parity

# Disable CoW on parity file
sudo chattr +C /mnt/parity/snapraid.parity

# Verify
lsattr /mnt/parity/snapraid.parity   # should show "C"
```

## SnapRAID Configuration

```bash
sudo nano /etc/snapraid.conf
```

**Configuration file content** (example for 5 data disks — keep one `content` line per parity plus at least one extra, each on a different physical disk):

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

# Optional (SnapRAID 14+): also report SMART/spin status of disks
# outside the array, e.g. the boot disk, in 'smart' and 'probe'
extra boot /

# Excludes
exclude /lost+found/
exclude *.unrecoverable
exclude /tmp/
exclude .snapraid.content

autosave 1000
```

> SnapRAID 14 also supports `.snapraidignore` files placed inside the array (gitignore-style, per-directory excludes) and `**` recursive globbing in `exclude` patterns — handy without editing the global config.

### Initial Sync

```bash
sudo snapraid -c /etc/snapraid.conf diff
sudo snapraid -c /etc/snapraid.conf sync
```

> **Safety stops**: SnapRAID deliberately halts an unattended `sync` when something looks wrong — a disk whose recorded files all vanished (`-E`, usually an unmounted disk), files truncated to zero (`-Z`), or changed disk UUIDs (`-U`). These are features: investigate and fix the mount before forcing. Note that a *newly added* disk records zero files until its first sync, and the content file on it is only created after that first successful `sync`.

## Maintenance and Automation

### Create Maintenance Script

```bash
sudo nano /usr/local/bin/snapraid-maintenance.sh
```

**Script content:**

```bash
#!/bin/bash
LOG=/var/log/snapraid.log
echo "=== SnapRAID maintenance started at $(date) ===" >> $LOG
snapraid -c /etc/snapraid.conf sync >> $LOG 2>&1
snapraid -c /etc/snapraid.conf scrub -p 4 -o 0 >> $LOG 2>&1
echo "=== SnapRAID maintenance finished at $(date) ===" >> $LOG
```

Make executable:

```bash
sudo chmod +x /usr/local/bin/snapraid-maintenance.sh
```

### Schedule Maintenance (cron)

```bash
sudo crontab -e
```

Add:

```cron
0 3 * * * /usr/local/bin/snapraid-maintenance.sh
```

## Known Issues & Limitations

> **Important**: mergerfs is known to have stability issues, especially when combined with Samba. The following problems have been reported by multiple users.

### Documented Problems

| Issue                          | Severity | Description                                                                 | Mitigation Used |
|--------------------------------|----------|-----------------------------------------------------------------------------|-----------------|
| **SMB rename/create failures** | Medium   | Creating or renaming folders/files over Samba can fail or behave incorrectly | `oplocks = no` |
| **Long-term segfaults**        | Medium   | Occasional crashes after running for days or weeks                          | None (monitor logs) |
| **Directory listing performance** | Medium | Slow or broken listings, especially with macOS clients                     | `oplocks = no`, `stat cache = yes` |
| **Metadata / VFS conflicts**   | Low–Medium | `fruit` module + mergerfs can cause unexpected behavior                     | Current Samba config |
| **Caching edge cases**         | Low      | Problems with certain cache-related options under heavy load                | `cache.files=off`, `dropcacheonclose=true` |

### Current Mitigations in This Guide

- `oplocks = no` and `level2 oplocks = no` on `[data]` and `[pool]`
- `smb encrypt = desired`
- `cache.files=off`
- `dropcacheonclose=true`
- `minfreespace=20G`
- `stat cache = yes` in global Samba config

These settings significantly reduce (but do not completely eliminate) the known issues.

### Recommendation

If you experience frequent problems with file operations or random crashes, consider monitoring mergerfs logs. The pool is mounted via `/etc/fstab`, so there is no dedicated service to restart — remount instead:

```bash
# Only safe when nothing is actively using the pool (check with: sudo lsof +f -- /mnt/pool)
sudo fusermount3 -u /mnt/pool && sudo mount /mnt/pool
```

For maximum stability, some users eventually move away from mergerfs in favor of native ZFS or simple bind mounts.