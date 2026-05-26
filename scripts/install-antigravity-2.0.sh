#!/bin/bash
set -euo pipefail

# Install Google Antigravity 2.0 (2.0.1 Tarball)
IDE_VERSION="2.0.1"
IDE_EXEC_ID="6566078776737792"
IDE_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/${IDE_VERSION}-${IDE_EXEC_ID}/linux-x64/Antigravity.tar.gz"
IDE_SHA256="0727e1f56961b6d2347941f278da69cc6c17de3befe988524848cd167380e9ab"

echo "Downloading Google Antigravity 2.0..."
curl -fsSL --connect-timeout 5 --retry 5 --retry-delay 2 "$IDE_URL" -o /tmp/Antigravity.tar.gz
echo "$IDE_SHA256  /tmp/Antigravity.tar.gz" | sha256sum -c -

echo "Extracting Google Antigravity 2.0..."
mkdir -p /usr/share/antigravity
tar -xzf /tmp/Antigravity.tar.gz -C /usr/share/antigravity --strip-components=1
rm /tmp/Antigravity.tar.gz

printf '#!/bin/bash\nexec /usr/share/antigravity/antigravity --disable-dev-shm-usage "$@"' > /usr/bin/antigravity
chmod +x /usr/bin/antigravity

# Disable Antigravity telemetry
mkdir -p /etc/skel/.config/Antigravity/User
echo '{"antigravity.account.enableTelemetry": false}' > /etc/skel/.config/Antigravity/User/settings.json
