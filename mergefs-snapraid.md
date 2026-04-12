# Setting up mergerfs + SnapRAID on Zettlab D6/D8 Ultra (Ubuntu 26.04 Server)

**Disk Assumption**  
This guide assumes:
- `/dev/sda` to `/dev/sde` are your **5 data disks**
- `/dev/sdf` is your dedicated **parity disk**

**Critical warning**: Device names (`/dev/sdX`) are **not persistent**. They can change after reboots, kernel updates, or SATA reordering. Always verify with `lsblk` and use **UUIDs** (or `/dev/disk/by-id/`) in `/etc/fstab` and `snapraid.conf`. This assumption is only for initial identification.

**Filesystem Choice (Important!)**  
**Recommended / default in this guide**:
- **Data disks** (`/dev/sda`–`/dev/sde`): **XFS** (best performance + no 16 TB file-size limit)
- **Parity disk** (`/dev/sdf`): **Btrfs** (allows cheap snapshot-based replication with `btrfs send | receive`)

You are **free to use any filesystem** you prefer:
- `ext4` works great on data disks (and parity) if your parity file will stay under 16 TB.
- `XFS` on parity is simpler and slightly faster if you don’t need Btrfs snapshots.
- `Btrfs` on data disks is possible but not recommended (CoW overhead hurts SnapRAID performance).

The steps below follow the recommended/default setup (XFS data + Btrfs parity). If you choose differently, adjust the formatting and mount options accordingly.

**Recommended Directory Structure**
- `/mnt/disk1` – `/mnt/disk5`: Individual data disks
- `/mnt/parity`: Parity disk
- `/mnt/pool`: mergerfs pooled mount point (this is what you will use daily)

## Prerequisites
- Ubuntu 26.04 Server installed and updated (see [ubuntu-installation.md](ubuntu-installation.md))
- Fan control module installed and running (see [fan-control.md](fan-control.md))
- Disks are detected (`lsblk`) and you have a complete backup

## Step 1: Prepare the Disks

1. Identify your disks (double-check!):
   ```bash
   lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,UUID
   sudo ls /dev/disk/by-id/
   ```

2. **(Destructive)** Format disks:
   ```bash
   # === DATA DISKS (XFS – recommended) ===
   for dev in sda sdb sdc sdd sde; do
       sudo wipefs -af /dev/$dev
       sudo parted -s /dev/$dev mklabel gpt
       sudo parted -s /dev/$dev mkpart primary 0% 100%
       sudo mkfs.xfs -f -L disk${dev: -1} /dev/${dev}1
   done

   # === PARITY DISK (Btrfs – recommended for snapshots) ===
   sudo wipefs -af /dev/sdf
   sudo parted -s /dev/sdf mklabel gpt
   sudo parted -s /dev/sdf mkpart primary 0% 100%
   sudo mkfs.btrfs -f -L parity /dev/sdf1
   ```

   *If you prefer ext4 on data disks or XFS on parity, replace the `mkfs.*` commands accordingly.*

3. Create mount points:
   ```bash
   sudo mkdir -p /mnt/disk{1..5} /mnt/parity /mnt/pool
   ```

4. Get UUIDs:
   ```bash
   sudo blkid
   ```

5. Add mounts to `/etc/fstab` (use UUIDs!):
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

   Reload systemd and test mounts:
   ```bash
   sudo systemctl daemon-reload
   sudo mount -a
   df -h | grep -E 'disk|parity|pool'
   ```

## Step 2: Prepare Parity File (Btrfs)

```bash
sudo mount -a

# Create the parity file directly on the Btrfs root
sudo touch /mnt/parity/snapraid.parity

# CRITICAL: Disable CoW on the parity file (prevents fragmentation)
sudo chattr +C /mnt/parity/snapraid.parity

# Verify
lsattr /mnt/parity/snapraid.parity   # should show "C"
```

## Step 3: Install mergerfs and SnapRAID

```bash
sudo apt update
sudo apt install snapraid -y
```

**Install latest mergerfs**:
```bash
cd /tmp
# Check https://github.com/trapexit/mergerfs/releases for the latest Ubuntu 26.04 .deb
wget https://github.com/trapexit/mergerfs/releases/download/2.41.1/mergerfs_2.41.1.ubuntu-noble_amd64.deb
sudo dpkg -i mergerfs_*.deb
mergerfs -V
```

## Step 4: Configure mergerfs Pool

Add this line to the end of `/etc/fstab`:
```
/mnt/disk* /mnt/pool fuse.mergerfs defaults,nonempty,allow_other,use_ino,cache.files=off,moveonenospc=true,dropcacheonclose=true,minfreespace=20G,category.create=pfrd,fsname=mergerfs,x-systemd.requires-mounts-for=/mnt/disk1,x-systemd.requires-mounts-for=/mnt/disk2,x-systemd.requires-mounts-for=/mnt/disk3,x-systemd.requires-mounts-for=/mnt/disk4,x-systemd.requires-mounts-for=/mnt/disk5 0 0
```

Reload systemd and mount the pool:
```bash
sudo systemctl daemon-reload
sudo mount -a
ls /mnt/pool
```

### Mergerfs Policy Reference (Different `category.create` types)
mergerfs uses **policies** to decide where new files and directories are created. The option `category.create=XXX` controls this behavior.

**Default in this guide**: `pfrd` (recommended for media/NAS + SnapRAID)
- **pfrd** = path-preserving + percentage-free random distribution
    - Preserves the full directory path on the chosen disk when possible.
    - Distributes new top-level folders across disks using a weighted random algorithm based on free space percentage.
    - Good balance of directory structure + even disk usage. Ideal for movie/TV libraries.

**Common alternative policies** (change `category.create=XXX` in the fstab line and run `sudo mount -a`):
- **ff** (first-found): Fastest. Creates on the first disk with enough space. Can fill one disk quickly.
- **mfs** (most-free-space): Always creates on the disk with the most free space. Simple and even usage.
- **epmfs** (existing-path most-free-space): Tries to keep files in the same path as existing data; falls back to most-free-space.
- **eplfs** (existing-path least-free-space): Similar to epmfs but prefers the disk with least free space (for filling disks evenly).
- **rand** (random): Pure random selection among disks with enough space.
- **lfs** / **lus** (least-free-space / least-used-space): Useful for specific balancing needs.

To change the policy later:
1. Edit the mergerfs line in `/etc/fstab`.
2. Run `sudo systemctl daemon-reload && sudo mount -a`.
3. Existing files are unaffected — only new creations follow the new policy.

For full policy list and details see the official mergerfs documentation:  
https://github.com/trapexit/mergerfs#policy-descriptions

## Step 5: Configure SnapRAID

```bash
sudo nano /etc/snapraid.conf
```

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

First sync:
```bash
sudo snapraid -c /etc/snapraid.conf diff
sudo snapraid -c /etc/snapraid.conf sync
```

## Step 6: Maintenance & Automation

Create maintenance script:
```bash
sudo nano /usr/local/bin/snapraid-maintenance.sh
```

```bash
#!/bin/bash
LOG=/var/log/snapraid.log
echo "=== SnapRAID maintenance started at $(date) ===" >> $LOG
snapraid -c /etc/snapraid.conf sync >> $LOG 2>&1
snapraid -c /etc/snapraid.conf scrub -p 8 -o 0 >> $LOG 2>&1
echo "=== SnapRAID maintenance finished at $(date) ===" >> $LOG
```

```bash
sudo chmod +x /usr/local/bin/snapraid-maintenance.sh
sudo crontab -e
```

Add to cron:
```
0 3 * * * /usr/local/bin/snapraid-maintenance.sh
```

**Note on snapshots**: The parity disk is formatted as Btrfs so you can later create snapshots for replication (e.g. from NVMe drive). The parity disk is ready whenever you need it.

## Next Steps
- Share `/mnt/pool` via Samba/NFS.
- Install Docker/Portainer and bind-mount apps to the pool.
- Monitor SMART and temperatures.

**Official references**:
- [mergerfs GitHub](https://github.com/trapexit/mergerfs)
- [SnapRAID official](https://www.snapraid.it/)

**Zettlab-specific note**: With the 45 W / 93 W CPU power limit, large initial syncs or scrubs will take longer — ensure your `zettlab_d8_fans` service is active.