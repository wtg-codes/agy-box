#!/bin/bash
set -euo pipefail

# Install Antigravity CLI (1.0.0 Tarball)
CLI_VERSION="1.0.0"
CLI_EXEC_ID="5288553236791296"
CLI_URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/${CLI_VERSION}-${CLI_EXEC_ID}/linux-x64/cli_linux_x64.tar.gz"
CLI_SHA512="5ccdcc01fb863c7e8e56473c6c95dba75fed4fd2a242200d80cfc4c7fab811b733f5a7fab25332130aad298e72627e1018e6911a5658f4f059ef6e019f211972"

echo "Downloading Antigravity CLI..."
curl -fsSL --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 "$CLI_URL" -o /tmp/cli_linux_x64.tar.gz
echo "$CLI_SHA512  /tmp/cli_linux_x64.tar.gz" | sha512sum -c -

echo "Extracting Antigravity CLI..."
tar -xzf /tmp/cli_linux_x64.tar.gz -C /tmp antigravity
mv /tmp/antigravity /usr/bin/agy
chmod +x /usr/bin/agy
rm /tmp/cli_linux_x64.tar.gz
