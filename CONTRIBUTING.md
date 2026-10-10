# Contributing to agy-box

Thank you for your interest in contributing to `agy-box`! This guide outlines how to set up your local development environment, explains the repository layout, and reviews code contribution workflows.

> 🌐 New here? The [project website](https://wtg-codes.github.io/agy-box/) gives a quick visual overview of what the box contains.

---

## 1. Repository Layout

The repository is structured as a Distrobox overlay template:

- 📄 **[Containerfile](Containerfile)**: Image definition. Based on `quay.io/toolbx/ubuntu-toolbox:24.04` (Ubuntu 24.04 LTS, multi-arch `linux/amd64` and `linux/arm64`).
- 📂 **[rootfs/](rootfs)**: Files copied directly into the root filesystem (`/`) of the container during the build.
  - 📂 **[rootfs/etc/profile.d/agy-setup-check.sh](rootfs/etc/profile.d/agy-setup-check.sh)**: Hook that launches the interactive setup helper on first interactive TTY shell login.
  - 📂 **[rootfs/usr/local/bin/agy-setup-helper](rootfs/usr/local/bin/agy-setup-helper)**: Interactive first-time CLI helper verifying API keys, D-Bus, Chrome version, and Git setups. Its `VERSION` variable is the image version (it also selects the versioned wallpaper).
  - 📂 **[rootfs/usr/local/bin/agy-vdi](rootfs/usr/local/bin/agy-vdi)**: Starts the noVNC VDI desktop (Xvfb, IceWM, x11vnc, websockify).
  - 📂 **[rootfs/usr/local/bin/entrypoint.sh](rootfs/usr/local/bin/entrypoint.sh)**: Custom entrypoint running inside the container to align sandbox user permissions.
  - 📂 **[rootfs/etc/X11/icewm/](rootfs/etc/X11/icewm)** and **[rootfs/etc/skel/](rootfs/etc/skel)**: IceWM desktop configuration, desktop icons, and default user settings.
- 📂 **[scripts/](scripts)**: Package dependency configuration and helper scripts.
  - 📄 **[scripts/install-agent-deps.sh](scripts/install-agent-deps.sh)**: Installs basic dependencies and system-level requirements (like `libsecret-1-0` for keyring mapping, Chrome, the VDI stack, and Gum).
  - 📄 **[scripts/install-open-webui.sh](scripts/install-open-webui.sh)**: Installs Open WebUI into `/opt/open-webui-venv` with `uv` and CPU-only PyTorch.
  - 📄 **[scripts/install-tools.sh](scripts/install-tools.sh)**: Installs pinned, checksum-verified CNCF tools (`kubectl`, `helm`, `k9s`).
  - 📄 **[scripts/install-agent-toolchain.sh](scripts/install-agent-toolchain.sh)**: Antigravity toolchain installer (Agent UI, IDE, `agy` CLI, SDK, ADK, Gemini CLI). Baked system-wide into `/usr/local/bin` and `/opt` during image build (Option A) for authentic Syft SBOM & Grype scanning, and shipped as `/usr/local/bin/agy-install-toolchain` for runtime per-user customizations.
  - 📄 **[scripts/test-box.sh](scripts/test-box.sh)**: Integration test harness that builds the image, creates a temporary distrobox, installs the toolchain, and runs the assertions.
  - 📄 **[scripts/assert-box.sh](scripts/assert-box.sh)**: Assertions asserting that all commands are functional inside the sandbox.
- 📂 **[tests/](tests)**: Bats unit tests for the installation scripts.
- 📂 **[docs/](docs)**: Architecture guide, setup guide, ADRs, Mermaid diagram sources (`docs/diagrams/*.mmd`) with their rendered SVG/PNG, and the GitHub Pages site (`docs/index.html`).
- 📄 **[agy-box-manager](agy-box-manager)**: The central interactive terminal menu tool to install, run, or remove container environments.
- 📄 **[justfile](justfile)**: Standard automation recipes.

---

## 2. Local Development Workflow

To make code changes and test them locally:

### Step 1: Make your changes
Edit scripts, `Containerfile`, or rootfs configurations.

### Step 2: Run the fast checks
These do not need an image build:
```bash
yamllint -c .yamllint.yml .
shellcheck scripts/*.sh agy-box-manager
hadolint Containerfile
just test-scripts   # Bats unit tests (falls back to a bats container if bats is not installed)
```

### Step 3: Build the development image
Build a local container image named `localhost/agy-box:dev` from your files:
```bash
# Using agy-box-manager:
./agy-box-manager dev

# Or using just:
just agy-box-dev
```

### Step 4: Run integration tests
Verify that your changes didn't break any application binaries or configurations inside the container:
```bash
just agy-test
```

### Editing diagrams
Edit the Mermaid sources in `docs/diagrams/*.mmd` only. The [`compile-diagrams.yml`](.github/workflows/compile-diagrams.yml) workflow re-renders `docs/diagrams/rendered/*.svg|png` and commits them back to your branch automatically (commit message tagged `[skip ci]`, so push a follow-up commit if you need CI to run on the final head).

---

## 3. Pull Request & Commit Guidelines

- **Branching**: Create feature branches starting from `main` (e.g. `feat/my-awesome-improvement`).
- **Commit Messages**: We enforce standard conventional commit styles:
  - `feat: add awesome new feature`
  - `fix: correct D-Bus keyring validation checks`
  - `docs: update system topology diagram`
  - `style: lint cleanup`
- **CI Pipelines**: On every pull request, GitHub Actions lints the repository (yamllint, ShellCheck, hadolint), runs the Bats tests, builds the `linux/amd64` image, runs the Distrobox integration test suite against it, and generates an SBOM plus an informational Grype vulnerability scan. Pull requests never push images to GHCR. Make sure all local lints and tests pass before pushing!
- **Releases**: Maintainers bump `VERSION` in `agy-box-manager` and `rootfs/usr/local/bin/agy-setup-helper` (plus the version shown in `docs/index.html`), merge to `main`, and push a `v<version>` tag. See [Releases](README.md#releases).

---

## 4. Container registry maintenance (GHCR)

Two manual-first workflows maintain `ghcr.io/wtg-codes/agy-box`. Both run in the `ghcr-maintenance` concurrency group, use only the workflow's `GITHUB_TOKEN` (`packages: write`), and default to **dry run**.

- **[ghcr-retag-amd64-only.yml](.github/workflows/ghcr-retag-amd64-only.yml)** (one-off, *Actions → GHCR re-tag legacy images → Run workflow*): images published before PR #24 contain a QEMU-built "arm64" entry that is really amd64 userland. For every tag whose index lists a non-amd64 platform, it re-points the tag to an index containing only the original `linux/amd64` manifest and its attestation manifest (`docker buildx imagetools create --platform linux/amd64`; nothing is rebuilt, manifest digests are unchanged). Already amd64-only tags (`latest`, `main`, releases) and `sha256-*` referrer tags are never touched. Inputs: `dry_run` (default `true`), `tags` (optional subset).
- **[ghcr-cleanup.yml](.github/workflows/ghcr-cleanup.yml)** (weekly + manual): deletes untagged image versions with [`dataaxiom/ghcr-cleanup-action`](https://github.com/dataaxiom/ghcr-cleanup-action), which understands image indexes, BuildKit attestation manifests and sigstore referrers and never deletes a digest still referenced by a tagged image. Only images older than `older_than` (default `1 day`) are considered, so in-flight CI pushes are safe. Scheduled runs stay dry runs until the repository variable `GHCR_CLEANUP_ENABLED` is set to `true`.

One-time order after the re-tag workflow lands: run the re-tag with `dry_run=true` and review → run it with `dry_run=false` → run the cleanup with `dry_run=true` (`older_than: 1 hour`, no CI/CD run in progress) and review → run the cleanup with `dry_run=false`. The old multi-arch indexes are then untagged and get removed together with their fake-arm64 children.
