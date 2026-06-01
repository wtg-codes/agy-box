# Settings & Configuration Variables Reference

This document maps the configuration variables and environment overrides used by `agy-box`, the `agy-box-manager` CLI, the setup assistant (`agy-setup-helper`), and the integration tests.

---

## 1. Configuration File Locations

Configuration variables inside the container are loaded from standard systemd environment configuration directories.

* **Primary Configuration File (Container):** `~/.config/environment.d/agy-box.conf` (or `~/.config/environment.d/antigravity-mcp.conf` as a legacy fallback).
  * This file is generated or updated by `agy-setup-helper`.
  * Permissions are hardened to `600` (read/write only by owner) automatically.
* **Distrobox Engine Configuration (Host):** `~/.distroboxrc`
  * Used to customize how Distrobox provisions the containers.

---

## 2. Core Workspace Configuration Variables

These variables are defined inside `~/.config/environment.d/agy-box.conf` to configure active agent services and keyring states.

| Variable Name | Default Value | Scope / Usage | Description |
| :--- | :--- | :--- | :--- |
| `GEMINI_API_KEY` | *(None)* | Google Antigravity SDK & APIs | The authentication key used to call Google Gemini / Vertex AI models. |
| `ANTIGRAVITY_API_KEY` | *(None)* | Google Antigravity Suite | Dedicated license or API key for accessing Google Antigravity cloud services. |
| `KEYRING_CRYPT_PASSWORD` | *(None)* | Python Keyring Fallback | The master password used to encrypt and decrypt the file-based fallback keyring (`keyrings.alt.file.EncryptedKeyring`) if Gnome Keyring or D-Bus session access is not available from the host. |

---

## 3. Manager CLI Environment Variables (`agy-box-manager`)

These environment variables can be set on your **host system** before running `agy-box-manager` to override default container names or images.

| Variable Name | Default Value | Description |
| :--- | :--- | :--- |
| `IMAGE_NAME` | `ghcr.io/wtg-codes/agy-box:latest` | The container image downloaded from the remote registry when running `install`. |
| `DEV_IMAGE_NAME` | `agy-box:dev` | The tag applied to the local image built from source when running `dev`. |
| `CONTAINER_NAME` | `agy-box` | The name of the registered Distrobox container for the official/stable release. |
| `DEV_CONTAINER_NAME` | `agy-box-dev` | The name of the registered Distrobox container for local development. |
| `DBX_CONTAINER_MANAGER` | *(Auto-detected)* | Forces Distrobox to use a specific engine (e.g., `podman` or `docker`). |

---

## 4. Integration Test Variables (`scripts/test-box.sh`)

These environment variables modify the behavior of the test suite when executing integration tests.

| Variable Name | Default Value | Description |
| :--- | :--- | :--- |
| `IMAGE_NAME` | `localhost/agy-box:dev` | The target image name built and tested by the integration tests. |
| `FORCE_BUILD` | `false` | Set to `true` to force a complete container build, bypassing the change-detection hash check. |
| `RUNTIME` | *(Auto-detected)* | Overrides the engine runtime runner (forces `podman` or `docker`). |

---

## 5. Host Integration & Bridge Environment Variables

These variables are injected by Distrobox or the host shell environment and are used to negotiate system-level bridging.

| Variable Name | Description |
| :--- | :--- |
| `DISTROBOX_HOST_HOME` | Points to the absolute path of the user's home directory on the host OS. Essential for profile seeding wizards. |
| `DBUS_SESSION_BUS_ADDRESS` | The socket reference address for D-Bus communication, allowing container applications to securely read passwords from the host Gnome Keyring. |
| `WAYLAND_DISPLAY` / `DISPLAY` | Forwarded display sockets used by graphical user interface components (Agent UI, IDE, and Chrome). |
