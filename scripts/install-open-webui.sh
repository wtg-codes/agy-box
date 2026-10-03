#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "Installing Python 3.12 and Open WebUI..."

# We need Python 3.12 for open-webui as it requires >=3.11, <3.13
# Ubuntu 26.04 ships with Python 3.14.

# Update apt cache
apt-get update

# Install software-properties-common for add-apt-repository
apt-get install -y --no-install-recommends software-properties-common

# Add deadsnakes PPA for Python 3.12 (in case it's not in the main repos)
add-apt-repository -y ppa:deadsnakes/ppa
apt-get update

# Install Python 3.12 and its venv module
apt-get install -y --no-install-recommends python3.12 python3.12-venv

# Install uv for high-speed parallel package downloads and wheel caching
PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install uv

# Create isolated virtualenv for Open WebUI with Python 3.12
uv venv /opt/open-webui-venv --python python3.12

# Install CPU-only PyTorch first to avoid downloading ~4.5 GB of NVIDIA CUDA blobs
uv pip install --python /opt/open-webui-venv/bin/python --index-url https://download.pytorch.org/whl/cpu torch torchvision

# Install Open WebUI into the virtual environment (reuses pre-installed CPU torch)
uv pip install --python /opt/open-webui-venv/bin/python open-webui

# Expose open-webui binary on system PATH
ln -sf /opt/open-webui-venv/bin/open-webui /usr/local/bin/open-webui

# Cleanup
apt-get clean
rm -rf /var/lib/apt/lists/* /root/.cache
