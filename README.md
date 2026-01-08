# Zettlab NAS Docker Container Setup

This repository provides a simple Docker Compose setup for running an Ubuntu 24.04 container on a Zettlab NAS with tools like Python, UV (Python package manager), Git, PM2 (Node.js process manager), SSH access, cron, and Neovim. It's designed for easy customization and persistence, ideal for development or scripting environments.

## Why No Dockerfile?
We avoid using a custom Dockerfile to keep things simple and flexible. Building and exporting a Docker image as a .tar file for NAS upload can be time-consuming. Instead, we use the official `ubuntu:24.04` image and an `init.sh` script that runs on startup to install and configure everything conditionally. This allows anyone to easily modify the script for their needs without rebuilding an image—perfect for quick tweaks on a NAS.

## Setup Instructions

1. **Create the Directory Structure**:
    - On your NAS, create a folder (e.g., `/This_NAS/Teams/docker/ubuntu`).
    - This folder binds to `/root` in the container for persistence—important for SSH keys, configs, and data like PM2 dumps or crontab.txt.

2. **Add init.sh Script**:
    - Place `init.sh` in `/This_NAS/Teams/docker/ubuntu`.
    - Use the script provided (with conditional installs, cleanup, etc.).
    - Optionally, add `crontab.txt` in `/This_NAS/Teams/docker/ubuntu` for custom cron jobs (e.g., `* * * * * echo "Test" >> /tmp/test.log`).

3. **Start the Container**:
    - Use the NAS Docker UI to create and start the container wth the compose file.
    - The container will start with SSH enabled, but password login is disabled for security reasons. This means you cannot SSH in initially using a password—you must set up SSH key authentication using the Docker app terminal on your NAS UI.

4. **Set Up SSH Key Authentication**:
    - Generate an SSH key pair on the machine you'll use to access the container (e.g., your local computer):
      ```
      ssh-keygen -t ed25519 -C "your_email@example.com"
      ```
        - This creates `~/.ssh/id_ed25519` (private key) and `~/.ssh/id_ed25519.pub` (public key) on your local machine. Follow the prompts (you can leave the passphrase empty for simplicity, but use one for better security).
        - Copy the contents of your public key file (e.g., `cat ~/.ssh/id_ed25519.pub` on your local machine) to your clipboard.
    - Access the container using the Docker app terminal on your NAS UI (this provides a root shell inside the container).
    - The `init.sh` script has already created the `/root/.ssh` folder and `authorized_keys` file (if missing), and set permissions.
    - In the terminal, append your public key to `/root/.ssh/authorized_keys` by pasting it into a command like this (replace the example key with your actual public key):
      ```
      echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... your_email@example.com" >> /root/.ssh/authorized_keys
      ```
        - The script handles ownership and permissions (700 for `.ssh`, 600 for `authorized_keys`), but you can verify/run `chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys` if needed.
    - Exit the terminal session. Now you can SSH in from your local machine: `ssh root@your-nas-ip -p 2222` (it will use your private key automatically if it's in `~/.ssh`).

5. **Persistence Reminder**:
    - The volume mount to `/This_NAS/Teams/docker/ubuntu` persists everything in `/root` (e.g., SSH keys, PM2 process dumps, crontab.txt). Without this, changes reset on container recreate.

## iGPU Support

The `init.sh` script includes installation of minimal Intel GPU drivers and runtimes (e.g., `intel-level-zero-gpu`, `intel-opencl-icd`, and `libze1`) to enable iGPU compute support for the Zettlab NAS D6 Ultra's Intel Core Ultra 5 125H processor (with integrated Arc graphics). This supports compute tasks in Python environments, such as PyTorch via Intel Extension for PyTorch (using oneAPI/SYCL backends).

The `docker-compose.yml` file passes through `/dev/dri` for GPU device access and sets `privileged: true` to allow the container to interact with the host's iGPU.

Python basics (`python3` and `python3-pip`) are installed, enabling further package installations (e.g., for PyTorch). Note that application-specific packages like PyTorch must be installed separately (e.g., via UV or pip).

## Testing iGPU Support

To verify iGPU support, use the provided `test_igpu_support.py` script (located in the `igpu-test` folder). This script checks for PyTorch XPU (iGPU) availability and performs a simple computation test.

1. **Place the Test Script**:
    - On your NAS host, add the `igpu-test` folder containing `test_igpu_support.py` to `/This_NAS/Teams/docker/ubuntu` (it will be available at `/root/igpu-test` inside the container due to the volume mount).

2. **SSH into the Container**:
    - Connect via SSH: `ssh root@your-nas-ip -p 2222`.

3. **Navigate to the Test Folder**:
    - `cd /root/igpu-test`

4. **Create a Virtual Environment with UV**:
    - Run `uv venv .venv-igpu` to create an isolated environment (this avoids installing packages globally).

5. **Activate the Environment**:
    - `source .venv-igpu/bin/activate`

6. **Run the Test Script**:
    - Use `uv run --extra-index-url https://download.pytorch.org/whl/xpu test_igpu_support.py` to execute the script. This will temporarily handle dependencies (e.g., installing PyTorch with XPU support if needed) without modifying the virtual environment permanently.
    - Alternatively, if you prefer to install dependencies persistently in the venv: Run `uv pip install --index-url https://download.pytorch.org/whl/xpu torch numpy`, then `python test_igpu_support.py`.

7. **Interpret the Output**:
    - If successful, you'll see "iGPU support detected via PyTorch!" and a test result (e.g., `[2. 3. 4.]`).
    - If not, it will provide troubleshooting tips (e.g., check drivers with `clinfo`).

This test confirms that the iGPU is accessible and functional for Python/PyTorch workloads.

## Logic of the init.sh Script

The `init.sh` script runs on every container start (via the `command` in docker-compose.yml). It's designed to be efficient and idempotent:

- **Conditional Installs**: Checks if tools are missing (using `command -v`) before installing via apt-get, curl, or npm. This skips redundant downloads on restarts (e.g., Python, pip, Git, openssh-server, curl, Node.js, npm, Neovim, UV, PM2, cron).
- **PM2 Handling**: Restores saved processes with `pm2 resurrect` on start.
- **Cron Setup**: Installs cron if needed, starts the daemon (`/usr/sbin/cron`), and imports jobs from `/root/crontab.txt` if it exists.
- **SSH Configuration**: Creates `/var/run/sshd` and `/root/.ssh` if needed, touches `/root/.ssh/authorized_keys` if missing, sets ownership (root:root) and permissions (700 for `.ssh`, 600 for `authorized_keys`), edits `/etc/ssh/sshd_config` (PermitRootLogin yes, PasswordAuthentication no, StrictModes no), modifies `/etc/pam.d/sshd` for compatibility, and starts sshd in background.
- **iGPU Drivers**: Adds Intel GPU repository and installs minimal compute packages if missing.
- **Shutdown Cleanup**: Traps SIGTERM (from `docker stop`) to save PM2 state (`pm2 save --force`), export current crontab to `/root/crontab.txt` (backing up any existing file), then gracefully stops sshd.
- **Efficiency**: Heavy operations (e.g., apt updates) only run when needed; quick checks make restarts fast.

This logic ensures the container is ready for use with minimal overhead, while persisting customizations via the volume mount. Customize `init.sh` as needed—add more tools or logic easily.