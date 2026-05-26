# AGY Box Manager - Universal Justfile

set allow-duplicate-recipes := true

# Launch the interactive UI manager
agy:
    @./agy-box-manager

# Pull and install the official stable release
agy-install:
    @./agy-box-manager install

# Build a local development workspace from source
agy-box-dev:
    @./agy-box-manager dev

# Enter the official workspace
agy-enter:
    @./agy-box-manager enter

# Enter the development workspace
agy-enter-dev:
    @./agy-box-manager enter dev

# Start VDI Desktop inside official workspace
agy-desktop:
    @./agy-box-manager desktop

# Start VDI Desktop inside development workspace
agy-desktop-dev:
    @./agy-box-manager desktop dev

# Check the status of AGY Boxes
agy-status:
    @./agy-box-manager status

# Remove the official workspace
agy-clean:
    @./agy-box-manager clean

# Remove the development workspace
agy-clean-dev:
    @./agy-box-manager clean dev

# Install the CLI tool globally to ~/.local/bin
agy-install-global:
    @./agy-box-manager install-global

# Remove the global CLI installation
agy-uninstall-global:
    @./agy-box-manager uninstall-global

# Test the dev image inside a temporary container
agy-test:
    @./scripts/test-box.sh

# Setup local development workspace and export tools
setup-box:
    @./agy-box-manager dev

# Teardown local development workspace and cleanup tools
teardown-box:
    @./agy-box-manager clean dev


