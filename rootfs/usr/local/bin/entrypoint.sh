#!/bin/bash
set -euo pipefail

PUID=${PUID:-9000}
PGID=${PGID:-9000}

if [ "$(id -u)" -eq 0 ]; then
    # Ensure group exists and matches requested PGID
    if getent group agygroup >/dev/null; then
        groupmod -o -g "$PGID" agygroup
    elif ! getent group "$PGID" >/dev/null; then
        groupadd -o -g "$PGID" agygroup
    fi

    # Ensure user exists, matches requested PUID/PGID, and belongs to sudo
    if id -u agyuser >/dev/null 2>&1; then
        usermod -o -u "$PUID" -g "$PGID" -aG sudo agyuser
    else
        useradd -o -u "$PUID" -g "$PGID" -G sudo -d /home/agyuser -m -s /bin/bash agyuser
        printf 'agyuser:agyuser\n' | chpasswd
    fi

    # Ensure passwordless sudo is configured for agyuser
    mkdir -p /etc/sudoers.d
    printf 'agyuser ALL=(ALL:ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/agyuser
    chmod 0440 /etc/sudoers.d/agyuser

    # Seed /etc/skel into /home/agyuser when bind-mounted from an empty host directory
    mkdir -p /home/agyuser
    if [ -d /etc/skel ]; then
        cp -rn /etc/skel/. /home/agyuser/ 2>/dev/null || true
    fi

    # Fix ownership of home (skipping read-only profile mounts) and data volumes
    chown "$PUID:$PGID" /home/agyuser 2>/dev/null || true
    find /home/agyuser -mindepth 1 -maxdepth 2 \
        ! -path "/home/agyuser/.ssh*" \
        ! -path "/home/agyuser/.gitconfig" \
        ! -path "/home/agyuser/.config/gcloud*" \
        -exec chown -R "$PUID:$PGID" {} + 2>/dev/null || true
    [ -d /workspace ] && chown -R "$PUID:$PGID" /workspace 2>/dev/null || true
    [ -d /config ] && chown -R "$PUID:$PGID" /config 2>/dev/null || true

    # Execute requested command as agyuser
    exec gosu agyuser "$@"
else
    # Container was started directly as an unprivileged user (e.g., --user flag)
    if [ -d /etc/skel ] && [ -w /home/agyuser ]; then
        cp -rn /etc/skel/. /home/agyuser/ 2>/dev/null || true
    fi
    exec "$@"
fi
