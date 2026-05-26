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

# Test the dev image inside a temporary container
agy-test:
    @./scripts/test-box.sh

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
        rsync -a --delete --exclude=backup ~/.config/agy-box/ ~/.config/agy-box/backup/agy-box/; \
    fi
    @if [ -d ~/.config/python_keyring ]; then \
        mkdir -p ~/.config/agy-box/backup/python_keyring; \
        rsync -a --delete ~/.config/python_keyring/ ~/.config/agy-box/backup/python_keyring/; \
    fi
    @echo "Workspace state successfully synchronized to ~/.config/agy-box/backup/"


