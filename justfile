# AGY Box Manager - Universal Justfile

set allow-duplicate-recipes := true

manager := `if [ -f ./agy-box-manager ]; then echo "./agy-box-manager"; else echo "agy-box-manager"; fi`

# Launch the interactive UI manager
agy:
    @{{manager}}

# Pull and install the official stable release
agy-install:
    @{{manager}} install

# Build a local development workspace from source
agy-box-dev:
    @{{manager}} dev

# Enter the official workspace
agy-enter:
    @{{manager}} enter

# Enter the development workspace
agy-enter-dev:
    @{{manager}} enter dev

# Start VDI Desktop inside official workspace
agy-desktop *args="":
    @{{manager}} desktop {{args}}

# Start VDI Desktop inside development workspace
agy-desktop-dev *args="":
    @{{manager}} desktop dev {{args}}

# Check the status of AGY Boxes
agy-status:
    @{{manager}} status

# Remove the official workspace
agy-clean:
    @{{manager}} clean

# Remove the development workspace
agy-clean-dev:
    @{{manager}} clean dev

# Install the CLI tool globally to ~/.local/bin
agy-install-global:
    @{{manager}} install-global

# Remove the global CLI installation
agy-uninstall-global:
    @{{manager}} uninstall-global

# Prune exited containers, dangling images, and unused volumes to free up space
agy-prune:
    @runtime=$(command -v podman &>/dev/null && echo "podman" || echo "docker"); \
    echo "Cleaning up local container environment via $runtime..."; \
    $runtime container prune -f || true; \
    $runtime image prune -f || true; \
    $runtime volume prune -f || true

# Test the dev image inside a temporary container
agy-test:
    @./scripts/test-box.sh

# Run health checks directly inside the active running container
agy-assert *args="":
    @target_name="agy-box"; \
    if [ "{{args}}" = "dev" ]; then target_name="agy-box-dev"; fi; \
    if ! distrobox list --no-color 2>/dev/null | grep -qw "$target_name"; then \
        echo "Error: Container '$target_name' is not running or registered." >&2; \
        exit 1; \
    fi; \
    echo "Running active assertions inside '$target_name'..."; \
    distrobox enter "$target_name" -- ./scripts/assert-box.sh

# Setup local development workspace and export tools
setup-box:
    @{{manager}} dev
    @mkdir -p ~/.local/share/bash-completion/completions
    @{{manager}} autocomplete bash > ~/.local/share/bash-completion/completions/agy-box-manager
    @{{manager}} autocomplete bash > ~/.local/share/bash-completion/completions/agy

# Teardown local development workspace and cleanup tools
teardown-box:
    @{{manager}} clean dev

# Sync config directories/dotfiles to backup directory
sync-workspace:
    @mkdir -p ~/.config/agy-box/backup
    @if [ -d ~/.config/environment.d ]; then \
        mkdir -p ~/.config/agy-box/backup/environment.d; \
        rsync -a --delete ~/.config/environment.d/ ~/.config/agy-box/backup/environment.d/; \
    fi
    @if [ -d ~/.config/agy-box ]; then \
        mkdir -p ~/.config/agy-box/backup/agy-box; \
        rsync -a --delete --exclude=backup --exclude=home ~/.config/agy-box/ ~/.config/agy-box/backup/agy-box/; \
    fi
    @if [ -d ~/.config/python_keyring ]; then \
        mkdir -p ~/.config/agy-box/backup/python_keyring; \
        rsync -a --delete ~/.config/python_keyring/ ~/.config/agy-box/backup/python_keyring/; \
    fi
    @echo "Workspace state successfully synchronized to ~/.config/agy-box/backup/"

# Run Bats unit tests for installation scripts
test-scripts:
    @if command -v bats >/dev/null 2>&1; then \
        bats tests/; \
    elif [ -f ./node_modules/.bin/bats ]; then \
        ./node_modules/.bin/bats tests/; \
    else \
        echo "bats not found locally, falling back to container..."; \
        runtime=$(command -v podman &>/dev/null && echo "podman" || echo "docker"); \
        $runtime run --rm -v "$(pwd):/code" -w /code docker.io/bats/bats:latest tests/; \
    fi


