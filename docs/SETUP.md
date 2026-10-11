# Setup and Troubleshooting Guide

This guide details the system prerequisites, installation instructions, and resolutions for common issues when setting up and running the `agy-box` workspace environment.

---

## 1. System Requirements & Prerequisites

To run `agy-box`, your host machine requires:
- **Linux OS on x86_64 (amd64) or aarch64 (arm64)** (with systemd and standard user namespaces enabled). The `ghcr.io/wtg-codes/agy-box` image is published natively for both `linux/amd64` and `linux/arm64`, supporting PCs, servers, NVIDIA DGX Spark workstations, Apple Silicon (Asahi Linux), and ChromeOS Crostini.
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

- **The Fix (`agy-box-manager`):** `agy-box-manager` honors `DBX_CONTAINER_MANAGER` when set in your environment (as long as the binary exists on `$PATH`). Simply export the variable before running manager commands:
  ```bash
  export DBX_CONTAINER_MANAGER="docker"
  agy-box-manager install
  ```

- **The Fix (plain Distrobox):** Create a configuration file at `~/.distroboxrc` on your host and manually define the execution runtime:
  ```bash
  # Force Docker engine globally
  DBX_CONTAINER_MANAGER="docker"
  ```
  Alternatively, you can set this variable in your host environment before calling `distrobox` directly:
  ```bash
  export DBX_CONTAINER_MANAGER="docker"
  distrobox enter agy-box
  ```

> [!TIP]
> If `DBX_CONTAINER_MANAGER` is unset or points to a binary not found on `$PATH`, `agy-box-manager` will automatically fall back to Podman (if installed), followed by Docker.

---

### Q5: How do I configure my environment with the First-Run Setup Wizard?
> [!NOTE]
> `agy-box-manager` provides an interactive setup wizard that prompts you for your preferred container engine, keyring security mode, default IDE, and profile seeding preferences.

Run:
```bash
agy-box-manager wizard
```
To set up all default values non-interactively without prompts:
```bash
agy-box-manager wizard --defaults
```
Your choices are saved to `~/.config/agy-box/config.env`.

---

### Q6: What if I don't want the container to access my host keyring or host dotfiles?
> [!IMPORTANT]
> If you work in sensitive, multi-tenant, or air-gapped environments, you may wish to prevent the container from accessing your host GNOME Keyring / KWallet, SSH keys, or cloud credentials.

Set `AGY_KEYRING_MODE="isolated"` and `AGY_PROFILE_SEEDING="false"` in `~/.config/agy-box/config.env`:
```bash
AGY_KEYRING_MODE="isolated"
AGY_PROFILE_SEEDING="false"
```
Or select **"isolated"** and **"false"** during `agy-box-manager wizard`.
When isolated mode is active:
* The container's D-Bus connection to the host session bus is severed (`--unsetenv=DBUS_SESSION_BUS_ADDRESS`).
* Python Keyring stores encrypted credentials inside a container-isolated file keyring (`keyrings.alt.file.EncryptedKeyring`).
* Your host `~/.ssh`, `~/.config/gcloud`, and `~/.gitconfig` are not mounted into the container.

