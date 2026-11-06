#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
export PIP_NO_COMPILE=1

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

# Install uv directly from static musl release tarball (avoids slow pipx bootstrap under QEMU)
arch="$(uname -m)"
case "$arch" in
    aarch64|arm64)
        uv_arch="aarch64"
        uv_platform="aarch64-unknown-linux-gnu"
        ;;
    *)
        uv_arch="x86_64"
        uv_platform="x86_64-unknown-linux-gnu"
        ;;
esac

curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 5 \
    "https://github.com/astral-sh/uv/releases/latest/download/uv-${uv_arch}-unknown-linux-musl.tar.gz" \
    | tar -xz -C /usr/local/bin --strip-components=1 \
        "uv-${uv_arch}-unknown-linux-musl/uv" \
        "uv-${uv_arch}-unknown-linux-musl/uvx"
chmod +x /usr/local/bin/uv /usr/local/bin/uvx

UV_BIN="/usr/local/bin/uv"
if ! "$UV_BIN" --version >/dev/null 2>&1; then
    echo "Target-arch uv failed (likely x86_64 jemalloc under QEMU on ARM64 host); trying static aarch64 uv..."
    mkdir -p /tmp/uv-host
    if curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 5 \
        "https://github.com/astral-sh/uv/releases/latest/download/uv-aarch64-unknown-linux-musl.tar.gz" \
        | tar -xz -C /tmp/uv-host --strip-components=1 "uv-aarch64-unknown-linux-musl/uv" && \
       chmod +x /tmp/uv-host/uv && \
       /tmp/uv-host/uv --version >/dev/null 2>&1; then
        echo "Using native host-kernel aarch64 uv for fast cross-arch wheel installation."
        UV_BIN="/tmp/uv-host/uv"
    fi
fi

python3.12 -m venv --without-pip /opt/open-webui-venv

if "$UV_BIN" --version >/dev/null 2>&1 && \
   "$UV_BIN" pip install --python /opt/open-webui-venv/bin/python --python-platform "$uv_platform" pip && \
   "$UV_BIN" pip install --python /opt/open-webui-venv/bin/python --python-platform "$uv_platform" --index-url https://download.pytorch.org/whl/cpu torch torchvision && \
   "$UV_BIN" pip install --python /opt/open-webui-venv/bin/python --python-platform "$uv_platform" open-webui; then
    echo "Open WebUI installed via uv ($UV_BIN)."
else
    echo "uv failed; falling back to python3.12 -m venv + pip..."
    rm -rf /opt/open-webui-venv
    python3.12 -m venv /opt/open-webui-venv
    /opt/open-webui-venv/bin/pip install --no-compile --upgrade pip
    /opt/open-webui-venv/bin/pip install --no-compile --index-url https://download.pytorch.org/whl/cpu torch torchvision
    /opt/open-webui-venv/bin/pip install --no-compile open-webui
fi
rm -rf /tmp/uv-host

# Expose open-webui binary on system PATH
ln -sf /opt/open-webui-venv/bin/open-webui /usr/local/bin/open-webui

# Cleanup
apt-get clean
rm -rf /var/lib/apt/lists/*
