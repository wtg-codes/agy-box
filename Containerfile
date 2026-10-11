FROM quay.io/toolbx/ubuntu-toolbox:24.04

LABEL org.opencontainers.image.description="Declarative Student Workspace for wtgOS Cloud-Native Laboratory"

ENV PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin

ARG TARGETARCH

# 1. Install agent dependencies
COPY scripts/install-agent-deps.sh /tmp/
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    /tmp/install-agent-deps.sh "${TARGETARCH}" && rm /tmp/install-agent-deps.sh

# 2. Install Open WebUI (Local Workspace Web Dashboard)
COPY scripts/install-open-webui.sh /tmp/
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    --mount=type=cache,target=/root/.cache/uv,sharing=locked \
    UV_LINK_MODE=copy /tmp/install-open-webui.sh && rm /tmp/install-open-webui.sh

# 3. Install CNCF Tooling
COPY scripts/install-tools.sh /tmp/
RUN /tmp/install-tools.sh "${TARGETARCH}" && rm /tmp/install-tools.sh

# 4. Install Antigravity Toolchain (Option A: Batteries-Included Image for authentic SBOM)
COPY scripts/install-agent-toolchain.sh /tmp/
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    --mount=type=cache,target=/root/.npm,sharing=locked \
    /tmp/install-agent-toolchain.sh --system && rm /tmp/install-agent-toolchain.sh

# 8. Copy rootfs and configure entrypoint
COPY rootfs/ /
# Ship the toolchain script as a user utility for runtime updates/customization
COPY scripts/install-agent-toolchain.sh /usr/local/bin/agy-install-toolchain
RUN chmod +x /usr/local/bin/entrypoint.sh \
             /usr/local/bin/agy-setup-helper \
             /usr/local/bin/agy-vdi \
             /usr/local/bin/agy-install-toolchain \
             /etc/profile.d/agy-setup-check.sh \
             /etc/profile.d/agy-toolchain.sh \
             /etc/X11/icewm/startup \
             /etc/skel/Desktop/*.desktop && \
    chmod -R ugo+rwX /etc/skel

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Dynamically link the correct version-specific wallpaper
RUN VERSION=$(grep -oP '^VERSION="\K[^"]+' /usr/local/bin/agy-setup-helper) && \
    major=$(echo "$VERSION" | cut -d. -f1) && \
    minor=$(echo "$VERSION" | cut -d. -f2) && \
    WALLPAPER_NAME="wallpaper-v${major}.${minor}.0.png" && \
    if [ -f "/usr/share/agy-box/${WALLPAPER_NAME}" ]; then \
        ln -sf "${WALLPAPER_NAME}" /usr/share/agy-box/wallpaper.png; \
    else \
        # Fallback to the latest available wallpaper if version-specific one doesn't exist
        LATEST_WALLPAPER=$(find /usr/share/agy-box/ -maxdepth 1 -name "wallpaper-v*.png" | sort -V | tail -n 1) && \
        if [ -n "$LATEST_WALLPAPER" ]; then \
            ln -sf "$(basename "$LATEST_WALLPAPER")" /usr/share/agy-box/wallpaper.png; \
        fi \
    fi

VOLUME ["/workspace", "/config"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
