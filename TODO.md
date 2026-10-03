# Future Improvements

## Architectural Goals
- **Multi-Architecture Support**: Update the CI pipeline and Docker build configuration to support generating multi-arch images (e.g., `amd64`, `arm64`) using `docker buildx`.
  - *Blocked by base image*: `ghcr.io/ublue-os/ubuntu-toolbox` is published for `linux/amd64` only (single `latest` tag, no manifest list), so CI currently builds and publishes amd64 only. Earlier "arm64" images built under QEMU were actually amd64 userland. Enabling arm64 requires a multi-arch base (e.g. `quay.io/toolbx/ubuntu-toolbox:24.04`, which publishes amd64 + arm64) and re-adding a native `ubuntu-24.04-arm` build job.
- **Component Separation**: Evaluate moving deeply specific agent tooling out of the base container into dynamically loaded modules to keep the core image size small.

## Technical Debt
- **Containerfile Linting**: Implement `hadolint` in the GitHub Actions workflow to ensure `Containerfile` adheres to best practices.
- **Shell Script Linting**: Add `shellcheck` into the linting workflow to validate the integrity of scripts within `scripts/`.
- **Dependency Pinning**: Ensure all package installations inside the `Containerfile` and scripts use strictly pinned versions instead of `latest` where possible.

## Testing Plans
- **Unit Testing for Scripts**: Introduce a framework like `Bats` (Bash Automated Testing System) to assert the scripts execute and install dependencies accurately without having to build the entire container every time.
- **Integration Testing**: Added a local integration test suite in `scripts/test-box.sh`. Next step is to run these assertions automatically in the CI pipeline.
- **PR Preview Environments**: Setup a way to dynamically test container image builds on pull requests, pushing to temporary PR-specific tags instead of polluting `latest`.

## Documentation & Community
- **CONTRIBUTING.md**: Create detailed contribution guidelines for new developers outlining branch strategies and commit conventions.
- **Code of Conduct**: Add a standard Code of Conduct document to the repository.
- **Architecture & Product Sync**: Periodically verify and update the sandbox architecture and product deep-dives (README.md) to reflect new versions, installation endpoints, and configuration options.
- **Settings Schema Mapping**: Document user settings schema for Antigravity IDE and CLI in a dedicated `docs/settings-reference.md` file.

## Security
- **Container Vulnerability Scanning**: Integrate `Trivy` or `Grype` into the CI/CD pipeline to automatically block builds that introduce critical CVEs.
