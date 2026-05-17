# Btrfs /data Subvolume + btrbk Snapshot Replication

> Creates a dedicated Btrfs subvolume at `/data` and sets up automatic daily incremental snapshot replication to the Btrfs parity disk (`/mnt/parity/replicas/data`).

## Compatibility

Tested with the official [storage-mergerfs-snapraid.md](storage-mergerfs-snapraid.md) setup. Snapshots are stored **outside** the SnapRAID parity file.

## Retention Policy

- Local snapshots: keep 14 days (minimum 2 days)
- On parity drive: keep **30 daily + 8 weekly + 12 monthly**

## Overview

- `/data` is a dedicated Btrfs subvolume
- `btrbk` automatically creates read-only snapshots and sends them **incrementally** to the parity drive
- First run = full send. Subsequent runs = delta (very fast)
- No extra fstab entries or mount changes required

## Prerequisites

- Ubuntu 26.04 Server installed and fully updated
- Root filesystem is Btrfs
- `/mnt/parity` is already mounted
- Full backup of any existing data

## Step 1: Create the /data Subvolume

```bash
# Create the subvolume
sudo btrfs subvolume create /data 2>/dev/null || echo "/data subvolume already exists"

# Create directory for local snapshots
sudo mkdir -p /data/.snapshots

# Set permissions
sudo chown -R $USER:$USER /data
```

**Verify:**

```bash
sudo btrfs subvolume list -t /
ls -ld /data
sudo btrfs subvolume show /data
```

## Step 2: Install btrbk

```bash
sudo apt update
sudo apt install btrbk -y
```

## Step 3: Create Receive Directory

```bash
sudo mkdir -p /mnt/parity/replicas/data
```

## Step 4: Create btrbk Configuration

```bash
sudo mkdir -p /etc/btrbk
sudo nano /etc/btrbk/btrbk.conf
```

**Paste the following configuration:**

```conf
# btrbk configuration for Zettlab D6/D8 Ultra
# /data subvolume → /mnt/parity/replicas/data

# Global retention settings
snapshot_preserve_min   2d
snapshot_preserve       14d          # keep daily snapshots locally for 14 days

target_preserve_min     2d
target_preserve         30d 8w 12m   # 30 daily + 8 weekly + 12 monthly on parity

# Source
volume /data
  subvolume .
    snapshot_dir            .snapshots
    target                  /mnt/parity/replicas/data
```

## Step 5: Test the Replication

```bash
# Dry-run first
sudo btrbk dryrun

# Real first run (creates snapshot + full send)
sudo btrbk run
```

**Verify results:**

```bash
ls -l /data/.snapshots/
ls -l /mnt/parity/replicas/data/
sudo btrbk stats
```

## Step 6: Enable Automatic Daily Replication

The `btrbk` package provides a ready-to-use systemd timer.

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now btrbk.timer
```

**Verify the timer:**

```bash
systemctl list-timers | grep btrbk
systemctl status btrbk.timer
```

## Maintenance Commands

```bash
sudo btrbk stats          # View statistics
sudo btrbk list           # List snapshots
sudo btrbk run            # Manually run replication
sudo btrbk clean          # Clean old snapshots
sudo journalctl -u btrbk.service -e
```

## How to Restore from a Replica (Emergency)

1. List available replicas:

   ```bash
   ls /mnt/parity/replicas/data/
   ```

2. Restore a specific snapshot:

   ```bash
   sudo btrfs receive -f /mnt/parity/replicas/data/data.2026XXXX /data-restored
   ```

## Final Notes

- Your existing SnapRAID + mergerfs setup remains **completely unchanged**
- Snapshots live in `/mnt/parity/replicas/data` — they are **not** part of the SnapRAID parity file
- Store all important data inside `/data` for automatic protection
- Replication is incremental and very fast after the first run
- The packaged `btrbk.timer` provides reliable daily execution