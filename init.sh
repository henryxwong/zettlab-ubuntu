#!/bin/bash

# Shutdown cleanup function to handle graceful termination
# This saves PM2 processes, backs up and exports the current crontab, and stops SSHD
cleanup() {
    echo "Received SIGTERM - saving PM2 and crontab before shutdown"
    pm2 save --force  # Save PM2 process list
    if [ -f "/root/crontab.txt" ]; then
        cp /root/crontab.txt /root/crontab.txt.bak  # Backup existing crontab.txt
    fi
    crontab -l > /root/crontab.txt  # Export current crontab to file
    kill -TERM $SSHD_PID  # Stop sshd gracefully
    wait $SSHD_PID  # Wait for sshd to exit
    exit 0
}

# Trap SIGTERM signal to trigger the cleanup function
trap 'cleanup' TERM

# Flag to track if cleanup is needed
need_cleanup=0

# Declare an array for packages to install
declare -a packages=()

# Handle Intel GPU drivers setup if missing (requires special repo handling)
if ! dpkg -l | grep -q intel-level-zero-gpu; then
    # Ensure tools for adding repo are available
    if ! command -v wget >/dev/null || ! command -v gpg >/dev/null; then
        apt-get update && apt-get install -y wget gpg-agent gnupg
        need_cleanup=1
    fi

    # Add Intel Graphics GPG key if missing
    if [ ! -f "/usr/share/keyrings/intel-graphics.gpg" ]; then
        wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | \
        gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg
    fi

    # Add Intel GPU repository for Ubuntu 24.04 (noble) if missing
    if [ ! -f "/etc/apt/sources.list.d/intel-gpu-noble.list" ]; then
        echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu noble client" | \
        tee /etc/apt/sources.list.d/intel-gpu-noble.list
    fi

    # Add GPU packages to the install list
    packages+=(libze1 intel-level-zero-gpu intel-opencl-icd)
fi

# Check for missing base packages and add to install list
if ! command -v git >/dev/null || ! command -v curl >/dev/null || ! command -v npm >/dev/null || ! command -v sshd >/dev/null; then
    packages+=(python3 python3-pip git openssh-server curl nodejs npm)
fi

# Check for Neovim and add to install list
if ! command -v nvim >/dev/null; then
    packages+=(neovim)
fi

# Check for cron and add to install list
if ! command -v crontab >/dev/null; then
    packages+=(cron)
fi

# Check for rsync and add to install list
if ! command -v rsync >/dev/null; then
    packages+=(rsync)
fi

# Perform a single apt update and install if any packages are needed
if [ ${#packages[@]} -gt 0 ]; then
    apt-get update && apt-get install -y "${packages[@]}"
    need_cleanup=1
fi

# Perform cleanup if any apt operations were run
if [ $need_cleanup -eq 1 ]; then
    rm -rf /var/lib/apt/lists/*
fi

# Install UV if missing
# Checks for the executable directly to ensure idempotency without relying on PATH
if [ ! -x "/root/.local/bin/uv" ]; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    if ! grep -q 'source /root/.local/bin/env' /root/.bashrc; then
        echo 'source /root/.local/bin/env' >> /root/.bashrc
    fi
fi

# Install PM2 if missing
if ! command -v pm2 >/dev/null; then
    npm install -g pm2
fi

# Restore PM2 processes if saved
pm2 resurrect

# Install pm2-logrotate if not already running
if ! pm2 ls | grep -q pm2-logrotate; then
    pm2 install pm2-logrotate
    pm2 save --force
fi

# Start cron daemon
/usr/sbin/cron

# Import crontab.txt if it exists
if [ -f "/root/crontab.txt" ]; then
    crontab /root/crontab.txt  # Import crontab every boot
fi

# Set up SSH directories and permissions
mkdir -p /var/run/sshd
mkdir -p /root/.ssh
chown -R root:root /root
chown -R root:root /root/.ssh
if [ ! -f "/root/.ssh/authorized_keys" ]; then
    touch /root/.ssh/authorized_keys
    chown root:root /root/.ssh/authorized_keys
else
    chown root:root /root/.ssh/authorized_keys
fi
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys

# Configure SSH settings for root login and key-based authentication (apply only if not already set)
if ! grep -q '^PermitRootLogin yes' /etc/ssh/sshd_config; then
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
fi
if ! grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config; then
    sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
fi
if ! grep -q '^StrictModes no' /etc/ssh/sshd_config; then
    sed -i 's/StrictModes yes/StrictModes no/' /etc/ssh/sshd_config
fi
if grep -q 'session\s*required\s*pam_loginuid.so' /etc/pam.d/sshd; then
    sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd
fi

# Start SSH daemon in background and save PID
/usr/sbin/sshd -D &
SSHD_PID=$!

# Wait for sshd to exit
wait $SSHD_PID