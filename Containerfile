FROM quay.io/toolbx/ubuntu-toolbox:24.04@sha256:9639e52d7df33ba2e1eed97d2469e9b5af47266ff3f5b0cf9fc6319899e4a76e

LABEL org.opencontainers.image.description="Declarative Student Workspace for wtgOS Cloud-Native Laboratory"

ARG TARGETARCH

# 1. Install agent dependencies
COPY scripts/install-agent-deps.sh /tmp/
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    /tmp/install-agent-deps.sh "${TARGETARCH}" && rm /tmp/install-agent-deps.sh

# 2. Install CNCF Tooling
COPY scripts/install-tools.sh /tmp/
RUN /tmp/install-tools.sh "${TARGETARCH}" && rm /tmp/install-tools.sh

# 3. Install Antigravity Toolchain (Option A: Batteries-Included Image for authentic SBOM)
COPY scripts/install-agent-toolchain.sh /tmp/
RUN --mount=type=cache,target=/root/.cache/uv,sharing=locked \
    --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    --mount=type=cache,target=/root/.npm,sharing=locked \
    UV_LINK_MODE=copy /tmp/install-agent-toolchain.sh --system && rm /tmp/install-agent-toolchain.sh

# 4. Copy rootfs and configure entrypoint
COPY rootfs/ /
# Ship the toolchain script as a user utility for runtime updates/customization
COPY scripts/install-agent-toolchain.sh /usr/local/bin/agy-install-toolchain
RUN chmod +x /usr/local/bin/entrypoint.sh \
             /usr/local/bin/agy-setup-helper \
             /usr/local/bin/agy-vdi \
             /usr/local/bin/agy-install-toolchain \
             /usr/local/bin/agy-install-ide \
             /etc/profile.d/agy-setup-check.sh \
             /etc/profile.d/agy-toolchain.sh \
             /etc/X11/icewm/startup \
             /etc/skel/Desktop/*.desktop && \
    chmod -R ugo+rwX /etc/skel

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Pre-create unprivileged sandbox user (agyuser) with passwordless sudo and default password
RUN groupadd -o -g 9000 agygroup && \
    useradd -o -u 9000 -g 9000 -G sudo -d /home/agyuser -m -s /bin/bash agyuser && \
    printf 'agyuser:agyuser\n' | chpasswd && \
    mkdir -p /etc/sudoers.d && \
    printf 'agyuser ALL=(ALL:ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/agyuser && \
    chmod 0440 /etc/sudoers.d/agyuser

VOLUME ["/workspace", "/config"]

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["sleep", "infinity"]
