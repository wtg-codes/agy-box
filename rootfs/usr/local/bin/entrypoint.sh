#!/bin/bash
set -euo pipefail

PUID=${PUID:-9000}
PGID=${PGID:-9000}

# Create group if it doesn't exist
if ! getent group "$PGID" >/dev/null; then
    groupadd -g "$PGID" agygroup
fi

# Create user if it doesn't exist
if ! getent passwd "$PUID" >/dev/null; then
    useradd -u "$PUID" -g "$PGID" -d /home/agyuser -m -s /bin/bash agyuser
fi

# Chown volumes
chown -R agyuser:agygroup /workspace || true
chown -R agyuser:agygroup /config || true

# Execute requested command
exec gosu agyuser "$@"
