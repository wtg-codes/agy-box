# Future Improvements

## Architectural Goals
- ~~**Multi-Architecture Support**: Update the CI pipeline and Docker build configuration to support generating multi-arch images (`amd64`, `arm64`) using native parallel GitHub Actions runners and Docker Buildx.~~ ✅ Done (`feat/nvidia-dgx-spark-arm64`): Switched base to `quay.io/toolbx/ubuntu-toolbox:24.04`, added native `ubuntu-24.04-arm` runner job, and auto-detects NVIDIA GPUs (including DGX Spark Grace Blackwell) via `--nvidia`.
- ~~**Authentic Supply Chain Security (Option A: Batteries-Included Image)**:~~ ✅ Done (PR #29): The complete Antigravity toolchain is pre-baked into `/opt` and `/usr/local/bin` at build time so Syft generates a 100% genuine SBOM that Grype scans prior to release, with `agy-install-toolchain` retained for runtime updates.

## Technical Debt
- ~~**Containerfile Linting**: Implement `hadolint` in the GitHub Actions workflow to ensure `Containerfile` adheres to best practices.~~ ✅ Done (v0.6.0, `Lint Codebase` job).
- ~~**Shell Script Linting**: Add `shellcheck` into the linting workflow to validate the integrity of scripts within `scripts/`.~~ ✅ Done (v0.6.0; also covers `agy-box-manager`, `agy-setup-helper`, `agy-vdi`, and the IceWM startup script).
- **Dependency Pinning**: Ensure all package installations inside the `Containerfile` and scripts use strictly pinned versions instead of `latest` where possible.
  - *Status (v0.6.0)*: Base image pinned to Ubuntu 24.04 release tag (`quay.io/toolbx/ubuntu-toolbox:24.04`); `kubectl`, `helm`, `k9s`, Gum, Antigravity tarballs, SDK, ADK, and Gemini CLI pinned. Still unpinned: Google Chrome (`google-chrome-stable`), apt packages, `uv`, Open WebUI and PyTorch wheels.
- ~~**Unused legacy install scripts**: `scripts/install-gemini-cli.sh` and `scripts/install-google-adk.sh` are no longer called by the `Containerfile` (superseded by `scripts/install-agent-toolchain.sh`) but are still exercised by Bats tests. Remove them and point the tests at the toolchain installer.~~ ✅ Done (PR #26).
- ~~**`agy-box-manager` runtime selection**: The manager always prefers Podman when installed and ignores a user-provided `DBX_CONTAINER_MANAGER` (see [docs/SETUP.md](docs/SETUP.md) Q4). Honor the variable.~~ ✅ Done: `agy-box-manager` now honors `$DBX_CONTAINER_MANAGER` when set in the environment and present on `PATH`.

## Testing Plans
- ~~**Unit Testing for Scripts**: Introduce a framework like `Bats` (Bash Automated Testing System) to assert the scripts execute and install dependencies accurately without having to build the entire container every time.~~ ✅ Done (v0.6.0, `tests/install_scripts.bats`, `Run Script Tests` job).
- ~~**Integration Testing**: Added a local integration test suite in `scripts/test-box.sh`. Next step is to run these assertions automatically in the CI pipeline.~~ ✅ Done (v0.6.0, the `Build & Validate Image (amd64)` job runs `scripts/test-box.sh` against the freshly built image).
- **PR Preview Environments**: Setup a way to dynamically test container image builds on pull requests, pushing to temporary PR-specific tags instead of polluting `latest`.
  - *Status (v0.6.0)*: PRs build and test the image but never push it (no `pr-N` tags). Publishing PR previews would need a GHCR retention policy first (see below).

## Documentation & Community
- ~~**CONTRIBUTING.md**: Create detailed contribution guidelines for new developers outlining branch strategies and commit conventions.~~ ✅ Done ([CONTRIBUTING.md](CONTRIBUTING.md)).
- ~~**Code of Conduct**: Add a standard Code of Conduct document to the repository.~~ ✅ Done ([CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md), Contributor Covenant 2.1).
- **Architecture & Product Sync**: Periodically verify and update the sandbox architecture and product deep-dives (README.md) to reflect new versions, installation endpoints, and configuration options.
- ~~**Settings Schema Mapping**: Document user settings schema for Antigravity IDE and CLI in a dedicated `docs/settings-reference.md` file.~~ ✅ Done ([docs/settings-reference.md](docs/settings-reference.md)).

## Security
- **Container Vulnerability Scanning**: Integrate `Trivy` or `Grype` into the CI/CD pipeline to automatically block builds that introduce critical CVEs.
  - *Status (v0.6.0)*: Grype scans the Syft SBOM on every build, but **informationally** (`--only-fixed`, no `--fail-on`). Blocking is tracked under [Possible future work](#possible-future-work).

## Possible future work

Ideas that are not scheduled yet. Each needs a decision before implementation.

### Images & platforms
- ~~**Batteries-Included Toolchain & Honest SBOM (Option A)**: Bake the developer toolchain (Google Antigravity Agent UI, IDE/VS Code extension, CLI `agy`, Python SDK, and Google ADK) directly into system paths (`/usr/local/bin`, `/opt`) at container build time. This ensures Syft generates a 100% authentic, comprehensive `sbom.spdx.json` that Grype scans in CI, while eliminating slow and error-prone user-space downloads on first boot.~~ ✅ Done (PR #29).
- **Upstream Version Sync via `agy-easy-install`**: Source upstream release URLs, versions, and verified SHA256 checksums from `wtg-codes/agy-easy-install`'s `versions.json` (scraped nightly) as build arguments in GitHub Actions CI.
- **Googlebook (ChromeOS / Crostini) Support**: Validate and document running `agy-box` / `agy-box-manager` inside ChromeOS Crostini Linux container (both x86_64 and ARM64 Googlebook devices), including localhost port forwarding for noVNC VDI (`6080`) and Open WebUI (`8080`).
- **Antigravity IDE Extension Transition**: With Google deprecating the Standalone Antigravity IDE in favor of editor extensions, package VS Code / VSCodium with the official `Google Antigravity` extension pre-configured inside the VDI desktop, keeping the standalone IDE as a legacy option.
- **Optional CUDA PyTorch variant for Open WebUI**: Offer CUDA-enabled PyTorch either as a separate image tag (e.g. `ghcr.io/wtg-codes/agy-box:<version>-cuda`) or as an opt-in installer inside the box. Only useful with NVIDIA GPU passthrough into the container, and adds roughly 4.5 GB of NVIDIA libraries, so the default image stays CPU-only.
- ~~**Real arm64 support (NVIDIA DGX Spark / Apple Silicon / Crostini)**: Moved to multi-arch base image `quay.io/toolbx/ubuntu-toolbox:24.04` (publishing native `amd64` and `arm64`) with parallel native GitHub Actions runners (`ubuntu-24.04` and `ubuntu-24.04-arm`). Updated `scripts/install-agent-toolchain.sh` with Google's official Linux ARM64 binaries and checksums. Added `--nvidia` GPU auto-detection in `agy-box-manager` for NVIDIA Grace Blackwell workstations.~~ ✅ Done (`feat/nvidia-dgx-spark-arm64`).
- ~~**v0.6.0 wallpaper asset**: Add `rootfs/usr/share/agy-box/wallpaper-v0.6.0.png`.~~ ✅ Done

### Toolchain
- ~~**`agy-box-manager update-toolchain` command**: Re-run the per-user toolchain installer (`agy-install-toolchain`) inside an existing box to pick up new Antigravity/SDK/ADK/Gemini CLI versions without recreating the container.~~ ✅ Done (PR #29).
- **Update notes**: Show what changed (image tag, toolchain versions) when `agy-box-manager install` recreates an existing box, e.g. by linking the GitHub Release notes for the pulled tag.

### CI/CD & supply chain
- **In-registry SBOM attestation**: Re-introduce an SBOM attestation using BuildKit's native `sbom: true` (`docker/build-push-action`), which stores the SBOM in the image index, as a replacement for the removed `actions/attest-sbom` step (dropped because the SBOM exceeded the 16 MB attestation limit).
- **Stricter Grype gating**: Fail the build on critical vulnerabilities that have a fix available (`grype --only-fixed --fail-on critical`), possibly with an allow-list file for accepted findings.
- ~~**GHCR retention policy**: Every push to `main` leaves the previous digest untagged. Add a scheduled cleanup (e.g. `actions/delete-package-versions` or `dataaxiom/ghcr-cleanup-action`) that prunes untagged digests older than N days while keeping anything referenced by a tag or attestation.~~ ✅ Done (PR #25, `.github/workflows/ghcr-cleanup.yml`).
- **Keep GitHub Actions current**: v0.6.0 moved all workflows off the deprecated Node 20 runtime; add Dependabot (`package-ecosystem: github-actions`) so future major versions arrive as PRs.
- **GitHub Actions cache size**: The `type=gha,mode=max` layer cache for the multi-GB image competes for the repository's 10 GB Actions cache quota. Consider `mode=min`, or a registry cache (`type=registry,ref=ghcr.io/wtg-codes/agy-box:buildcache,mode=max`).
- ~~**Test for stray NVIDIA pip packages**: Extend `scripts/assert-box.sh` to fail if any `nvidia-*` Python packages are present in `/opt/open-webui-venv` (`uv pip list` / `pip list`), complementing the existing `torch.version.cuda` check.~~ ✅ Done: Added assertion in `scripts/assert-box.sh` verifying no stray `nvidia-*` packages exist in the CPU-only Open WebUI venv.
- **Mermaid render on PRs**: `compile-diagrams.yml` commits rendered diagrams back to the branch with `[skip ci]`, which leaves that head commit without PR checks. Consider rendering in CI without committing, or committing with a token that triggers CI.
