# Zettlab NAS Docker Container Setup

> **⚠️ Intel-Based NAS Only**: This Docker container setup is designed exclusively for **Zettlab D6 Ultra** and **D8 Ultra** NAS models. These systems feature Intel processors with integrated Arc graphics (iGPU). This setup will **NOT** work on ARM-based NAS systems or other models without Intel iGPU support.

This repository provides a simple Docker Compose setup for running an Ubuntu 24.04 container on a Zettlab NAS with tools like Python, UV (Python package manager), Git, PM2 (Node.js process manager), SSH access, cron, Neovim, rsync, and logrotate. It's designed for easy customization and persistence, ideal for development or scripting environments.

## Why No Dockerfile?
We avoid using a custom Dockerfile to keep things simple and flexible. Building and exporting a Docker image as a .tar file for NAS upload can be time-consuming. Instead, we use the official `ubuntu:24.04` image and an `init.sh` script that runs on startup to install and configure everything conditionally. This allows anyone to easily modify the script for their needs without rebuilding an image—perfect for quick tweaks on a NAS.

## Supported Hardware

- **Zettlab D6 Ultra**
- **Zettlab D8 Ultra**

> **Note**: This setup leverages Intel-specific GPU drivers (`intel-level-zero-gpu`, `intel-opencl-icd`, `libze1`) and `/dev/dri` device passthrough, which are only available on Intel-based systems.

## Setup Instructions

1. **Create the Directory Structure**:
    - On your NAS, create a folder (e.g., `/This_NAS/Teams/docker/ubuntu`).
    - This folder binds to `/root` in the container for persistence—important for SSH keys, configs, and data like PM2 dumps or crontab.txt.

2. **Add init.sh Script**:
    - Place `init.sh` in `/This_NAS/Teams/docker/ubuntu`.
    - Use the script provided (with conditional installs, cleanup, etc.).
    - Optionally, add `crontab.txt` in `/This_NAS/Teams/docker/ubuntu` for custom cron jobs.
    - **Best Practice**: Always redirect cron job output to log files in `/root/logs` with stderr redirection:
      ```bash
      # Example cron entry
      * * * * * /path/to/command >> /root/logs/mylog.log 2>&1
      ```
      The `2>&1` redirects both stdout and stderr to the log file.

3. **Start the Container**:
    - Use the NAS Docker UI to create and start the container with the compose file.
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

This setup includes comprehensive Intel integrated GPU (iGPU) support for compute-intensive workloads. The `init.sh` script automatically installs minimal Intel GPU drivers and runtimes:

- **intel-level-zero-gpu**: Level Zero API for Intel GPU compute
- **intel-opencl-icd**: OpenCL ICD for Intel GPUs
- **libze1**: Level Zero library

These drivers enable GPU-accelerated computing in Python environments, including support for:
- PyTorch via Intel Extension for PyTorch (IPEX) with XPU backend
- oneAPI/SYCL programming model
- OpenCL applications

The `docker-compose.yml` configuration:
- Passes through `/dev/dri` for direct GPU device access
- Sets `privileged: true` to allow container interaction with the host's iGPU

### GPU-Accelerated Workloads

This setup supports various GPU-accelerated applications:
- Machine learning and AI workloads with PyTorch
- Scientific computing (NumPy, SciPy with GPU acceleration)
- Computer vision tasks
- Data processing pipelines

## Logging Management

This setup includes comprehensive logging management with automatic log rotation:

### Log Directory
- **Location**: `/root/logs` - All cron job logs are stored here by default

### Logrotate Configuration
- **Configuration File**: `/etc/logrotate.d/cronlogs`
- **Rotation Policy**:
  - Daily rotation
  - Keep last 7 days of logs
  - Compress old logs automatically
  - Create new log files with proper permissions (0640)
  
This ensures that cron job logs don't grow indefinitely and are automatically managed.

### PM2 Log Rotation
- **Feature**: Automatically installed via `pm2-logrotate` module
- **Purpose**: Rotates PM2 process logs to prevent excessive disk usage
- **Persistence**: Log rotation configuration is saved with PM2 state

### Additional Tools
- **rsync**: File synchronization and backup utility, useful for copying files between directories or systems efficiently
- **logrotate**: System tool for managing automatic rotation, compression, and removal of log files

## Testing iGPU Support

To verify that iGPU support is working correctly, use the provided `test_igpu_support.py` script (located in the `igpu-test` folder). This script checks for PyTorch XPU (iGPU) availability and performs a simple computation test.

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
- **iGPU Drivers**: Adds Intel GPU repository and installs minimal compute packages if missing. This section only executes on compatible Intel-based systems.
- **Shutdown Cleanup**: Traps SIGTERM (from `docker stop`) to save PM2 state (`pm2 save --force`), export current crontab to `/root/crontab.txt` (backing up any existing file), then gracefully stops sshd.
- **Efficiency**: Heavy operations (e.g., apt updates) only run when needed; quick checks make restarts fast.

This logic ensures the container is ready for use with minimal overhead, while persisting customizations via the volume mount. Customize `init.sh` as needed—add more tools or logic easily.

## Troubleshooting

### iGPU Not Detected
- Verify you're using a compatible Zettlab NAS (D6 Ultra or D8 Ultra)
- Check that `/dev/dri` is properly mounted in the container: `ls -la /dev/dri`
- Run `clinfo` to check OpenCL device availability
- Ensure the container is running with `privileged: true`

### SSH Connection Issues
- Confirm your public key is in `/root/.ssh/authorized_keys`
- Check that the container's port 2222 is accessible from your network
- Verify SSHd is running: `ps aux | grep sshd`

### PM2 Processes Not Starting
- Check that PM2 dump file exists in `/root/.pm2/dump.pm2`
- Review PM2 logs: `pm2 logs`
- Ensure required dependencies are installed in the container

## License

This project is provided as-is for use with Zettlab NAS systems.
