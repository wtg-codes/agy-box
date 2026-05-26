# Contributing to agy-box

Thank you for your interest in contributing to `agy-box`! This guide outlines how to set up your local development environment, explains the repository layout, and reviews code contribution workflows.

---

## 1. Repository Layout

The repository is structured as a Distrobox overlay template:

- 📂 **[rootfs/](file:///var/home/wtg/Repos/agy-box/rootfs)**: Files copied directly into the root filesystem (`/`) of the container during the build.
  - 📂 **[rootfs/etc/profile.d/agy-setup-check.sh](file:///var/home/wtg/Repos/agy-box/rootfs/etc/profile.d/agy-setup-check.sh)**: Hook that launches the interactive setup helper on first interactive TTY shell login.
  - 📂 **[rootfs/usr/local/bin/agy-setup-helper](file:///var/home/wtg/Repos/agy-box/rootfs/usr/local/bin/agy-setup-helper)**: Interactive first-time CLI helper verifying API keys, D-Bus, Chrome version, and Git setups.
  - 📂 **[rootfs/usr/local/bin/entrypoint.sh](file:///var/home/wtg/Repos/agy-box/rootfs/usr/local/bin/entrypoint.sh)**: Custom entrypoint running inside the container to align sandbox user permissions.
- 📂 **[scripts/](file:///var/home/wtg/Repos/agy-box/scripts)**: Package dependency configuration and helper scripts.
  - 📄 **[scripts/install-agent-deps.sh](file:///var/home/wtg/Repos/agy-box/scripts/install-agent-deps.sh)**: Installs basic dependencies and system-level requirements (like `libsecret-1-0` for keyring mapping).
  - 📄 **[scripts/install-antigravity-2.0.sh](file:///var/home/wtg/Repos/agy-box/scripts/install-antigravity-2.0.sh)**: Installs and extracts the Antigravity desktop IDE.
  - 📄 **[scripts/test-box.sh](file:///var/home/wtg/Repos/agy-box/scripts/test-box.sh)**: Integration test harness asserting that all commands are functional inside the sandbox.
- 📄 **[agy-box-manager](file:///var/home/wtg/Repos/agy-box/agy-box-manager)**: The central interactive terminal menu tool to install, run, or remove container environments.
- 📄 **[justfile](file:///var/home/wtg/Repos/agy-box/justfile)**: Standard automation recipes.

---

## 2. Local Development Workflow

To make code changes and test them locally:

### Step 1: Make your changes
Edit scripts, `Containerfile`, or rootfs configurations.

### Step 2: Build the development image
Build a local container image named `localhost/agy-box:dev` from your files:
```bash
# Using agy-box-manager:
./agy-box-manager dev

# Or using just:
just agy-box-dev
```

### Step 3: Run integration tests
Verify that your changes didn't break any application binaries or configurations inside the container:
```bash
just agy-test
```

---

## 3. Pull Request & Commit Guidelines

- **Branching**: Create feature branches starting from `main` (e.g. `feat/my-awesome-improvement`).
- **Commit Messages**: We enforce standard conventional commit styles:
  - `feat: add awesome new feature`
  - `fix: correct D-Bus keyring validation checks`
  - `docs: update system topology diagram`
  - `style: lint cleanup`
- **CI Pipelines**: On every pull request, GitHub Actions builds the image and runs the integration test suite automatically. Make sure all local lints and tests pass before pushing!
