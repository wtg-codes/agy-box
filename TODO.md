# Future Improvements

## Architectural Goals
- **Multi-Architecture Support**: Update the CI pipeline and Docker build configuration to support generating multi-arch images (e.g., `amd64`, `arm64`) using `docker buildx`.
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

---

## 🗺️ Master Plan Workstreams (Active Plan)

### Workstream 1: Documentation & Pages Expansion
- [ ] Fix broken `file:///` links in README
- [ ] Add `doctor` and `ports` subcommands to command reference table in README
- [ ] Add `CODE_OF_CONDUCT.md` (Contributor Covenant)
- [ ] Add GitHub issue and PR templates in `.github/`
- [ ] Create `docs/settings-reference.md` mapping configuration variables
- [ ] Expand `SETUP.md` troubleshooting FAQ with 10+ common issues

### Workstream 2: Visual Diagrams
- [ ] Extract all inline Mermaid blocks to standalone files under `docs/diagrams/src/`
- [ ] Style diagrams using custom brand variables config
- [ ] Set up `mmdc` script/CI workflow to auto-render `.mmd` -> `.svg` on push

### Workstream 3 & 4: Downstream & Rename Integration
- [ ] Update any references pointing to the old `agv-easy-install` name to the new `agy-easy-install` name
- [ ] Decide on versioning strategy: should agy-box-manager download release tags or always fetch `main`?
- [ ] Coordinate macOS warnings/blocks for distrobox setup

