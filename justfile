# AGY Box Manager - Universal Justfile

set allow-duplicate-recipes := true

manager := `if [ -f ./agy-box-manager ]; then echo "./agy-box-manager"; else echo "agy-box-manager"; fi`

# Launch the interactive UI manager
agy:
    @{{manager}}

# Pull and install the official release (or a named container: just agy-install test1, with optional --mode sandbox|workstation)
agy-install *args="":
    @{{manager}} install {{args}}

# Build a local development workspace from source
agy-box-dev *args="":
    @{{manager}} dev {{args}}

# Enter the official workspace (or a named container: just agy-enter test1)
agy-enter *args="":
    @{{manager}} enter {{args}}

# Enter the development workspace
agy-enter-dev *args="":
    @{{manager}} enter dev {{args}}

# Start VDI Desktop inside official workspace (or a named container: just agy-desktop test1)
agy-desktop *args="":
    @{{manager}} desktop {{args}}

# Start VDI Desktop inside development workspace
agy-desktop-dev *args="":
    @{{manager}} desktop dev {{args}}

# Check the status of AGY Boxes and preserved storage directories
agy-status:
    @{{manager}} status

# Inspect full system, container workspaces, toolchain, IDEs & auth status
agy-check *args="":
    @{{manager}} check {{args}}

# Run the first-run configuration setup wizard
agy-wizard *args="":
    @{{manager}} wizard {{args}}

# Update toolchain, IDE extensions, and container packages
agy-update *args="":
    @{{manager}} update {{args}}

# Back up agy-box configuration and workspace state to a tar.gz archive
agy-backup *args="":
    @{{manager}} backup {{args}}

# Restore agy-box configuration and workspace state from a tar.gz archive
agy-restore *args="":
    @{{manager}} restore {{args}}

# Remove workspace or named box (prompts for data retention, or pass --purge / --keep)
agy-clean *args="":
    @{{manager}} clean {{args}}

# Remove the development workspace
agy-clean-dev *args="":
    @{{manager}} clean dev {{args}}

# Install/update the Antigravity toolchain in the official workspace (or named box)
agy-update-toolchain *args="":
    @{{manager}} update-toolchain {{args}}

# Install/update the Antigravity toolchain in the development workspace
agy-update-toolchain-dev *args="":
    @{{manager}} update-toolchain dev {{args}}

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

# Run full host E2E test against the official published GHCR image
agy-e2e *tag="0.6.0":
    @./scripts/test-e2e.sh {{tag}}

# Run health checks directly inside the active running container
agy-assert *args="":
    @target_name="agy-box"; \
    if [ "{{args}}" = "dev" ]; then target_name="agy-box-dev"; fi; \
    if ! distrobox list --no-color 2>/dev/null | awk -F'|' -v name="$target_name" 'NR>1 {gsub(/^[ \t]+|[ \t]+$/, "", $2); if ($2 == name) exit 0} END {exit 1}'; then \
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
        $runtime run --rm -v "$(pwd):/code:z" -w /code docker.io/bats/bats:latest tests/; \
    fi

# Launch Local Workspace Web Dashboard (supports OpenAI/LiteLLM/DeepSeek on :4000/:8000 or Ollama on :11434)
agy-local-ui:
    @echo "🔍 Auditing local inference infrastructure..."
    @mkdir -p ~/.config/agy-local-ui
    @if [ -n "${OPENAI_API_BASE_URL:-}" ]; then \
        echo "✅ OpenAI-compatible backend configured via OPENAI_API_BASE_URL ($OPENAI_API_BASE_URL)"; \
        export DATA_DIR="$HOME/.config/agy-local-ui" \
               ENABLE_OLLAMA_API="${ENABLE_OLLAMA_API:-false}" \
               ENABLE_OPENAI_API="true" \
               OPENAI_API_KEY="${OPENAI_API_KEY:-sk-spark-local}" \
               RAG_EMBEDDING_ENGINE="${RAG_EMBEDDING_ENGINE:-openai}" \
               USE_CUDA_DOCKER="false" \
               CUDA_VISIBLE_DEVICES="" && \
        open-webui serve --port "${WEBUI_PORT:-8080}"; \
    elif curl -sf http://127.0.0.1:4000/health/liveliness > /dev/null 2>&1 || curl -sf http://127.0.0.1:4000/v1/models > /dev/null 2>&1; then \
        echo "✅ DGX Spark LiteLLM Gateway detected on port 4000 (CPU-only UI mode enabled)!"; \
        export DATA_DIR="$HOME/.config/agy-local-ui" \
               ENABLE_OLLAMA_API="false" \
               ENABLE_OPENAI_API="true" \
               OPENAI_API_BASE_URL="http://127.0.0.1:4000/v1" \
               OPENAI_API_KEY="${OPENAI_API_KEY:-sk-spark-master-key}" \
               RAG_EMBEDDING_ENGINE="openai" \
               USE_CUDA_DOCKER="false" \
               CUDA_VISIBLE_DEVICES="" && \
        open-webui serve --port "${WEBUI_PORT:-8080}"; \
    elif curl -sf http://127.0.0.1:8000/v1/models > /dev/null 2>&1; then \
        echo "✅ DGX Spark DeepSeek-V4.1-Flash TP2 Engine detected on port 8000 (CPU-only UI mode enabled)!"; \
        export DATA_DIR="$HOME/.config/agy-local-ui" \
               ENABLE_OLLAMA_API="false" \
               ENABLE_OPENAI_API="true" \
               OPENAI_API_BASE_URL="http://127.0.0.1:8000/v1" \
               OPENAI_API_KEY="${OPENAI_API_KEY:-sk-spark-local}" \
               RAG_EMBEDDING_ENGINE="openai" \
               USE_CUDA_DOCKER="false" \
               CUDA_VISIBLE_DEVICES="" && \
        open-webui serve --port "${WEBUI_PORT:-8080}"; \
    elif curl -sf http://127.0.0.1:11434/api/tags > /dev/null 2>&1; then \
        echo "✅ Ollama hardware acceleration node detected on port 11434!"; \
        export DATA_DIR="$HOME/.config/agy-local-ui" && open-webui serve --port "${WEBUI_PORT:-8080}"; \
    else \
        echo "❌ CONFIG ERROR: No local inference backend found on :4000 (LiteLLM), :8000 (DeepSeek), or :11434 (Ollama)!"; \
        echo "💡 Set OPENAI_API_BASE_URL=http://127.0.0.1:4000/v1 or start your local inference engine."; \
        exit 1; \
    fi

# Launch Local Workspace Web Dashboard in isolated dev/testing mode
agy-local-ui-dev:
    @echo "🧪 Initializing isolated local UI testing layer..."
    @mkdir -p ~/.config/agy-local-ui-dev
    @export DATA_DIR="$HOME/.config/agy-local-ui-dev" \
            ENABLE_OLLAMA_API="${ENABLE_OLLAMA_API:-false}" \
            ENABLE_OPENAI_API="${ENABLE_OPENAI_API:-true}" \
            OPENAI_API_BASE_URL="${OPENAI_API_BASE_URL:-http://127.0.0.1:4000/v1}" \
            OPENAI_API_KEY="${OPENAI_API_KEY:-sk-spark-local}" \
            USE_CUDA_DOCKER="false" \
            CUDA_VISIBLE_DEVICES="" && \
     open-webui serve --port "${WEBUI_DEV_PORT:-8081}"
