# Security Policy

## Supported Versions

Security updates are applied to the latest release series and the `main` branch (`ghcr.io/wtg-codes/agy-box:latest`). Older tagged releases are not backported; please upgrade to the latest release or rebuild from `main`.

| Version | Supported |
| :--- | :--- |
| `0.8.x` / `main` (`:latest`) | :white_check_mark: |
| `< 0.8.0` | :x: |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues, discussions, or pull requests.**

Instead, please report suspected vulnerabilities privately using **GitHub Private Vulnerability Reporting**:

- Open a private security advisory at <https://github.com/wtg-codes/agy-box/security/advisories/new>.

When submitting a report, please include as much of the following as possible:

- Affected component (`Containerfile`, `agy-box-manager`, `rootfs/` runtime or VDI scripts, CI/CD workflows, or published container image digest/tag)
- Reproduction steps or proof-of-concept details
- Potential impact (e.g., host credential exposure, container escape, supply-chain compromise, or privilege escalation)
- Suggested remediation, if you have one

> **Important:** Never include live API keys, OAuth tokens, passwords, or private network endpoints in security reports, issues, or pull requests.

### Response Timeline

- **Acknowledgment:** Within 3 business days of receiving the report.
- **Triage & Assessment:** Within 7 business days, including severity assessment and planned remediation timeline.
- **Coordinated Disclosure:** We will coordinate disclosure timing with you once a fix or mitigation is available and verified in a new release.

## Scope & Supply-Chain Verification

This policy covers:

- The `agy-box` container image definition (`Containerfile`), baked system scripts (`scripts/`, `rootfs/`), and the host CLI (`agy-box-manager`).
- Host/container isolation boundaries (default `--mode sandbox` credential isolation and optional `--mode workstation` D-Bus/SecretService forwarding).
- Build, SBOM, provenance attestation, and release workflows under `.github/workflows/`.

For vulnerabilities in third-party upstream tools bundled inside the image (such as Ubuntu base packages, Google Antigravity, VS Code, Zed, Chrome/Chromium, or CNCF CLI binaries), please also consider reporting upstream, while notifying us if a pinned version bump or mitigation is needed in `agy-box`.

### Verifying Published Images & SBOMs

Published `ghcr.io/wtg-codes/agy-box` multi-arch images carry signed SLSA build provenance attestations, and every tagged GitHub Release attaches per-architecture SPDX JSON SBOMs (`sbom-amd64.spdx.json`, `sbom-arm64.spdx.json`):

```bash
gh attestation verify oci://ghcr.io/wtg-codes/agy-box:latest --repo wtg-codes/agy-box
```
