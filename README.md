<p align="center">
  <a href="https://github.com/wtg-codes/agy-box/actions/workflows/ci.yml">
    <img src="https://img.shields.io/github/actions/workflow/status/wtg-codes/agy-box/ci.yml?branch=main&label=CI%2FCD&style=flat-square" alt="CI/CD Status">
  </a>
  <a href="https://github.com/wtg-codes/agy-box/releases">
    <img src="https://img.shields.io/github/v/release/wtg-codes/agy-box?label=Latest%20Release&style=flat-square&color=blue" alt="Latest Release">
  </a>
  <a href="https://wtg-codes.github.io/agy-box/">
    <img src="https://img.shields.io/badge/website-wtg--codes.github.io%2Fagy--box-6366f1?style=flat-square" alt="Project Website">
  </a>
  <img src="https://img.shields.io/badge/container%20base-Ubuntu%2024.04%20LTS-E95420?style=flat-square" alt="Container Base OS">
  <img src="https://img.shields.io/badge/platform-amd64%20%7C%20arm64-64748b?style=flat-square" alt="Platform: amd64 | arm64">
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-emerald?style=flat-square" alt="MIT License">
  </a>
</p>

# 📦 Antigravity Dev Box (agy-box)

`agy-box` is `agy` and friends in an isolated box fleet! This repository builds `agy-box`, an Ubuntu 24.04 LTS container environment (`quay.io/toolbx/ubuntu-toolbox:24.04`, digest-pinned, native `linux/amd64` and `linux/arm64`) pre-baked with the complete Google Antigravity agent toolchain, VS Code, Zed, Chrome/Chromium, and a browser-based IceWM noVNC VDI desktop.

By default, every box runs as a fast, standalone **Sandbox** via rootless Podman or Docker (`distrobox` not required), with optional **Workstation** mode (`--mode workstation` via Distrobox) when you want native host Wayland/X11 windows and host SecretService integration.

The published container image is **`ghcr.io/wtg-codes/agy-box`** (`:latest` tracks `main`; releases are tagged `:<major>.<minor>.<patch>` and `:<major>.<minor>`, e.g. `:0.8.0` and `:0.8`).

> 🌐 **Project website: [wtg-codes.github.io/agy-box](https://wtg-codes.github.io/agy-box/)** — quick-start command, feature tour, architecture diagrams, and command reference.

---

## Quick Start (No Clone Required)

Launch the interactive workspace manager directly from your terminal without cloning this repository:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/wtg-codes/agy-box/main/agy-box-manager)
```

*(From **System Tools**, select **"Install CLI Globally (~/.local/bin)"** to save `agy-box-manager` permanently — zero host `.bashrc`/`.zshrc` edits and zero host binary overwrites!)*

### CLI Workflow

```bash
# 1. Install the manager CLI to ~/.local/bin/agy-box-manager
agy-box-manager install-global

# 2. Pull ghcr.io/wtg-codes/agy-box:latest and create a new stable box (e.g. agy-box-golden-spark)
#    Defaults to fast isolated Sandbox mode; pass '--mode workstation' for Distrobox integration
agy-box-manager install

# 3. Enter your box shell or launch the browser VDI desktop (auto-selects when 1 box is installed)
agy-box-manager enter
agy-box-manager desktop      # http://127.0.0.1:6080/vnc.html?autoconnect=true&resize=scale&path=websockify

# 4. Inspect structured manager & container logs at any time
agy-box-manager logs
```

## Prerequisites

- **An x86_64 (amd64) or aarch64 (arm64) Linux host**: standard PCs/servers, Bluefin / Universal Blue desktops, NVIDIA DGX Spark workstations, Apple Silicon (Asahi Linux), and ChromeOS Crostini.
- **A container runtime**: **Podman** (recommended) or **Docker**.
- **Distrobox** *(optional)*: required only when explicitly requesting `--mode workstation`. Default `--mode sandbox` runs standalone on Podman or Docker.
- **Gum** *(optional)*: powers the interactive TUI menu (all CLI subcommands run without it; if missing in menu mode, the manager installs it via Homebrew when available, otherwise prints install instructions).

The manager never modifies host shell RC files or overwrites host `~/.local/bin/agy`; see the [Setup & Troubleshooting Guide](docs/SETUP.md) for per-distro container runtime setup.

## What's Inside

- **Google Antigravity** (`antigravity`, `2.31.0`) — the agent-first UI / Hub (with extracted desktop icon).
- **Antigravity CLI** (`agy`, `1.5.5`), **Google Antigravity Python SDK** (`google-antigravity`, `0.1.23`), **Google ADK** (`google-adk` / `adk`, `2.1.0`), and **Gemini CLI** (`@google/gemini-cli` / `gemini`, `0.43.0`).
- **VS Code** (`code`) and **Zed** (`zed`) pre-configured with `Google.google-antigravity` workspace recommendations and Zed `auto_install_extensions` (with user-space extension updates via `agy-install-toolchain` or `agy-box-manager update --ides`).
- **Google Chrome** (amd64) / **Chromium** (arm64) for CDP browser automation.
- **CNCF tooling**: `kubectl`, `helm`, `k9s` (pinned, checksum-verified).
- **IceWM noVNC VDI desktop** (`agy-vdi`) starting on port `6080` (`6081`, `6082`, ... automatically across multiple boxes).
- **Non-blocking container health diagnostics** (`agy-doctor`) and structured tool logs under `~/.local/state/agy-box/*.log` + host `~/.config/agy-box/logs/`.

The toolchain is baked system-wide into `/opt` and `/usr/local/bin` at build time (so the Syft SBOM is complete) and can be updated per box with `agy-install-toolchain` or `agy-box-manager update`.

## Unified Multi-Box Fleet Architecture

Every managed box is an equal peer with a permanent two-word name (`agy-box-<adj>-<noun>` on the `stable` channel, `agy-box-dev-<adj>-<noun>` when built via `agy-box-manager dev` from a non-`main` git branch) and a dedicated isolated home at `~/.config/agy-box/homes/<box-name>`:

- **Sandbox mode (`--mode sandbox`, default)**: runs standalone via rootless Podman or Docker with isolated container credentials, automatic VDI port allocation (`6080+`), and zero host credential mounts unless explicitly seeded.
- **Workstation mode (`--mode workstation`, optional)**: runs via **Distrobox** with forwarded host Wayland/X11, audio, and D-Bus SecretService (`AGY_KEYRING_MODE="host"`).

![agy-box System Topology](docs/diagrams/rendered/system-topology.svg)

See the [System Architecture Guide](docs/architecture/system-architecture.md) for the bridging model, keyring pipeline, port map, image composition, and CI/CD pipeline.

## Commands

| Action | Command | Just |
| :--- | :--- | :--- |
| Interactive TUI menu | `agy-box-manager` | `just agy` |
| Create a new stable box | `agy-box-manager install [-m sandbox\|workstation] [-i <img>] [-n <name>] [-y]` | `just agy-install` |
| Build a box from local repo | `agy-box-manager dev [-m sandbox\|workstation] [--channel stable\|dev]` | `just agy-box-dev` |
| Enter a box shell | `agy-box-manager enter [box\|stable\|dev]` | `just agy-enter` |
| Start / manage VDI web desktop | `agy-box-manager desktop [box\|stable\|dev] [-p port] [-d\|--stop\|--status]` | `just agy-desktop` |
| View manager & box logs | `agy-box-manager logs [box\|stable\|dev] [-n N] [-f] [--vdi\|--doctor\|--toolchain]` | `just agy-logs` |
| Status of all boxes & storage | `agy-box-manager status` | `just agy-status` |
| Host & box health diagnostics | `agy-box-manager doctor [box]` (alias `check`) | `just agy-doctor` |
| Update toolchain, IDEs & OS | `agy-box-manager update [box\|stable\|dev] [--all\|--check]` | `just agy-update` |
| Remove a box or all boxes | `agy-box-manager clean [box\|--all] [--purge\|--keep] [-y]` | `just agy-clean` |

When exactly one box is installed, `enter`, `desktop`, `update`, and `clean` select it automatically; with multiple boxes, pass the full name, two-word slug (`golden-spark`), or channel (`stable` / `dev`), or pick interactively in `gum`. See the [User Guide](docs/USER_GUIDE.md#8-command-reference) for the complete reference.

## Documentation

- 📘 **[User Guide](docs/USER_GUIDE.md)** — canonical handbook: quickstart, sandbox vs workstation modes, IDEs, AI authentication, CLI mastery, diagnostics & logs, cloud deployments, and FAQ.
- 🛠️ **[Setup & Troubleshooting Guide](docs/SETUP.md)** — prerequisites, rootless engine configuration, PATH setup, keyring behavior.
- 🏛️ **[System Architecture Guide](docs/architecture/system-architecture.md)** — host bridging, keyring behavior, ports, CI/CD, and ADRs.
- ⚙️ **[Settings Reference](docs/settings-reference.md)** — Antigravity and CLI settings schema.
- 🤝 **[Contributing](CONTRIBUTING.md)** — repository layout, local development workflow, CI, releases, and GHCR maintenance.
- 🗺️ **[Roadmap / TODO](TODO.md)** and **[Changelog](CHANGELOG.md)**.
- 🌐 **[Project Website](https://wtg-codes.github.io/agy-box/)** (GitHub Pages, built from [`docs/index.html`](docs/index.html)).

## Testing

`just agy-test` builds `localhost/agy-box:dev` (skipped if nothing changed; `FORCE_BUILD=true` overrides), provisions a temporary box, and runs `scripts/assert-box.sh` against it. `just agy-e2e [tag]` runs the same harness against the published `ghcr.io/wtg-codes/agy-box:<tag>` image (default `latest`) including the VDI check, and `just test-scripts` runs the Bats unit test suite across `agy-box-manager`, `agy-doctor`, and the installation scripts. See [CONTRIBUTING.md](CONTRIBUTING.md#2-local-development-workflow) for the full workflow.

## License

[MIT](LICENSE)
