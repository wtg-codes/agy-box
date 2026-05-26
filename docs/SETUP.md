# Setup and Troubleshooting Guide

This guide details the system prerequisites, installation instructions, and resolutions for common issues when setting up and running the `agy-box` workspace environment.

---

## 1. System Requirements & Prerequisites

To run `agy-box`, your host machine requires:
- **Linux OS** (with systemd and standard user namespaces enabled).
- **Distrobox** (version `1.4.0` or newer).
- **A compatible container engine**:
  - 🍎 **Podman** (Highly Recommended for native rootless user mappings and safety).
  - 🐳 **Docker** (Advisable with rootless configurations or user group mappings).

### Quick Installation Guides

#### Fedora / Silverblue / Kinoite:
```bash
sudo dnf install distrobox podman
```

#### Ubuntu / Debian:
```bash
sudo apt update
sudo apt install distrobox podman
```

#### Arch Linux:
```bash
sudo pacman -S distrobox podman
```

---

## 2. Common User Obstacles & Troubleshooting (FAQ)

### Q1: "Permission Denied" errors appear when modifying files inside the workspace.
> [!NOTE]
> **Why it happens:** You are using standard system Docker as your container engine instead of Podman. Docker executes as a root-level daemon. When `agy-box` writes code files or configuration assets, Docker saves them to your host's drive with root ownership, locking your local host user out.

- **The Fix (Option A - Highly Recommended):** Install Podman, which resolves user namespace mappings natively. Once installed, `agy-box-manager` will automatically prioritize it over Docker.
- **The Fix (Option B):** Add your host user to the standard system Docker group and configure rootless namespaces. Follow the [Docker Rootless Mode Documentation](https://docs.docker.com/engine/security/rootless/).
- **The Fix (Option C - Automated Fallback):** `agy-box-manager` automatically injects user/group ID mapping parameters (`--additional-flags "--user $(id -u):$(id -g)"`) to Distrobox if it detects Docker is running, but using rootless container storage is still recommended.

---

### Q2: My GUI applications or text editors refuse to open from inside the container.
> [!WARNING]
> **Why it happens:** Your host's window manager (Wayland or X11) is blocking connection attempts from outside the standard host namespace.

- **The Fix:** Grant local X11 access on your host system terminal, then enter your session:
  ```bash
  # On your host system terminal:
  xhost +local:

  # Restart or enter your environment:
  agy-box-manager enter
  ```

---

### Q3: Commands or CLI tools I exported do not work in my host terminal.
> [!IMPORTANT]
> **Why it happens:** Your system shell does not know where to look for the custom wrapper binaries exported by Distrobox.

- **The Fix:** Ensure that `~/.local/bin` is configured in your system's global `$PATH` environment variable. Add the following line to the end of your `~/.bashrc` or `~/.zshrc`:
  ```bash
  export PATH="$HOME/.local/bin:$PATH"
  ```
  Save the file, and then run `source ~/.bashrc` or restart your terminal.

---

### Q4: How do I force agy-box to use Docker even if I have Podman installed?
> [!NOTE]
> **Why it happens:** Some team environments mandate Docker or have specific proxy and registry rules defined exclusively for Docker.

- **The Fix:** Create a configuration file at `~/.distroboxrc` on your host and manually define the execution runtime:
  ```bash
  # Force Docker engine globally
  DBX_CONTAINER_MANAGER="docker"
  ```
  Alternatively, you can set this variable in your host environment before calling the manager CLI:
  ```bash
  export DBX_CONTAINER_MANAGER="docker"
  agy-box-manager
  ```
