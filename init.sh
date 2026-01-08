#!/bin/bash

# Shutdown cleanup function
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

# Trap SIGTERM
trap 'cleanup' TERM

# Install base packages if missing
if ! command -v git >/dev/null || ! command -v curl >/dev/null || ! command -v npm >/dev/null || ! command -v sshd >/dev/null; then
    apt-get update && apt-get install -y \
        python3 \
        python3-pip \
        git \
        openssh-server \
        curl \
        nodejs \
        npm \
        && rm -rf /var/lib/apt/lists/*
fi

# Install Neovim if missing
if ! command -v nvim >/dev/null; then
    apt-get update && apt-get install -y neovim && rm -rf /var/lib/apt/lists/*
fi

# Install UV if missing
if ! command -v uv >/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
    if ! grep -q 'source $HOME/.local/bin/env' /root/.bashrc; then
        echo 'source $HOME/.local/bin/env' >> /root/.bashrc
    fi
fi

# Install PM2 if missing
if ! command -v pm2 >/dev/null; then
    npm install -g pm2
fi

# Restore PM2 processes if saved
pm2 resurrect

# Install cron if missing, start daemon, and import crontab.txt if exists
if ! command -v crontab >/dev/null; then
    apt-get update && apt-get install -y cron && rm -rf /var/lib/apt/lists/*
fi
/usr/sbin/cron
if [ -f "/root/crontab.txt" ]; then
    crontab /root/crontab.txt  # Import crontab every boot
fi

# Install minimal Intel GPU drivers and runtimes if missing (for iGPU compute support in Python/PyTorch)
if ! dpkg -l | grep -q intel-level-zero-gpu; then
    apt-get update && apt-get install -y wget gpg-agent gnupg && rm -rf /var/lib/apt/lists/*

    # Add Intel Graphics GPG key
    wget -qO - https://repositories.intel.com/gpu/intel-graphics.key | \
    gpg --yes --dearmor --output /usr/share/keyrings/intel-graphics.gpg

    # Add Intel GPU repository for Ubuntu 24.04 (noble)
    echo "deb [arch=amd64,i386 signed-by=/usr/share/keyrings/intel-graphics.gpg] https://repositories.intel.com/gpu/ubuntu noble client" | \
    tee /etc/apt/sources.list.d/intel-gpu-noble.list

    # Update and install minimal compute packages
    apt-get update && apt-get install -y \
        libze1 \
        intel-level-zero-gpu \
        intel-opencl-icd \
        && rm -rf /var/lib/apt/lists/*
fi

# Set up SSH
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
sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/StrictModes yes/StrictModes no/' /etc/ssh/sshd_config
sed 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' -i /etc/pam.d/sshd

# Start SSH daemon in background and save PID
/usr/sbin/sshd -D &
SSHD_PID=$!

# Wait for sshd to exit
wait $SSHD_PID