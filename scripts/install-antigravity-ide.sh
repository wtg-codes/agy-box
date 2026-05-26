#!/bin/bash
set -euo pipefail

# Install Antigravity IDE (Stable 1.23.2 Tarball)
IDE_VERSION="1.23.2"
IDE_URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${IDE_VERSION}-4781536860569600/linux-x64/Antigravity.tar.gz"
IDE_SHA256="5232a4048ff4fa15685d9a981ba4fba573e297f3efc9b76f638e794baf775725"

echo "Downloading Antigravity IDE..."
curl -fsSL --connect-timeout 5 --retry 5 --retry-delay 2 "$IDE_URL" -o /tmp/Antigravity-ide.tar.gz
echo "$IDE_SHA256  /tmp/Antigravity-ide.tar.gz" | sha256sum -c -

echo "Extracting Antigravity IDE..."
mkdir -p /usr/share/antigravity-ide
tar -xzf /tmp/Antigravity-ide.tar.gz -C /usr/share/antigravity-ide --strip-components=1
rm /tmp/Antigravity-ide.tar.gz

printf '#!/bin/bash\nexec /usr/share/antigravity-ide/antigravity --disable-dev-shm-usage "$@"' > /usr/bin/antigravity-ide
chmod +x /usr/bin/antigravity-ide

# Disable telemetry for IDE
mkdir -p /etc/skel/.config/Antigravity-ide/User
echo '{"antigravity.account.enableTelemetry": false}' > /etc/skel/.config/Antigravity-ide/User/settings.json
