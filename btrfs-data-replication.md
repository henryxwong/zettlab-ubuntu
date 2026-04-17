# Btrfs /data Subvolume + btrbk Snapshot Replication Guide

> Complete guide for the Zettlab D6/D8 Ultra NAS running Ubuntu 26.04 Server.  
> Creates a dedicated Btrfs subvolume at `/data` and sets up automatic daily incremental snapshot replication to the Btrfs parity disk (`/mnt/parity/replicas/data`).

**Compatibility**  
Tested with the official [storage-mergerfs-snapraid.md](storage-mergerfs-snapraid.md) setup.  
Snapshots are stored **outside** the SnapRAID parity file, so they do not interfere with your mergerfs pool.

**Retention policy**  
- Local snapshots: keep 14 days (minimum 2 days)  
- On parity drive: keep **30 daily + 8 weekly + 12 monthly**

---

## Overview

- `/data` is a dedicated Btrfs subvolume.  
- `btrbk` automatically creates read-only snapshots and sends them **incrementally** to the parity drive.  
- First run = full send. Subsequent runs = delta (very fast).  
- No extra fstab entries or mount changes required.

---

## Prerequisites

- Ubuntu 26.04 Server installed and fully updated  
- Root filesystem is Btrfs (`/dev/nvme1n1p2` or similar)  
- `/mnt/parity` is already mounted (from the mergerfs + SnapRAID guide)  
- Full backup of any existing data you want to keep  

---

## Step 1: Create the /data Subvolume

```bash
# Create the subvolume (safe to run even if it already exists)
sudo btrfs subvolume create /data 2>/dev/null || echo "/data subvolume already exists"

# Create directory for local snapshots
sudo mkdir -p /data/.snapshots

# Set permissions for the current user
sudo chown -R $USER:$USER /data
```

**Verify:**

```bash
sudo btrfs subvolume list -t /
ls -ld /data
sudo btrfs subvolume show /data
```

---

## Step 2: Install btrbk

```bash
sudo apt update
sudo apt install btrbk -y
```

---

## Step 3: Create the receive directory on the parity disk

```bash
sudo mkdir -p /mnt/parity/replicas/data
```

---

## Step 4: Create the btrbk configuration

```bash
sudo mkdir -p /etc/btrbk
sudo nano /etc/btrbk/btrbk.conf
```

**Paste the complete configuration below:**

```conf
# =============================================
# btrbk configuration for Zettlab D6/D8 Ultra
# /data subvolume → /mnt/parity/replicas/data
# =============================================

# Global retention settings
snapshot_preserve_min   2d
snapshot_preserve       14d          # keep daily snapshots locally for 14 days

target_preserve_min     2d
target_preserve         30d 8w 12m   # 30 daily + 8 weekly + 12 monthly on parity drive

# Source: treat /data as the volume root (correct snapshot_dir resolution)
volume /data
  subvolume .
    snapshot_dir            .snapshots          # local snapshots stored inside /data
    target                  /mnt/parity/replicas/data
```

Save and exit (`Ctrl`+`O` → `Enter` → `Ctrl`+`X`).

---

## Step 5: Test the replication

```bash
# Dry-run first
sudo btrbk dryrun

# Real first run (creates snapshot + full send)
sudo btrbk run
```

**Verify results:**

```bash
# Local snapshot
ls -l /data/.snapshots/

# Received copy on parity drive
ls -l /mnt/parity/replicas/data/

# Status overview
sudo btrbk stats
```

---

## Step 6: Set up automatic daily replication (consistent with SnapRAID)

Create a small wrapper script so the cron job is consistent with the SnapRAID maintenance script.

```bash
sudo nano /usr/local/bin/btrbk-run.sh
```

**Paste the following content:**

```bash
#!/bin/bash
# btrbk wrapper script for scheduled execution

LOG=/var/log/btrbk.log
echo "=== btrbk replication started at $(date) ===" >> $LOG
/usr/bin/btrbk run >> $LOG 2>&1
echo "=== btrbk replication finished at $(date) ===" >> $LOG
```

Make the script executable:

```bash
sudo chmod +x /usr/local/bin/btrbk-run.sh
```

Now add the cron job:

```bash
sudo crontab -e
```

Add this line (runs at 04:00 every day, one hour after SnapRAID):

```
0 4 * * * /usr/local/bin/btrbk-run.sh
```

Save and exit the editor.

Verify the cron job:

```bash
sudo crontab -l
```

---

## Maintenance & Useful Commands

### View statistics and list snapshots
```bash
sudo btrbk stats
sudo btrbk list
```

### Manually run replication
```bash
sudo btrbk run
```

### Clean old snapshots
```bash
sudo btrbk clean
```

### Check logs
```bash
cat /var/log/btrbk.log
sudo journalctl -u btrbk -e
```

### Edit retention later
Edit `/etc/btrbk/btrbk.conf` and run `sudo btrbk run`.

---

## Step 7: How to Restore from a Replica (Emergency)

1. List available replicas:
   ```bash
   ls /mnt/parity/replicas/data/
   ```

2. Restore a specific snapshot (example):
   ```bash
   # Restore to a new subvolume
   sudo btrfs receive -f /mnt/parity/replicas/data/@data-YYYY-MM-DD_... /data-restored
   ```

---

## Final Notes

- Your existing SnapRAID + mergerfs setup remains **completely unchanged**.
- Snapshots live in `/mnt/parity/replicas/data` — they are **not** part of the SnapRAID parity file.
- Store all important data inside `/data` for automatic protection.
- Replication is incremental and very fast after the first run.