# Contributing to agy-box

Thank you for your interest in contributing to `agy-box`! This guide outlines how to set up your local development environment, explains the repository layout, and reviews code contribution workflows.

> 🌐 New here? The [project website](https://wtg-codes.github.io/agy-box/) gives a quick visual overview of what the box contains.

---

## 1. Repository Layout

The repository is structured as a Distrobox overlay template:

- 📄 **[Containerfile](Containerfile)**: Image definition. Based on `quay.io/toolbx/ubuntu-toolbox:24.04`, pinned by digest (Ubuntu 24.04 LTS, multi-arch `linux/amd64` and `linux/arm64`; Dependabot proposes digest bumps).
- 📂 **[rootfs/](rootfs)**: Files copied directly into the root filesystem (`/`) of the container during the build.
  - 📂 **[rootfs/etc/profile.d/agy-setup-check.sh](rootfs/etc/profile.d/agy-setup-check.sh)**: Hook that launches the interactive setup helper on first interactive TTY shell login.
  - 📂 **[rootfs/usr/local/bin/agy-setup-helper](rootfs/usr/local/bin/agy-setup-helper)**: Interactive first-time CLI helper verifying API keys, D-Bus, Chrome version, and Git setups. Its `VERSION` variable is the image version.
  - 📂 **[rootfs/usr/local/bin/agy-vdi](rootfs/usr/local/bin/agy-vdi)**: Starts the noVNC VDI desktop (Xvfb, IceWM, x11vnc, websockify).
  - 📂 **[rootfs/usr/local/bin/entrypoint.sh](rootfs/usr/local/bin/entrypoint.sh)**: Custom entrypoint running inside the container to align sandbox user permissions.
  - 📂 **[rootfs/etc/X11/icewm/](rootfs/etc/X11/icewm)** and **[rootfs/etc/skel/](rootfs/etc/skel)**: IceWM desktop configuration, desktop icons, and default user settings.
- 📂 **[scripts/](scripts)**: Package dependency configuration and helper scripts.
  - 📄 **[scripts/install-agent-deps.sh](scripts/install-agent-deps.sh)**: Installs basic dependencies and system-level requirements (like `libsecret-1-0` for keyring mapping, Chrome, the VDI stack, and Gum).
  - 📄 **[scripts/install-tools.sh](scripts/install-tools.sh)**: Installs pinned, checksum-verified CNCF tools (`kubectl`, `helm`, `k9s`).
  - 📄 **[scripts/install-agent-toolchain.sh](scripts/install-agent-toolchain.sh)**: Antigravity toolchain installer (Agent UI, IDE, `agy` CLI, SDK, ADK, Gemini CLI). Baked system-wide into `/usr/local/bin` and `/opt` during image build (Option A) for authentic Syft SBOM & Grype scanning, and shipped as `/usr/local/bin/agy-install-toolchain` for runtime per-user customizations.
  - 📄 **[scripts/test-box.sh](scripts/test-box.sh)**: Integration test harness that builds (or with `PULL=true` pulls `IMAGE_NAME`) the image, creates a temporary distrobox, installs the toolchain, and runs the assertions (`VDI_TEST=true` also checks the noVNC desktop). `just agy-e2e [tag]` runs it against `ghcr.io/wtg-codes/agy-box:<tag>`.
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

# Or test a published image end to end (pull + VDI check), default tag `latest`:
just agy-e2e 0.6.0
```

### Editing diagrams
Edit the Mermaid sources in `docs/diagrams/*.mmd` only. Renders in `docs/diagrams/rendered/` are regenerated automatically by [`compile-diagrams.yml`](.github/workflows/compile-diagrams.yml) after merge to `main`; do not edit or commit them by hand.

---

## 3. Pull Request & Commit Guidelines

- **Branching**: Create feature branches starting from `main` (e.g. `feat/my-awesome-improvement`).
- **Commit Messages**: We enforce standard conventional commit styles:
  - `feat: add awesome new feature`
  - `fix: correct D-Bus keyring validation checks`
  - `docs: update system topology diagram`
  - `style: lint cleanup`
- **Never put CI skip directives in commit messages** (`[skip ci]`, `[ci skip]`, `[no ci]`, `[skip actions]`, `skip-checks: true`), not even when quoting them. Squash merges copy commit messages into the merge commit on `main`, and GitHub then silently skips the CI/CD run, so nothing gets published. The **Lint Codebase** job rejects PRs whose commits contain them.
- **CI Pipelines**: On every pull request, GitHub Actions lints the repository (yamllint, ShellCheck, hadolint), runs the Bats tests, builds the `linux/amd64` and `linux/arm64` images on native runners, runs the Distrobox integration test suite against both, and generates an SBOM plus an informational Grype vulnerability scan for each architecture. Pull requests never push images to GHCR. Make sure all local lints and tests pass before pushing!
- **Releases**: Maintainers bump `VERSION` in `agy-box-manager` and `rootfs/usr/local/bin/agy-setup-helper` (plus the version shown in `docs/index.html`), merge to `main`, and push a `v<version>` tag. See [Releases](#releases).

---

## 4. Container registry maintenance (GHCR)

The [ghcr-cleanup.yml](.github/workflows/ghcr-cleanup.yml) workflow (weekly + manual) maintains `ghcr.io/wtg-codes/agy-box`. It runs in the `ghcr-maintenance` concurrency group, uses only the workflow's `GITHUB_TOKEN` (`packages: write`), and defaults to **dry run**. It deletes untagged image versions with [`dataaxiom/ghcr-cleanup-action`](https://github.com/dataaxiom/ghcr-cleanup-action), which understands image indexes, BuildKit attestation manifests and sigstore referrers and never deletes a digest still referenced by a tagged image. Only images older than `older_than` (default `1 day`) are considered, so in-flight CI pushes are safe. Scheduled runs stay dry runs until the repository variable `GHCR_CLEANUP_ENABLED` is set to `true`.

---

## 5. CI/CD, Artifacts & Releases

The [`CI/CD` workflow](.github/workflows/ci.yml) runs on every pull request, every push to `main`, and every `v*` tag.

| Job | Runs on | What it does |
| :--- | :--- | :--- |
| **Lint Codebase** | PRs, `main`, tags | Rejects CI skip directives in PR commit messages, `yamllint` (strict), `actionlint` on the workflows, ShellCheck on all shell scripts and `agy-box-manager`, and `hadolint` on the `Containerfile`. |
| **Run Script Tests** | PRs, `main`, tags | Runs the Bats unit tests in `tests/`. |
| **Build & Validate Image (matrix: amd64, arm64)** | PRs, `main`, tags | Builds natively with Docker Buildx: `amd64` on GitHub-hosted `ubuntu-24.04` (GitHub Actions layer cache), `arm64` on the DGX Spark self-hosted runners (`[self-hosted, Linux, ARM64, dgx-spark]`) with the persistent `dgx-spark-builder` BuildKit cache. No QEMU. **Fork PRs never run on the self-hosted runners**: their jobs use GitHub-hosted `ubuntu-24.04` / `ubuntu-24.04-arm`. Runs the Distrobox integration tests (`scripts/test-box.sh`) against that build, generates an SPDX SBOM with Syft, scans it with Grype (informational, `--only-fixed`), and uploads the SBOM. On `main` and tags (never on PRs) it pushes each architecture build to GHCR **by digest**. |
| **Publish & Release** | `main`, tags | Runs after all upstream jobs pass. Merges the per-architecture digests into a multi-arch manifest list, applies tags (`latest`, `main`, `0.6.0`, `0.6`), creates signed SLSA **build provenance attestations**, and on `v*` tags creates a GitHub Release with both SBOMs attached. |

Pull requests never push images. Published tags: `latest` and `main` (every push to `main`), and `<major>.<minor>.<patch>` / `<major>.<minor>` (every `v*` tag). Auxiliary workflows: [`pages.yml`](.github/workflows/pages.yml) deploys `docs/` to GitHub Pages when `docs/` changes on `main` and after a successful diagram render, [`compile-diagrams.yml`](.github/workflows/compile-diagrams.yml) re-renders Mermaid diagrams on `main`, and [Dependabot](.github/dependabot.yml) keeps GitHub Actions and the base image digest current.

**Artifacts.** Every build produces an SPDX JSON SBOM (workflow artifact, retained 5 days; attached to GitHub Releases for tags). The SBOM is not pushed as a registry attestation (it exceeds the attestation size limit); the published image carries a build provenance attestation:

```bash
gh attestation verify oci://ghcr.io/wtg-codes/agy-box:latest --repo wtg-codes/agy-box
```

### Releases

1. Bump the versions (see [Pull Request & Commit Guidelines](#3-pull-request--commit-guidelines)) and merge to `main`.
2. Tag and push: `git tag v0.6.0 && git push origin v0.6.0`.
3. CI builds, tests, and publishes `ghcr.io/wtg-codes/agy-box:0.6.0` and `:0.6` (`latest` only moves on pushes to `main`), then creates a GitHub Release with autogenerated notes and the SBOMs attached.
