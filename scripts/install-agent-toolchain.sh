#!/bin/bash
set -euo pipefail

# Ensure target directories exist
mkdir -p "$HOME/.local/bin"
mkdir -p "$HOME/.local/share"

# 1. Install Google Antigravity (Agent UI) (2.0.1 Tarball)
IDE_VERSION="2.0.1"
IDE_EXEC_ID="6566078776737792"
IDE_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/${IDE_VERSION}-${IDE_EXEC_ID}/linux-x64/Antigravity.tar.gz"
IDE_SHA256="0727e1f56961b6d2347941f278da69cc6c17de3befe988524848cd167380e9ab"

echo "Downloading Google Antigravity (Agent UI)..."
curl -fsSL --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 "$IDE_URL" -o /tmp/Antigravity.tar.gz
echo "$IDE_SHA256  /tmp/Antigravity.tar.gz" | sha256sum -c -

echo "Extracting Google Antigravity (Agent UI)..."
rm -rf "$HOME/.local/share/antigravity"
mkdir -p "$HOME/.local/share/antigravity"
tar -xzf /tmp/Antigravity.tar.gz -C "$HOME/.local/share/antigravity" --strip-components=1
rm -f /tmp/Antigravity.tar.gz

cat << 'EOF' > "$HOME/.local/bin/antigravity"
#!/bin/bash
if [ -e /run/.containerenv ] || [ -e /run/.toolboxenv ]; then
    mkdir -p "$HOME/.config/Antigravity-box/User"
    if [ ! -f "$HOME/.config/Antigravity-box/User/settings.json" ]; then
        echo '{"antigravity.account.enableTelemetry": false, "antigravity.browser.chromeBinaryPath": "/usr/bin/google-chrome-stable", "window.titleBarStyle": "native"}' > "$HOME/.config/Antigravity-box/User/settings.json"
    elif command -v jq &>/dev/null; then
        jq '.["antigravity.browser.chromeBinaryPath"] = "/usr/bin/google-chrome-stable" | .["window.titleBarStyle"] = "native"' "$HOME/.config/Antigravity-box/User/settings.json" > "$HOME/.config/Antigravity-box/User/settings.json.tmp" && mv "$HOME/.config/Antigravity-box/User/settings.json.tmp" "$HOME/.config/Antigravity-box/User/settings.json"
    fi
    exec "$HOME/.local/share/antigravity/antigravity" --user-data-dir "$HOME/.config/Antigravity-box" --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "$@"
else
    exec "$HOME/.local/share/antigravity/antigravity" --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "$@"
fi
EOF
chmod +x "$HOME/.local/bin/antigravity"

# Disable Antigravity telemetry
mkdir -p "$HOME/.config/Antigravity/User"
echo '{"antigravity.account.enableTelemetry": false}' > "$HOME/.config/Antigravity/User/settings.json"


# 2. Install Antigravity IDE (Stable 1.23.2 Tarball)
IDE_VERSION="1.23.2"
IDE_URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${IDE_VERSION}-4781536860569600/linux-x64/Antigravity.tar.gz"
IDE_SHA256="5232a4048ff4fa15685d9a981ba4fba573e297f3efc9b76f638e794baf775725"

echo "Downloading Antigravity IDE..."
curl -fsSL --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 "$IDE_URL" -o /tmp/Antigravity-ide.tar.gz
echo "$IDE_SHA256  /tmp/Antigravity-ide.tar.gz" | sha256sum -c -

echo "Extracting Antigravity IDE..."
rm -rf "$HOME/.local/share/antigravity-ide"
mkdir -p "$HOME/.local/share/antigravity-ide"
tar -xzf /tmp/Antigravity-ide.tar.gz -C "$HOME/.local/share/antigravity-ide" --strip-components=1
rm -f /tmp/Antigravity-ide.tar.gz

cat << 'EOF' > "$HOME/.local/bin/antigravity-ide"
#!/bin/bash
if [ -e /run/.containerenv ] || [ -e /run/.toolboxenv ]; then
    mkdir -p "$HOME/.config/Antigravity-ide-box/User"
    if [ ! -f "$HOME/.config/Antigravity-ide-box/User/settings.json" ]; then
        echo '{"antigravity.account.enableTelemetry": false, "antigravity.browser.chromeBinaryPath": "/usr/bin/google-chrome-stable", "window.titleBarStyle": "native"}' > "$HOME/.config/Antigravity-ide-box/User/settings.json"
    elif command -v jq &>/dev/null; then
        jq '.["antigravity.browser.chromeBinaryPath"] = "/usr/bin/google-chrome-stable" | .["window.titleBarStyle"] = "native"' "$HOME/.config/Antigravity-ide-box/User/settings.json" > "$HOME/.config/Antigravity-ide-box/User/settings.json.tmp" && mv "$HOME/.config/Antigravity-ide-box/User/settings.json.tmp" "$HOME/.config/Antigravity-ide-box/User/settings.json"
    fi
    exec "$HOME/.local/share/antigravity-ide/antigravity" --user-data-dir "$HOME/.config/Antigravity-ide-box" --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "$@"
else
    exec "$HOME/.local/share/antigravity-ide/antigravity" --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "$@"
fi
EOF
chmod +x "$HOME/.local/bin/antigravity-ide"

# Disable telemetry for IDE
mkdir -p "$HOME/.config/Antigravity-ide/User"
echo '{"antigravity.account.enableTelemetry": false}' > "$HOME/.config/Antigravity-ide/User/settings.json"


# 3. Install Antigravity CLI (1.0.0 Tarball)
CLI_VERSION="1.0.0"
CLI_EXEC_ID="5288553236791296"
CLI_URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/${CLI_VERSION}-${CLI_EXEC_ID}/linux-x64/cli_linux_x64.tar.gz"
CLI_SHA512="5ccdcc01fb863c7e8e56473c6c95dba75fed4fd2a242200d80cfc4c7fab811b733f5a7fab25332130aad298e72627e1018e6911a5658f4f059ef6e019f211972"

echo "Downloading Antigravity CLI..."
curl -fsSL --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 "$CLI_URL" -o /tmp/cli_linux_x64.tar.gz
echo "$CLI_SHA512  /tmp/cli_linux_x64.tar.gz" | sha512sum -c -

echo "Extracting Antigravity CLI..."
tar -xzf /tmp/cli_linux_x64.tar.gz -C /tmp antigravity
mv /tmp/antigravity "$HOME/.local/bin/agy"
chmod +x "$HOME/.local/bin/agy"
rm -f /tmp/cli_linux_x64.tar.gz


# 4. Install Antigravity SDK (google-antigravity)
echo "Installing Antigravity SDK..."
pip3 install --user --break-system-packages --no-cache-dir --retries 10 google-antigravity==0.1.0


# 5. Install Google ADK
echo "Installing Google ADK..."
pip3 install --user --break-system-packages --no-cache-dir --retries 10 google-adk==2.1.0


# 6. Install Gemini CLI
echo "Installing Gemini CLI..."
npm install -g --prefix "$HOME/.local" --omit=dev --no-audit --no-fund @google/gemini-cli@0.43.0

echo "Agent toolchain installed successfully at user level."
