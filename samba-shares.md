# Samba Shares: Home + /data + mergerfs Pool

> Complete guide for the Zettlab D6/D8 Ultra NAS running Ubuntu 26.04 Server.  
> Exposes your home directory, the protected `/data` Btrfs subvolume, and the `/mnt/pool` mergerfs storage pool as Samba shares.  
> Uses your existing Linux password.

**Compatibility**  
Tested with [storage-mergerfs-snapraid.md](storage-mergerfs-snapraid.md) and [btrfs-data-replication.md](btrfs-data-replication.md).

---

## Overview

- `[homes]` → personal home directory  
- `[data]` → Btrfs subvolume with automatic snapshot replication  
- `[pool]` → mergerfs pooled storage (SnapRAID protected)  

All shares are read/write for your user only.

**macOS users**  
This guide now includes full `.DS_Store` prevention (both client-side and server-side) and modern `fruit` VFS settings for optimal Finder performance, metadata handling, and zero macOS clutter on your NAS.

**Important stability note for Zettlab D6/D8 Ultra:**  
Use `smb encrypt = desired` (not `required`). This significantly improves stability and greatly reduces movie stuttering and SSH drops during sustained playback **and file listing** while remaining compatible with macOS.

---

## Prerequisites

- Ubuntu 26.04 Server installed and updated  
- `/data` subvolume and mergerfs pool configured  
- Regular (non-root) user account

---

## Step 1: Install Samba and smbclient

```bash
sudo apt update
sudo apt install samba smbclient -y
```

---

## Step 2: Create the Samba configuration

```bash
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.bak
sudo nano /etc/samba/smb.conf
```

Replace the entire file with the following updated configuration:

```conf
# =============================================
# Samba configuration for Zettlab D6/D8 Ultra
# Ubuntu 26.04 – single-user setup
# =============================================

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
   passwd chat = *Enter\snew\s*\spassword:* %n\n *Retype\snew\s*\spassword:* %n\n *password\supdated\ssuccessfully*

   # Modern SMB3 + encryption negotiation (required for macOS stability)
   server min protocol = SMB3
   server max protocol = SMB3
   smb encrypt = desired

   # Performance for mergerfs/XFS + Realtek RTL8127 stability
   socket options = TCP_NODELAY
   aio read size = 8192
   aio write size = 8192
   read raw = yes
   write raw = yes
   use sendfile = yes

   # === Modern macOS compatibility (fruit VFS) ===
   vfs objects = fruit streams_xattr
   fruit:metadata = stream
   fruit:model = MacSamba
   fruit:posix_rename = yes
   fruit:zero_file_id = yes
   fruit:wipe_intentionally_left_blank_rfork = yes
   fruit:delete_empty_adfiles = yes
   fruit:nfs_aces = no

   # Stop macOS clutter (.DS_Store and AppleDouble files) at the server level
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

   # Reduce metadata storms (important for file listing stability)
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

   # Reduce metadata storms (important for file listing stability)
   oplocks = no
   level2 oplocks = no
```

---

## Step 3: Add your user to Samba

```bash
sudo smbpasswd -a $(whoami)
```

Enter your current Linux password twice when prompted.

---

## Step 4: Restart and enable Samba

```bash
sudo systemctl restart smbd
sudo systemctl enable smbd
```

---

## Step 5: Firewall (if ufw is enabled)

```bash
sudo ufw allow samba
sudo ufw reload
```

---

## Step 6: Verify

```bash
sudo systemctl status smbd
smbclient -L localhost -U $(whoami)
sudo testparm
```

You should see the shares: `homes`, `data`, and `pool`.

---

## macOS Optimization & .DS_Store Prevention

### Client-side (on every Mac that connects)
This is the most effective way to stop macOS from creating `.DS_Store` files:

1. Open **Terminal** on your Mac and run:
   ```bash
   defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool TRUE
   ```

2. Force Finder to reload the setting:
   ```bash
   killall Finder
   ```

3. **Verify the setting**:
   ```bash
   defaults read com.apple.desktopservices DSDontWriteNetworkStores
   ```
   It should return `1`.

### Server-side protection (already included in the config above)
The new `veto files` + `delete veto files` rules will automatically block and delete any `.DS_Store` or `._*` files that still slip through.

### One-time cleanup (run after updating Samba)
```bash
sudo find /mnt/pool -name ".DS_Store" -delete
sudo find /mnt/pool -name "._*" -delete
sudo find /data -name ".DS_Store" -delete 2>/dev/null || true
```

---

## Connect from Client Devices

**macOS**  
Finder → Go → Connect to Server → `smb://ZETTLABNAS` or `smb://IP-OF-NAS`

**Windows**  
File Explorer → `\\ZETTLABNAS` or `\\IP-OF-NAS`

**Linux**
```bash
smbclient //ZETTLABNAS/data -U $(whoami)
```

---

## Maintenance

### Restart Samba
```bash
sudo systemctl restart smbd
```

### Check connected users
```bash
sudo smbstatus
```

### View logs
```bash
sudo journalctl -u smbd -e
```

### Password changes
After running `passwd`, also update Samba:
```bash
sudo smbpasswd -a $(whoami)
```

---

## Notes

- Store important data in `/data` (btrbk replication) or `/mnt/pool` (SnapRAID).
- SnapRAID and btrbk schedules are unaffected.
- The configuration is tuned specifically for Realtek RTL8127 stability on this hardware.
- For remote access, use WireGuard or VPN.
- The `fruit` VFS module + veto rules ensure a clean, macOS-friendly experience with **zero `.DS_Store` pollution**.
- After applying the changes, test by creating a new folder from your Mac and running `find /mnt/pool -name ".DS_Store" -mmin -5` on the NAS — it should return nothing.