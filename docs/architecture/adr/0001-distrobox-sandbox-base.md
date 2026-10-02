# ADR-0001: Distrobox Sandbox Base

## Status
Accepted

## Context
Developers using the `bluefin-wtg` ecosystem and other Linux distributions need a consistent developer workspace that includes the Google Antigravity developer suite, dependencies, CLI, SDK, and CNCF tools. Traditional containerization or virtual machine setups isolate the developer environment completely, which introduces several friction points:
- Graphical user interface (GUI) applications like Google Chrome and Google Antigravity (Agent UI) cannot render natively on the host desktop.
- Accessing host files, host configuration, SSH keys, and Git configurations requires manual, complex mount configurations.
- Inter-process communication (IPC) and local socket sharing between containerized dev tools and the host OS are difficult to set up.
- Connecting external USB hardware devices (e.g., Android devices via ADB) for hardware debugging is cumbersome.

A solution is needed that provides the safety and reproducibility of containerization while retaining the seamless hardware, file system, and GUI integration of the host operating system.

## Decision
We utilize **Distrobox** on top of a rootless container engine (**Podman** or **Docker**) as the base architecture for the `agy-box` developer sandbox. The container image is layered from the Ubuntu toolbox image (`ghcr.io/ublue-os/ubuntu-toolbox:latest`) via `Containerfile`.

Distrobox manages the container lifecycle and automatically handles:
1. **Home Directory Bind-Mount**: Mounts the host user's home directory (`~/`) directly into the container to share files, project workspaces, and configuration files.
2. **GUI Socket Forwarding**: Mounts host X11 and Wayland sockets (`/tmp/.X11-unix` and `$WAYLAND_DISPLAY`) and shares GPU devices (`/dev/dri`) to allow sandbox GUI applications to render natively on the host windowing system.
3. **Network Sockets Integration**: Configures shared network loops so containerized servers (e.g., the Antigravity API server on port `8080`) can communicate directly with host browsers and IDEs on `localhost`.
4. **Subsystem and Hardware Sharing**: Automatically forwards audio devices (PipeWire/PulseAudio) and USB devices (`/dev/bus/usb` for Android ADB) to support full hardware and multimedia integration.

## Consequences
### Trade-offs
- **What becomes easier**:
  - Zero-configuration GUI application rendering (e.g., Chrome, Agent UI).
  - Instant access to host project folders and configuration files without explicit volume mounting.
  - Seamless hardware debugging with local physical Android devices.
  - Simplified multi-distribution compatibility (especially on immutable/atomic hosts).
- **What becomes harder**:
  - **Reduced Isolation**: Since the host home directory is mounted inside the container, a malicious process inside the container could modify files in the host home directory. This is mitigated by running the container engine strictly in **rootless mode**.
  - **Dependency on Host Configs**: Host configuration files (e.g., shell profiles, custom dotfiles) can bleed into the container, potentially causing compatibility or styling conflicts if the container's shell environment differs.
