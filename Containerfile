FROM ghcr.io/ublue-os/ubuntu-toolbox:latest

LABEL org.opencontainers.image.description="Declarative Student Workspace for wtgOS Cloud-Native Laboratory"

ENV PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin

# 1. Install agent dependencies
COPY scripts/install-agent-deps.sh /tmp/
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    /tmp/install-agent-deps.sh && rm /tmp/install-agent-deps.sh

# 2. Install Google Antigravity (Agent UI)
COPY scripts/install-antigravity.sh /tmp/
RUN /tmp/install-antigravity.sh && rm /tmp/install-antigravity.sh

# 2b. Install Antigravity IDE (Stable 1.23.2)
COPY scripts/install-antigravity-ide.sh /tmp/
RUN /tmp/install-antigravity-ide.sh && rm /tmp/install-antigravity-ide.sh

# 3. Install Antigravity CLI
COPY scripts/install-antigravity-cli.sh /tmp/
RUN /tmp/install-antigravity-cli.sh && rm /tmp/install-antigravity-cli.sh

# 4. Install Antigravity SDK
COPY scripts/install-antigravity-sdk.sh /tmp/
RUN --mount=type=cache,target=/root/.cache/pip \
    /tmp/install-antigravity-sdk.sh && rm /tmp/install-antigravity-sdk.sh

# 5. Install Google ADK
COPY scripts/install-google-adk.sh /tmp/
RUN --mount=type=cache,target=/root/.cache/pip \
    /tmp/install-google-adk.sh && rm /tmp/install-google-adk.sh

# 6. Install CNCF Tooling
COPY scripts/install-tools.sh /tmp/
RUN /tmp/install-tools.sh && rm /tmp/install-tools.sh

# 7. Install Gemini CLI
COPY scripts/install-gemini-cli.sh /tmp/
RUN --mount=type=cache,target=/root/.npm \
    /tmp/install-gemini-cli.sh && rm /tmp/install-gemini-cli.sh

# 8. Copy rootfs and configure entrypoint
COPY rootfs/ /
RUN chmod +x /usr/local/bin/entrypoint.sh \
             /usr/local/bin/agy-setup-helper \
             /usr/local/bin/agy-vdi \
             /etc/profile.d/agy-setup-check.sh \
             /etc/X11/icewm/startup \
             /etc/skel/Desktop/*.desktop

# Dynamically link the correct version-specific wallpaper
RUN VERSION=$(grep -oP '^VERSION="\K[^"]+' /usr/local/bin/agy-setup-helper) && \
    major=$(echo "$VERSION" | cut -d. -f1) && \
    minor=$(echo "$VERSION" | cut -d. -f2) && \
    WALLPAPER_NAME="wallpaper-v${major}.${minor}.0.png" && \
    if [ -f "/usr/share/agy-box/${WALLPAPER_NAME}" ]; then \
        ln -sf "${WALLPAPER_NAME}" /usr/share/agy-box/wallpaper.png; \
    else \
        # Fallback to the latest available wallpaper if version-specific one doesn't exist
        LATEST_WALLPAPER=$(ls -v /usr/share/agy-box/wallpaper-v*.png 2>/dev/null | tail -n 1) && \
        if [ -n "$LATEST_WALLPAPER" ]; then \
            ln -sf "$(basename "$LATEST_WALLPAPER")" /usr/share/agy-box/wallpaper.png; \
        fi \
    fi

VOLUME ["/workspace", "/config"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
