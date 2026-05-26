FROM ghcr.io/ublue-os/ubuntu-toolbox:latest

LABEL org.opencontainers.image.description="Declarative Student Workspace for wtgOS Cloud-Native Laboratory"

ENV PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin

# 1. Install agent dependencies
COPY scripts/install-agent-deps.sh /tmp/
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    /tmp/install-agent-deps.sh && rm /tmp/install-agent-deps.sh

# 2. Install Google Antigravity 2.0
COPY scripts/install-antigravity-2.0.sh /tmp/
RUN /tmp/install-antigravity-2.0.sh && rm /tmp/install-antigravity-2.0.sh

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
RUN chmod +x /usr/local/bin/entrypoint.sh

VOLUME ["/workspace", "/config"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
