# Samba Shares: Home + /data + mergerfs Pool

> Exposes your home directory, the protected `/data` Btrfs subvolume, and the `/mnt/pool` mergerfs storage pool as Samba shares using your existing Linux password.

## Compatibility

Tested with [storage-mergerfs-snapraid.md](storage-mergerfs-snapraid.md) and [btrfs-data-replication.md](btrfs-data-replication.md).

## Overview

- `[homes]` → personal home directory
- `[data]` → Btrfs subvolume with automatic snapshot replication
- `[pool]` → mergerfs pooled storage (SnapRAID protected)

All shares are read/write for your user only.

**macOS users**: This guide includes full `.DS_Store` prevention and modern `fruit` VFS settings.

**Important stability note**: Use `smb encrypt = desired` (not `required`). This significantly improves stability on Zettlab hardware while remaining compatible with macOS.

## Prerequisites

- Ubuntu 26.04 Server installed and updated
- `/data` subvolume and mergerfs pool configured
- Regular (non-root) user account

## Step 1: Install Samba

```bash
sudo apt update
sudo apt install samba smbclient -y
```

## Step 2: Create Samba Configuration

```bash
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
sudo nano /etc/samba/smb.conf
```

Replace the entire file with the following configuration:

```conf
# Samba configuration for Zettlab D6/D8 Ultra
# Ubuntu 26.04 – single-user setup

[global]
   workgroup = WORKGROUP
   server string = Zettlab Ultra NAS
   netbios name = ZETTLABNAS
   security = user
   server role = standalone server
   map to guest = never
   obey pam restrictions = yes
   pam password change = yes

   # Sync Samba password changes back to Linux
   unix password sync = yes
   passwd program = /usr/bin/passwd %u
   passwd chat = *Enter\\snew\\s*\\spassword:* %n\\n *Retype\\snew\\s*\\spassword:* %n\\n *password\\supdated\\ssuccessfully*

   # Modern SMB3 + encryption negotiation
   server min protocol = SMB3
   server max protocol = SMB3
   smb encrypt = desired

   # Performance tuning
   socket options = TCP_NODELAY
   aio read size = 8192
   aio write size = 8192
   read raw = yes
   write raw = yes
   use sendfile = yes

   # Modern macOS compatibility (fruit VFS)
   vfs objects = fruit streams_xattr
   fruit:metadata = stream
   fruit:model = MacSamba
   fruit:posix_rename = yes
   fruit:zero_file_id = yes
   fruit:wipe_intentionally_left_blank_rfork = yes
   fruit:delete_empty_adfiles = yes
   fruit:nfs_aces = no

   # Stop macOS clutter (.DS_Store and AppleDouble files)
   veto files = /._*/.DS_Store/
   delete veto files = yes

   # Reduce metadata storms during directory listing
   stat cache = yes

# === Home directory ===
[homes]
   comment = Home Directories
   browseable = no
   read only = no
   create mask = 0644
   directory mask = 0755

# === /data share ===
[data]
   comment = Data (Btrfs with daily replication)
   path = /data
   browseable = yes
   read only = no
   create mask = 0644
   directory mask = 0755
   force user = %U
   force group = %U
   valid users = %U

   # Reduce metadata storms
   oplocks = no
   level2 oplocks = no

# === mergerfs pool share ===
[pool]
   comment = Storage Pool (mergerfs + SnapRAID)
   path = /mnt/pool
   browseable = yes
   read only = no
   create mask = 0644
   directory mask = 0755
   force user = %U
   force group = %U
   valid users = %U

   # Reduce metadata storms
   oplocks = no
   level2 oplocks = no
```

## Step 3: Add Your User to Samba

```bash
sudo smbpasswd -a $(whoami)
```

Enter your current Linux password twice when prompted.

## Step 4: Restart and Enable Samba

```bash
sudo systemctl restart smbd
sudo systemctl enable smbd
```

## Step 5: Firewall (if ufw is enabled)

```bash
sudo ufw allow samba
sudo ufw reload
```

## Step 6: Verify

```bash
sudo systemctl status smbd
smbclient -L localhost -U $(whoami)
sudo testparm
```

You should see the shares: `homes`, `data`, and `pool`.

## macOS Optimization & .DS_Store Prevention

### Client-side (on every Mac)

```bash
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool TRUE
killall Finder
```

**Verify:**

```bash
defaults read com.apple.desktopservices DSDontWriteNetworkStores
```

### Server-side Protection

Already included in the config above (`veto files` + `delete veto files`).

### One-time Cleanup

```bash
sudo find /mnt/pool -name ".DS_Store" -delete
sudo find /mnt/pool -name "._*" -delete
sudo find /data -name ".DS_Store" -delete 2>/dev/null || true
```

## Connect from Client Devices

| Platform | Connection String                          |
|----------|--------------------------------------------|
| macOS    | `smb://ZETTLABNAS` or `smb://IP-OF-NAS`    |
| Windows  | `\\ZETTLABNAS` or `\\IP-OF-NAS`            |
| Linux    | `smbclient //ZETTLABNAS/data -U $(whoami)` |

## Maintenance

```bash
sudo systemctl restart smbd          # Restart Samba
sudo smbstatus                       # Check connected users
sudo journalctl -u smbd -e           # View logs
sudo smbpasswd -a $(whoami)          # Update Samba password after passwd
```

## Notes

- Store important data in `/data` (btrbk replication) or `/mnt/pool` (SnapRAID)
- SnapRAID and btrbk schedules are unaffected
- The configuration is tuned for stability on this hardware
- For remote access, use WireGuard or VPN
- The `fruit` VFS module + veto rules ensure a clean, macOS-friendly experience with zero `.DS_Store` pollution