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

---

### Q5: Keyring access fails or credentials are not persisted across container sessions.
> [!NOTE]
> **Why it happens:** D-Bus session forwarding from the host is either not configured correctly, or you are running in a headless or SSH session without a running host D-Bus daemon.

- **The Fix:** Run the `agy-setup-helper` tool manually. It will detect the missing keyring environment and offer to initialize a fallback file-based encrypted keyring:
  ```bash
  agy-setup-helper
  ```
  This configures `keyrings.alt.file.EncryptedKeyring` and saves the password securely inside `~/.config/environment.d/agy-box.conf`.

---

### Q6: Chrome fails to start or crashes with 'No usable sandbox' errors inside the container.
> [!WARNING]
> **Why it happens:** Standard container engines restrict the creation of user namespaces inside containers by default, which blocks Chrome's built-in multi-process sandboxing mechanism.

- **The Fix:** Do not run raw `/usr/bin/google-chrome`. Instead, use the pre-installed Google Chrome wrapper script `/usr/bin/google-chrome-stable` (which is configured by default for all tools). This wrapper launches Chrome with the `--no-sandbox` and `--disable-dev-shm-usage` flags, which are safe for containers.

---

### Q7: The Android SDK / ADB does not detect physical devices connected via USB.
> [!IMPORTANT]
> **Why it happens:** The container sandbox does not have hardware-level access to the host's USB subsystem, or the permissions are blocked.

- **The Fix:** Make sure your host has the proper `udev` rules configured for your Android device. Then, recreate the container with access to `/dev/bus/usb`:
  ```bash
  # In ~/.distroboxrc or when creating the container, ensure usb dev is mounted:
  distrobox create --name agy-box-dev --additional-flags "--volume /dev/bus/usb:/dev/bus/usb" --yes
  ```

---

### Q8: How do I upgrade my agy-box container without losing my code or settings?
> [!TIP]
> **Why it works:** Because `agy-box` mounts your host home directory (`~/`) inside the container, all of your source code, configuration files, SSH keys, and custom profiles are stored on the host filesystem rather than the volatile container rootfs.

- **The Fix:** Simply pull and recreate the container using the manager CLI. Your user settings and files will be completely untouched:
  ```bash
  agy-box-manager install
  ```

---

### Q9: Security audit checks warn about "Exposed port listener (0.0.0.0)".
> [!CAUTION]
> **Why it happens:** A development server or service inside the container is binding to wildcard addresses, allowing external host systems or networks to access the port.

- **The Fix:** Configure your development web server or daemon to bind strictly to localhost (`127.0.0.1` or `::1`) rather than `0.0.0.0`. For example, in Node.js or Python Flask:
  ```python
  # Python Flask example
  app.run(host='127.0.0.1', port=8080)
  ```

---

### Q10: The Web VDI Desktop loads a blank screen or reports connection refused.
> [!WARNING]
> **Why it happens:** The VDI background services (`Xvfb`, `openbox`, `x11vnc`, `websockify`) either failed to start, had a port conflict, or encountered a GPU driver probe error.

- **The Fix:** Run the diagnostic CLI `agy-box-manager doctor` to ensure all dependencies are installed. If it checks out, terminate any conflicting processes:
  ```bash
  # Check if port 6080 is in use on the host
  ss -tulpn | grep 6080
  
  # Restart the desktop VDI service:
  agy-box-manager desktop
  ```

---

### Q11: Systemd-dependent tools fail to initialize or report systemd is not running.
> [!NOTE]
> **Why it happens:** Distrobox does not initialize user systemd daemons by default unless the container was explicitly provisioned with init support.

- **The Fix:** Recreate the distrobox container specifying the init configuration. The `agy-box-manager` CLI handles this dynamically when systemd features are configured. You can check the current init status using:
  ```bash
  agy-box-manager status
  ```

