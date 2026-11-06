# agy-box System Architecture & Design Guide

This document provides a deep dive into the inner workings of the `agy-box` developer sandbox, detailing how it achieves seamless host integration, manages graphical rendering, secures credentials, and facilitates first-time configuration.

> 🖼️ **Diagrams:** all figures below are rendered from the Mermaid sources in [`docs/diagrams/*.mmd`](../diagrams/) into [`docs/diagrams/rendered/`](../diagrams/rendered/) (SVG and PNG) automatically after merge to `main`.

---

## 1. System Topology & Bridging

Unlike typical sandbox runtimes that completely isolate applications, `agy-box` uses **Distrobox** (on top of Podman or Docker) to act as a **host-integrated developer environment**.

![agy-box System Topology](../diagrams/rendered/system-topology.svg)

---

## 2. Interactive Setup Assistant Sequence Flow

When a user opens an interactive shell session in the `agy-box` container for the first time, a hook in `/etc/profile.d/agy-setup-check.sh` is triggered. The helper handles verifying the environment and setting up credentials.

![Interactive Setup Assistant Sequence Flow](../diagrams/rendered/setup-assistant.svg)

---

## 3. D-Bus session keyring pipelines

Google Chrome and Google Antigravity (Agent UI) encrypt credentials (e.g. Google sign-in tokens, saved passwords) using the host OS keyring manager (GNOME Keyring or KWallet). 

Even though the D-Bus socket is forwarded into the sandbox container by Distrobox, client applications must have the `libsecret` library installed inside the container to make method calls over D-Bus to request credentials decryption. Without `libsecret-1-0`, these apps fail to authenticate silently.

![D-Bus session keyring pipeline](../diagrams/rendered/dbus-keyring.svg)

---

## 4. Port Mappings & IPC Loops

The components of the Antigravity developer suite communicate over a series of ports and sockets inside the container loop:

![Antigravity Product Communication](../diagrams/rendered/product-communication.svg)

| Port | Protocol | Source | Target | Description |
| :--- | :--- | :--- | :--- | :--- |
| **8080** | HTTP | Python SDK (`google-antigravity`) | Google Antigravity (Agent UI) | Localhost developer API server mapping workspace canvases. |
| **9222** | WebSocket / CDP | Google Antigravity (Agent UI) | `google-chrome-stable` | Chrome DevTools Protocol port to dynamically execute web commands. |
| **5900** | RFB | VNC Clients | `x11vnc` | Internal virtual display VNC server stream (bound securely to `127.0.0.1`). |
| **6080** | HTTP / WS | Web Browsers | `websockify` / noVNC | noVNC HTML5 client portal enabling remote/VDI browser desktop access (listens on `0.0.0.0`, no password). |
| **dynamic** | WebSocket | Antigravity CLI (`agy`) | Google Antigravity (Agent UI) | Active loop coordinating lab course task completion updates. |

---

## 5. VDI Web Desktop (Headless Display Routing)

To support remote development, headless environments (e.g. Google Cloud Shell, VMs), and easy environment debugging, the workspace provides a built-in virtual desktop environment utilizing **noVNC** and **Xvfb**, started on demand by `agy-vdi` (`agy-box-manager desktop`). See [ADR-0003](adr/0003-headless-novnc-display-routing.md) for the design.

![VDI Web Desktop Headless Display Routing](../diagrams/rendered/vdi-desktop.svg)

## 6. Cloud & Alternative Deployment Architectures

Because `agy-box` is built as a self-contained, standard OCI image (`ghcr.io/wtg-codes/agy-box`, `linux/amd64` and `linux/arm64`), it can execute without the host-integration layers (such as host home folder bind-mounts or local Wayland compositor sockets) required for distrobox.

When run outside Distrobox, the image entrypoint (`/usr/local/bin/entrypoint.sh`, run under `tini`) configures an unprivileged `agyuser` (UID/GID from `PUID`/`PGID`, default `9000`) with passwordless `sudo` (`/etc/sudoers.d/agyuser`, default password `agyuser`), seeds `/etc/skel` into `/home/agyuser`, fixes ownership of `/home/agyuser`, `/workspace`, and `/config` volumes, and executes the container command (default `sleep infinity`) as that user. No desktop, VNC, or SSH service is started automatically.

### A. Standalone Headless Deployment (Cloud VMs)
When running on standard Cloud VMs (Compute Engine, EC2):
1. **Graphics Routing:** The local X11/Wayland display server is bypassed. Running `agy-vdi` inside the container (e.g. `docker exec -it <name> agy-vdi`) starts **Xvfb** at display `:99`.
2. **Display Streaming:** **x11vnc** hooks into the virtual framebuffer and streams the **IceWM** desktop (with PCManFM desktop icons) via the RFB protocol on `127.0.0.1:5900`.
3. **Web Proxying:** **websockify** translates the RFB stream into a WebSocket connection and hosts the **noVNC** HTML5 client on port `6080`, allowing remote developers to interact with the GUI directly via web browser. There is no authentication, so publish the port only behind a firewall or SSH tunnel.

### B. Devcontainer Integration (GitHub Codespaces / Coder)
When used as a devcontainer:
1. **Workspace Mounting:** The cloud provider mounts the active repository workspace folder into the container (this repository's [`.devcontainer/devcontainer.json`](../../.devcontainer/devcontainer.json) mounts it at `/workspace`).
2. **Port Forwarding:** The provider forwards the standard communication ports (e.g., `6080` for noVNC, `8080` for the Antigravity API, and `9222` for the Chrome DevTools Protocol), exposing them securely over HTTPS via OAuth proxy loops.
3. **Toolchain:** The image provides the system-level toolchain (Chrome, CNCF tools, VDI stack) plus the pre-baked Antigravity toolchain; per-user updates go into `~/.local` with `agy-install-toolchain`.

### C. Jules VM Execution Parity
When executed by the autonomous agent orchestration runtime (Jules):
1. The orchestrator spins up the image inside a sandboxed VM.
2. It bypasses GUI/Desktop services entirely, running task executors and bash verification gates directly inside the container.
3. Using the exact same image ensures that any test assertions executed in CI or on the agent's VM are consistent with the developer's local environment.

---

## 7. Image Composition

The image is built on a multi-arch Ubuntu base with a batteries-included developer toolchain baked system-wide (Option A) for complete SBOM attestation and fast startup:

| Layer | Installed by | Contents |
| :--- | :--- | :--- |
| Base | `quay.io/toolbx/ubuntu-toolbox:24.04` (pinned by digest) | Ubuntu 24.04 LTS toolbox userland (native `linux/amd64` and `linux/arm64`). |
| System deps | `scripts/install-agent-deps.sh` | git, curl, jq, Python 3, Node.js 22 LTS (NodeSource), `libsecret-1-0` + Python keyring, `tini`, `gosu`, Gum, Google Chrome (amd64) / Chromium (arm64 via xtradeb), Xvfb, x11vnc, IceWM, PCManFM, noVNC, websockify, xterm. |
| CNCF tools | `scripts/install-tools.sh` | `kubectl`, `helm`, `k9s` (pinned versions, checksum-verified for both amd64 and arm64). |
| Pre-baked toolchain (Option A) | `scripts/install-agent-toolchain.sh --system` | Google Antigravity (Agent UI), Antigravity CLI (`agy`), Gemini CLI in `/usr/local/bin` and `/opt`; Antigravity SDK and Google ADK in `/opt/agy-python` (installed with a pinned `uv` 0.13.7); plus VS Code/Zed Antigravity extensions. |
| rootfs overlay | `rootfs/` | `agy-setup-helper`, `agy-vdi`, `entrypoint.sh`, profile hook, IceWM config, desktop icons, wallpaper. |
| Runtime toolchain utility | `scripts/install-agent-toolchain.sh` | Shipped to `/usr/local/bin/agy-install-toolchain` for runtime per-user customizations. |

---

## 8. CI/CD Pipeline

The [`CI/CD` workflow](../../.github/workflows/ci.yml) builds and validates native images in parallel across `linux/amd64` (on GitHub-hosted `ubuntu-24.04`) and `linux/arm64` (on the self-hosted DGX Spark runners, `[self-hosted, Linux, ARM64, dgx-spark]`, with the persistent `dgx-spark-builder` BuildKit cache). Pull requests run every check but never push; pushes to `main` and `v*` tags additionally publish multi-arch images.

```mermaid
flowchart LR
    trigger["PR / push to main / v* tag"] --> lint["Lint Codebase<br/>yamllint, ShellCheck, hadolint"]
    trigger --> bats["Run Script Tests<br/>Bats"]
    trigger --> build_amd64["Build Image (amd64)<br/>ubuntu-24.04"]
    trigger --> build_arm64["Build Image (arm64)<br/>DGX Spark self-hosted"]
    build_amd64 --> itest_amd64["Distrobox tests (amd64)<br/>scripts/test-box.sh"]
    build_arm64 --> itest_arm64["Distrobox tests (arm64)<br/>scripts/test-box.sh"]
    build_amd64 --> sbom_amd64["Syft SBOM (amd64)"]
    build_arm64 --> sbom_arm64["Syft SBOM (arm64)"]
    sbom_amd64 --> grype_amd64["Grype scan (amd64)"]
    sbom_arm64 --> grype_arm64["Grype scan (arm64)"]
    itest_amd64 --> push_amd64{"main or tag?"}
    itest_arm64 --> push_arm64{"main or tag?"}
    push_amd64 -- "yes" --> digest_amd64["Push amd64 digest"]
    push_arm64 -- "yes" --> digest_arm64["Push arm64 digest"]
    lint --> publish["Publish & Release"]
    bats --> publish
    digest_amd64 --> publish
    digest_arm64 --> publish
    publish --> manifest["Create multi-arch manifest<br/>docker buildx imagetools create"]
    manifest --> tags["Tag multi-arch index<br/>latest + main, or X.Y.Z + X.Y"]
    tags --> prov["Build provenance attestation"]
    prov --> release{"v* tag?"}
    release -- "yes" --> gh["GitHub Release<br/>+ sbom.spdx.json"]
```

Notes:
- Native multi-arch builds (`amd64` and `arm64`) run in parallel on native runners (GitHub-hosted amd64, self-hosted DGX Spark arm64) without QEMU emulation.
- Full hardware support for Intel/AMD x86_64, NVIDIA DGX Spark workstations (Grace Blackwell), Apple Silicon, and ChromeOS Crostini.
- The SBOMs are published as workflow artifacts and release assets, scanned by Grype in CI.
- [`pages.yml`](../../.github/workflows/pages.yml) deploys `docs/` to [GitHub Pages](https://wtg-codes.github.io/agy-box/) on every push to `main`; [`compile-diagrams.yml`](../../.github/workflows/compile-diagrams.yml) re-renders `docs/diagrams/*.mmd` to `docs/diagrams/rendered/` when the sources change on `main`. [Dependabot](../../.github/dependabot.yml) keeps GitHub Actions and the base image digest current.

---

## 9. Architectural Decision Records (ADRs)

The following architectural decision records document the technical reasoning and trade-offs for core system designs:

- [ADR-0001: Distrobox Sandbox Base](adr/0001-distrobox-sandbox-base.md)
- [ADR-0002: Credentials Decryption via D-Bus Session Keyring Forwarding and libsecret](adr/0002-dbus-keyring-decryption.md)
- [ADR-0003: Virtual Desktop Display Routing](adr/0003-headless-novnc-display-routing.md)
- [ADR-0004: Interactive Setup Assistant Hook](adr/0004-setup-assistant-profile-hook.md)
