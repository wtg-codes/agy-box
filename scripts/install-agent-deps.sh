#!/bin/bash
set -euo pipefail

TARGETARCH="${1:-amd64}"
if [[ "$TARGETARCH" =~ arm ]]; then
    TARGETARCH="arm64"
else
    TARGETARCH="amd64"
fi

export DEBIAN_FRONTEND=noninteractive

# 1. Install system dependencies
echo "Installing agent dependencies..."
apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    wget \
    jq \
    gnupg \
    python3-pip \
    pipx \
    python3-keyring \
    python3-keyrings.alt \
    apt-transport-https \
    ca-certificates \
    libsecret-1-0 \
    tini \
    gosu \
    xvfb \
    x11vnc \
    icewm \
    novnc \
    websockify \
    xterm \
    pcmanfm \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# 2. Install Node.js (v22 LTS) via NodeSource (for Gemini CLI and modern tooling)
echo "Installing Node.js 22 LTS via NodeSource..."
mkdir -p /etc/apt/keyrings
curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 5 https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" > /etc/apt/sources.list.d/nodesource.list
apt-get update && apt-get install -y --no-install-recommends nodejs && rm -rf /var/lib/apt/lists/*

# 3. Install Charm Gum
echo "Installing Charm Gum..."
mkdir -p /etc/apt/keyrings
curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 5 https://repo.charm.sh/apt/gpg.key | gpg --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" > /etc/apt/sources.list.d/charm.list
apt-get update && apt-get install -y --no-install-recommends gum=0.17.0 && rm -rf /var/lib/apt/lists/*

# 4. Install Google Chrome (amd64) or Chromium (arm64) for agent-based browsing
if [[ "$TARGETARCH" = "arm64" ]]; then
    echo "Installing Chromium for arm64 via xtradeb PPA..."
    mkdir -p /etc/apt/keyrings
    curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 5 "https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x5301FA4FD93244FBC6F6149982BB6851C64F6880" | gpg --dearmor -o /etc/apt/keyrings/xtradeb.gpg
    echo "deb [arch=arm64 signed-by=/etc/apt/keyrings/xtradeb.gpg] http://ppa.launchpad.net/xtradeb/apps/ubuntu noble main" > /etc/apt/sources.list.d/xtradeb.list
    apt-get update && apt-get install -y --no-install-recommends chromium && rm -rf /var/lib/apt/lists/*
    
    # Locate chromium binary
    if command -v chromium &>/dev/null; then
        CHROMIUM_BIN=$(command -v chromium)
    elif command -v chromium-browser &>/dev/null; then
        CHROMIUM_BIN=$(command -v chromium-browser)
    else
        CHROMIUM_BIN="/usr/bin/chromium"
    fi
    printf '#!/bin/bash\nexec %s --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "$@"\n' "${CHROMIUM_BIN}" > /usr/bin/google-chrome-stable
    chmod +x /usr/bin/google-chrome-stable
else
    echo "Installing Google Chrome for amd64..."
    wget -q -O - --connect-timeout=5 --tries=5 https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/googlechrome-linux-keyring.gpg
    echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/googlechrome-linux-keyring.gpg] https://dl.google.com/linux/chrome/deb/ stable main' > /etc/apt/sources.list.d/google.list
    apt-get update && apt-get install -y --no-install-recommends google-chrome-stable && rm -rf /var/lib/apt/lists/*
    
    # Apply wrappers for Electron/Chrome stability in containers
    mv /usr/bin/google-chrome-stable /usr/bin/google-chrome-stable.orig
    printf '#!/bin/bash\nexec /usr/bin/google-chrome-stable.orig --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "$@"\n' > /usr/bin/google-chrome-stable
    chmod +x /usr/bin/google-chrome-stable
fi
