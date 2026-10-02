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

# Install open-webui via pipx using Python 3.12
# We inject python3.12 so it ignores system python3
PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install open-webui --python python3.12

# Cleanup
apt-get clean
rm -rf /var/lib/apt/lists/*
