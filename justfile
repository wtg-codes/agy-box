# AGY Box Manager - Universal Justfile

set allow-duplicate-recipes := true

manager := `if [ -f ./agy-box-manager ]; then echo "./agy-box-manager"; else echo "agy-box-manager"; fi`

# Launch the interactive TUI manager
agy:
    @{{manager}}

# Pull the official release image and create a new stable box (default: --mode sandbox; optional: --mode workstation)
agy-install *args="":
    @{{manager}} install {{args}}

# Build a box image from the local repository (main -> stable channel, other branches -> dev channel)
agy-box-dev *args="":
    @{{manager}} dev {{args}}

# Enter a box shell (auto-selects when 1 box exists, or pass name | stable | dev)
agy-enter *args="":
    @{{manager}} enter {{args}}

# Enter a dev-channel box shell
agy-enter-dev *args="":
    @{{manager}} enter dev {{args}}

# Start or manage VDI Web Desktop for a box (auto-selects when 1 box exists, or pass name | stable | dev)
agy-desktop *args="":
    @{{manager}} desktop {{args}}

# Start or manage VDI Web Desktop for a dev-channel box
agy-desktop-dev *args="":
    @{{manager}} desktop dev {{args}}

# View manager and per-box diagnostic logs (e.g. just agy-logs, just agy-logs dev --vdi)
agy-logs *args="":
    @{{manager}} logs {{args}}

# Show status of all managed AGY Boxes and preserved storage directories
agy-status:
    @{{manager}} status

# Run host and workspace health diagnostics
agy-doctor *args="":
    @{{manager}} doctor {{args}}

# Alias of agy-doctor
agy-check *args="":
    @{{manager}} doctor {{args}}

# Update toolchain, IDE extensions, and container OS packages
agy-update *args="":
    @{{manager}} update {{args}}

# Remove a box or all boxes (pass --all, --purge, --keep, -y)
agy-clean *args="":
    @{{manager}} clean {{args}}

# Remove a dev-channel box
agy-clean-dev *args="":
    @{{manager}} clean dev {{args}}

# Install/update the Antigravity toolchain inside a box
agy-update-toolchain *args="":
    @{{manager}} update-toolchain {{args}}

# Install/update the Antigravity toolchain inside a dev-channel box
agy-update-toolchain-dev *args="":
    @{{manager}} update-toolchain dev {{args}}

# Install agy-box-manager globally to ~/.local/bin
agy-install-global:
    @{{manager}} install-global

# Remove the global agy-box-manager CLI installation
agy-uninstall-global *args="":
    @{{manager}} uninstall-global {{args}}

# Prune exited containers, dangling images, and unused volumes to free up space
agy-prune:
    @runtime=$(command -v podman &>/dev/null && echo "podman" || echo "docker"); \
    echo "Cleaning up local container environment via $runtime..."; \
    $runtime container prune -f || true; \
    $runtime image prune -f || true; \
    $runtime volume prune -f || true

# Build and test the local image inside an isolated container
agy-test:
    @./scripts/test-box.sh

# Run full host E2E test against the official published GHCR image
agy-e2e tag="latest":
    @PULL=true VDI_TEST=true IMAGE_NAME="ghcr.io/wtg-codes/agy-box:{{tag}}" ./scripts/test-box.sh

# Run active container assertions inside a running box (sandbox or workstation)
agy-assert *args="":
    @{{manager}} enter {{args}} -- bash -s < ./scripts/assert-box.sh

# Build a local development box and configure agy-box-manager completions
setup-box:
    @{{manager}} dev --no-enter

# Teardown local development box
teardown-box:
    @{{manager}} clean dev --purge -y

# Run Bats unit tests for manager and installation scripts
test-scripts:
    @if command -v bats >/dev/null 2>&1; then \
        bats tests/; \
    elif [ -f ./node_modules/.bin/bats ]; then \
        ./node_modules/.bin/bats tests/; \
    else \
        echo "bats not found locally, falling back to container..."; \
        runtime=$(command -v podman &>/dev/null && echo "podman" || echo "docker"); \
        $runtime run --rm -v "$(pwd):/code:z" -w /code docker.io/bats/bats:latest tests/; \
    fi
