#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "Installing Python 3.12 and Open WebUI..."

# We need Python 3.12 for open-webui as it requires >=3.11, <3.13
# Ubuntu 24.04 ships Python 3.12 natively; later releases may need deadsnakes PPA.
apt-get update

if ! apt-cache show python3.12 >/dev/null 2>&1; then
    apt-get install -y --no-install-recommends software-properties-common
    add-apt-repository -y ppa:deadsnakes/ppa
    apt-get update
fi

# Install Python 3.12 and its venv module
apt-get install -y --no-install-recommends python3.12 python3.12-venv

# Install uv for high-speed parallel package downloads and wheel caching
PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install uv

# Single-thread uv under QEMU user-mode emulation to avoid allocator/thread segfaults,
# and fall back cleanly to standard python3.12 -m venv + pip if uv still crashes under QEMU.
export RAYON_NUM_THREADS=1
export UV_CONCURRENT_DOWNLOADS=1
export UV_CONCURRENT_BUILDS=1
export UV_CONCURRENT_INSTALLS=1

if uv venv /opt/open-webui-venv --python python3.12 && \
   uv pip install --python /opt/open-webui-venv/bin/python --index-url https://download.pytorch.org/whl/cpu torch torchvision && \
   uv pip install --python /opt/open-webui-venv/bin/python open-webui; then
    echo "Open WebUI installed via uv."
else
    echo "uv failed (likely running under QEMU emulation); falling back to python3.12 -m venv + pip..."
    rm -rf /opt/open-webui-venv
    python3.12 -m venv /opt/open-webui-venv
    /opt/open-webui-venv/bin/pip install --no-cache-dir --upgrade pip
    /opt/open-webui-venv/bin/pip install --no-cache-dir --index-url https://download.pytorch.org/whl/cpu torch torchvision
    /opt/open-webui-venv/bin/pip install --no-cache-dir open-webui
fi

# Expose open-webui binary on system PATH
ln -sf /opt/open-webui-venv/bin/open-webui /usr/local/bin/open-webui

# Cleanup
apt-get clean
rm -rf /var/lib/apt/lists/*
