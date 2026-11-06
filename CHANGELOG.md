# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

Container images are published to `ghcr.io/wtg-codes/agy-box` (`:<version>`, `:<major>.<minor>`, and `:latest` for `main`).

## [Unreleased]

- **CI/CD audit fixes**:
  - Fixed CI/CD not running on merges to `main`: a skip directive quoted in PR commit messages was copied into the squash-merge commit. The lint job now rejects PRs containing skip directives, and the diagram bot no longer uses one.
  - Fork PRs never run on the self-hosted DGX Spark runners; they fall back to GitHub-hosted `ubuntu-24.04` / `ubuntu-24.04-arm`.
  - Runs on `main`/tags are no longer cancelled mid-publish by a newer run (only PR runs are cancelled).
  - Pages deploys only when `docs/` changes on `main`, not three times per merge or after failed runs.
  - Added `actionlint`; yamllint runs as a CLI instead of a third-party action; stale workflow comments fixed.
  - The image's Antigravity SDK check now imports `Agent` and builds an offline `LocalAgentConfig`.
  - New `sdk-smoke.yml`: live, budget-capped Antigravity SDK agent turns against the DGX Spark cluster (`LocalOpenAIAgentConfig`, no cloud key) and the Gemini API (`LocalAgentConfig`, once the `GEMINI_API_KEY` secret is set).
  - `main` is now protected by the `main: require CI` ruleset (required checks, no force push or deletion). Squash merges use the PR title only. The diagram bot pushes with a deploy key, and docs-only pushes no longer rebuild the image.
- **Simplification & cleanup**:
  - **Removed Open WebUI** (`scripts/install-open-webui.sh`, `just agy-local-ui` / `agy-local-ui-dev`, and the TUI dashboard entry). It is not core to agy-box; run the official `ghcr.io/open-webui/open-webui` container next to the box if you want a local chat UI.
  - Removed the Archify interactive diagrams (`docs/diagrams/interactive/`, `docs/diagrams/sources/`) and the obsolete one-off `ghcr-retag-amd64-only.yml` workflow. `compile-diagrams.yml` renders Mermaid only, and only on pushes to `main`.
  - Merged `scripts/test-e2e.sh` into `scripts/test-box.sh` (`PULL=true`, `VDI_TEST=true`, `IMAGE_NAME=…`); `just agy-e2e [tag]` runs it against the published image.
  - `agy-box-manager`: merged `doctor` and `check` (`check` is an alias), removed the "Check Package Dependencies" menu item and host package-manager auto-installs (gum via Homebrew if present, otherwise install instructions), and removed the `just` shell-function override (`ujust agy-*` integration kept).
  - Replaced pipx with a pinned `uv` (`0.13.7`) installing the SDK and ADK into `/opt/agy-python`; base image `quay.io/toolbx/ubuntu-toolbox:24.04` pinned by digest; single `wallpaper.png` instead of versioned wallpapers.
  - CI: `amd64` builds natively on GitHub-hosted `ubuntu-24.04` and `arm64` on the DGX Spark self-hosted runners (no QEMU); added Dependabot for GitHub Actions and the base image digest.
- **Antigravity Toolchain & IDE Streamlining**:
  - **Removed legacy `antigravity-ide` (`1.23.2`)** from the container image, installer (`scripts/install-agent-toolchain.sh`), VDI desktop, and documentation in favor of the **Google Antigravity App (`antigravity` v2.0.1)**, **Antigravity CLI (`agy` v1.5.0)**, **VS Code (`code`)**, **Zed (`zed`)**, and **JetBrains IDEs (`agy-install-ide`)**.
  - Added automatic cleanup of legacy `antigravity-ide` binaries, share directories, desktop shortcuts, and config directories when running `agy-install-toolchain` / `update-toolchain`.
  - Updated `agy-vdi` browser VDI desktop startup to launch only the **Terminal (`xterm`)** automatically so users can launch Google Antigravity, VS Code, or Zed on demand from the desktop/toolbar icons.
- **Sandbox Sudo, UID/GID Alignment & Self-Hosted DGX Spark CI**:
  - Added passwordless `sudo` (`NOPASSWD:ALL`) for the container's `agyuser` (`rootfs/etc/sudoers.d/agyuser`) and dynamic `PUID`/`PGID` alignment inside isolated `--mode sandbox` containers so bind-mounted workspaces and package installation work seamlessly without permission errors ([#43]).
  - Added self-hosted ARM64 (`dgx-spark`) GitHub Actions runner orchestration with persistent `dgx-spark-builder` BuildKit cache and fast static `uv` wheel installation ([#42], [#43]).
- **Dual-Engine Architecture (Workstation vs. Sandbox)**:
  - Added native support for **Isolated Sandboxes** directly via rootless Podman or Docker (`--mode sandbox`, default for named boxes like `test1`), running with zero host mounts, isolated encrypted keyring, clean room environment, and no credential leakage.
  - Retained **Integrated Workstation** mode via Distrobox (`--mode workstation`, default for primary `agy-box`) for seamless host desktop, Wayland/audio, and SSO integration.
  - Added smart lifecycle delegation in `agy-box-manager` (`enter`, `desktop`, `clean`) that automatically inspects container labels (`manager=agy-box-podman` vs `manager=distrobox`) and dispatches commands to the right engine.
  - Added container name collision detection with interactive auto-suffixing (`name-1`, `name-2`), manual renaming, or recreate options.
  - Added isolated home directory preservation policies on deletion: `agy-clean` forces an explicit choice (Purge all data vs Keep data), with non-interactive safety guards requiring `--purge` or `--keep`.
  - Added preserved storage management in `agy-box-manager status` and an interactive TUI menu item ("📁 Manage Preserved Box Data...") to inspect and reclaim orphaned storage.
- **Container IDE Support**:
  - Pre-installed **Visual Studio Code** (`code`) and **Zed Editor** (`zed`) in the container image with multi-arch support (`amd64` and `arm64`).
  - Pre-installed/pre-configured **Antigravity extensions**: `Google.antigravity` extension pre-installed in VS Code and auto-installation configured for Zed (`~/.config/zed/settings.json`).
  - IceWM desktop launchers and application menu/toolbar entries for VS Code and Zed.
  - On-demand **JetBrains IDE installer** (`agy-install-ide`) supporting IntelliJ IDEA Community and PyCharm Community with Antigravity plugin installation, desktop shortcuts, and an interactive integration menu in `agy-setup-helper`.
  - Comprehensive health checks in `scripts/assert-box.sh` and Bats unit tests for IDE installation and toolchain extensions.

## [0.6.0] - 2026-10-03

### Added
- **Local Workspace Web Dashboard**: [Open WebUI](https://github.com/open-webui/open-webui) is bundled in the image, with `just agy-local-ui` (port 8080, requires an Ollama backend on port 11434) and an isolated `just agy-local-ui-dev` instance (port 8081), plus an interactive-menu entry in `agy-box-manager` ([#22]).
- **Host profile seeding** in `agy-setup-helper`: an optional one-time copy of Chrome, Antigravity, and Antigravity IDE settings from the host into the box's isolated home, with `chromeBinaryPath` patched to the container's Chrome ([#16]).
- **Stale lock cleanup** in `agy-vdi`: stale X11 and Chrome/Electron `SingletonLock` files are removed on startup, fixing "profile in use by another computer" errors after a container is recreated ([#16]).
- **GitHub Pages landing page** at <https://wtg-codes.github.io/agy-box/> (`docs/index.html`) with an automatic deployment workflow ([#17]).
- **Linting in CI**: yamllint (strict), ShellCheck, and hadolint ([#18]).
- **Bats unit tests** for the installation scripts (`tests/install_scripts.bats`, `just test-scripts`) ([#18]).
- **Supply-chain security**: SPDX SBOM generation with Syft and Grype vulnerability scanning on every build; the SBOM is attached to GitHub Releases ([#19], [#23], [#24]).
- **Architecture documentation**: Mermaid diagram sources with rendered SVG/PNG, an automatic diagram compilation workflow, and Architecture Decision Records ADR-0001 to ADR-0004 ([#21]).
- `CHANGELOG.md`, and a "Possible future work" section in `TODO.md`.
- Added official v0.6.0 high-resolution wallpaper asset (`rootfs/usr/share/agy-box/wallpaper-v0.6.0.png`).

### Changed
- **Component separation**: the Antigravity Agent UI, Antigravity IDE, Antigravity CLI (`agy`), Antigravity SDK, Google ADK, and Gemini CLI are no longer baked into the image. They are installed per user into `~/.local` by `scripts/install-agent-toolchain.sh` ([#19]); `agy-box-manager install` runs the installer inside the box via `agy-install-toolchain` (toolchain user-path fix PR).
- **Base image pinned by digest**: `ghcr.io/ublue-os/ubuntu-toolbox` (Ubuntu 26.04 LTS) instead of the floating `:latest` tag.
- **Dependency pinning**: `kubectl` 1.36.1, `helm` 3.21.0, `k9s` 0.50.18 (checksum-verified), Gum 0.17.0, Antigravity SDK 0.1.0, Google ADK 2.1.0, Gemini CLI 0.43.0 ([#18]).
- **IceWM configuration** moved from `/etc/icewm/` to the standard `/etc/X11/icewm/`; desktop launchers are executable, and the Antigravity CLI launcher starts in the home directory ([#16]).
- **Open WebUI install**: now installed with `uv` into an isolated `/opt/open-webui-venv` (Python 3.12) with **CPU-only PyTorch**, avoiding ~4.5 GB of NVIDIA CUDA libraries (previously installed with `pipx`) ([#24]).
- **CI/CD overhaul**: the image is built once, tested with the Distrobox integration suite, scanned, and the exact same build is pushed to GHCR by digest; tags (`latest`/`main`, or `X.Y.Z`/`X.Y` for releases) and the build provenance attestation are applied only after every check passes. PRs build and test but never push. The SBOM is generated once and Grype scans the SBOM instead of re-cataloging the image ([#23], [#24]).
- **GitHub Actions** upgraded off the deprecated Node 20 runtime (`actions/checkout` v7, `actions/upload-artifact` v7, `actions/download-artifact` v8, `actions/attest-build-provenance` v4, `actions/configure-pages` v6, `actions/upload-pages-artifact` v5, `actions/deploy-pages` v5, `actions/setup-node` v7, `docker/setup-buildx-action` v4, `docker/metadata-action` v6, `docker/build-push-action` v7, `docker/login-action` v4, `softprops/action-gh-release` v3, `stefanzweifel/git-auto-commit-action` v7, `hadolint/hadolint-action` v3.5.0); the Mermaid compile job now runs Node.js 24.
- ShellCheck in CI now also covers `agy-setup-helper`, `agy-vdi`, and the IceWM startup script.
- Documentation (README, CONTRIBUTING, architecture and setup guides, diagrams, Pages site) updated to describe the current image, toolchain, VDI desktop (IceWM), and CI/CD pipeline; broken absolute `file://` links replaced with relative links.

### Removed
- **arm64 images**: only `linux/amd64` is built and published. The upstream base image is amd64-only, so the previously published "arm64" images were actually amd64 userland built under QEMU ([#24]).
- **`actions/attest-sbom`** registry attestation: the SBOM of the multi-GB image exceeds the 16 MB attestation size limit. The SBOM remains available as a workflow artifact and a release asset ([#24]).
- Unused per-component install scripts superseded by `scripts/install-agent-toolchain.sh` (`install-antigravity.sh`, `install-antigravity-ide.sh`, `install-antigravity-cli.sh`, `install-antigravity-sdk.sh`).

### Fixed
- `just agy-local-ui` / `agy-local-ui-dev` stored Open WebUI data in a literal `~` directory (quoted tilde in `DATA_DIR`); they now use `$HOME/.config/agy-local-ui[-dev]`.
- Released images now actually provide the Antigravity toolchain to users (toolchain user-path fix PR); since [#19] it was only installed by the CI test harness.

## [0.5.0] - 2026-05-27

### Added
- VDI desktop enhancements: IceWM desktop with PCManFM desktop icons, wallpaper, taskbar and launchers; redesigned integration testing workflow ([#13], [#14], [#15]).
- Hybrid home isolation (`~/.config/agy-box/home`) with read-only host `~/.ssh`, `~/.config/gcloud`, and `~/.gitconfig` mounts, and Developer Skills Pack auto-install.
- Spinners with error logging for image pulls, dev builds, container creation, and exports.
- README documentation of all four Antigravity suite components.

### Changed
- VDI default resolution raised to 1920x1080 with auto-scaling and LAN access.
- Interactive menu refactored into a state machine with compact headers.
- "Antigravity 2.0" renamed to "Google Antigravity (Agent UI)"; Antigravity state isolated per box.
- Distrobox containers are created with custom hostnames.

### Fixed
- VDI terminal loss on hosts with pre-existing tint2 configurations.
- `EACCES` permission errors inside the VDI, and an unbound variable in `cmd_install_official`.

## [0.4.2] - 2026-05-26

First tagged release.

### Added
- `agy-box-manager` interactive CLI and `justfile` recipes (with `just`/`ujust` shell integration) to install, build, enter, and remove the box.
- Antigravity Agent UI, Antigravity IDE ([#12]), Antigravity CLI, Antigravity SDK, Google ADK, Gemini CLI, Google Chrome, and CNCF tools in the image.
- First-time setup assistant (`agy-setup-helper`) with keyring, API key, Chrome, and Git checks.
- noVNC VDI desktop (`agy-vdi`) with dynamic resolution, startup health checks, and Wayland-leak guards.
- Shell autocompletion, user-mode systemd support, keyring cache fallback, port mapping dashboard ([#6]), SSH-agent forwarding ([#7]), container resource limits ([#8]), devcontainer template ([#9]), workspace state sync ([#10]), and doctor diagnostics ([#11]).
- Unified CI/CD workflow with lint, build, test, SBOM, and attestation jobs, and automatic GitHub Releases on `v*` tags.

[Unreleased]: https://github.com/wtg-codes/agy-box/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/wtg-codes/agy-box/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/wtg-codes/agy-box/compare/v0.4.2...v0.5.0
[0.4.2]: https://github.com/wtg-codes/agy-box/releases/tag/v0.4.2
[#6]: https://github.com/wtg-codes/agy-box/pull/6
[#7]: https://github.com/wtg-codes/agy-box/pull/7
[#8]: https://github.com/wtg-codes/agy-box/pull/8
[#9]: https://github.com/wtg-codes/agy-box/pull/9
[#10]: https://github.com/wtg-codes/agy-box/pull/10
[#11]: https://github.com/wtg-codes/agy-box/pull/11
[#12]: https://github.com/wtg-codes/agy-box/pull/12
[#13]: https://github.com/wtg-codes/agy-box/pull/13
[#14]: https://github.com/wtg-codes/agy-box/pull/14
[#15]: https://github.com/wtg-codes/agy-box/pull/15
[#16]: https://github.com/wtg-codes/agy-box/pull/16
[#17]: https://github.com/wtg-codes/agy-box/pull/17
[#18]: https://github.com/wtg-codes/agy-box/pull/18
[#19]: https://github.com/wtg-codes/agy-box/pull/19
[#21]: https://github.com/wtg-codes/agy-box/pull/21
[#22]: https://github.com/wtg-codes/agy-box/pull/22
[#23]: https://github.com/wtg-codes/agy-box/pull/23
[#24]: https://github.com/wtg-codes/agy-box/pull/24
