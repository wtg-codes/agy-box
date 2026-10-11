# 🏛️ agy-box System Architecture & Specifications

This directory contains technical specifications and Architectural Decision Records (ADRs) for the **`agy-box`** declarative Distrobox workspace container.

---

## 📑 Architecture Documents & References

### Core Architecture & User Documentation
- **[System Architecture Guide (`../architecture.md`)](../architecture.md)** — Comprehensive architectural walkthrough: layered topology, host-to-container bridging, D-Bus session keyring pipelines, IPC protocol bridges, interactive setup assistant sequence flows, and CI/CD pipelines.
- **[Complete User Guide (`../USER_GUIDE.md`)](../USER_GUIDE.md)** — 7-chapter definitive guide covering all four ways to work, modern IDE deep dive, Google AI & local model auth, agentic engineering, and disaster recovery.
- **[Setup & Troubleshooting Guide (`../SETUP.md`)](../SETUP.md)** — System requirements, host prerequisites (Podman, Docker, Distrobox), and solutions to common obstacles.
- **[User Settings Schema Reference (`../settings-reference.md`)](../settings-reference.md)** — Comprehensive mapping of configuration files, directories, and environment variables across `~/.config/agy-box/home` and the host.

---

## 📑 Architectural Decision Records (ADRs)

Key architectural decisions for `agy-box` are documented under the [adr/](adr/) directory:

- **[ADR 0001: Distrobox Sandbox Base](adr/0001-distrobox-sandbox-base.md)** — Selection of Distrobox and rootless container virtualization (Podman / Docker) as the isolation mechanism.
- **[ADR 0002: D-Bus Keyring Decryption](adr/0002-dbus-keyring-decryption.md)** — Forwarding host D-Bus session bus to allow secure GNOME Keyring access inside the sandbox.
- **[ADR 0003: Headless noVNC Display Routing](adr/0003-headless-novnc-display-routing.md)** — Serving IceWM desktop over HTML5 noVNC (`http://localhost:6080`) for headless servers, remote VMs, and browser access.
- **[ADR 0004: Setup Assistant Profile Hook](adr/0004-setup-assistant-profile-hook.md)** — Automated first-run environment diagnostics, git identity check, and optional host profile seeding hook.
