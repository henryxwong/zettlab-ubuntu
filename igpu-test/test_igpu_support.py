#!/usr/bin/env python3

import subprocess
import sys
import importlib.util


def install_if_missing(packages, index_url=None):
    for package in packages:
        if importlib.util.find_spec(package.split('==')[0]) is None:
            cmd = ['uv', 'pip', 'install', package]
            if index_url:
                cmd += ['--index-url', index_url]
            print(f"Installing {package}...", file=sys.stderr)
            try:
                subprocess.check_call(cmd)
            except subprocess.CalledProcessError as e:
                print(f"Failed to install {package}: {e}", file=sys.stderr)
                sys.exit(1)


# Install required packages if missing
install_if_missing(['torch', 'numpy'], index_url='https://download.pytorch.org/whl/xpu')

import torch
import numpy as np  # Just to suppress the warning

# Check for iGPU (XPU) availability
if torch.xpu.is_available():
    print("iGPU support detected via PyTorch!")

    # Perform a simple test computation on the iGPU
    device = torch.device('xpu')
    a = torch.tensor([1.0, 2.0, 3.0], device=device)
    b = a + 1
    print(f"Test result on iGPU: {b.cpu().numpy()}")
else:
    print(
        "No iGPU support detected. Ensure the Intel GPU drivers are installed on the host and in the container, and the container has access to /dev/dri. Run 'clinfo' inside the container to verify GPU detection. If clinfo shows no platforms, check host drivers or container privileges.")