#!/bin/bash
# test-box.sh - Integration test runner for agy-box container and distrobox environment
set -euo pipefail

# --- Color configuration ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

CONTAINER_NAME="agy-box-test"
IMAGE_NAME="${IMAGE_NAME:-localhost/agy-box:dev}"

log_info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# --- Cleanup function ---
cleanup() {
    log_info "Cleaning up..."
    if distrobox list --no-color | grep -qw "$CONTAINER_NAME"; then
        log_info "Removing distrobox container '$CONTAINER_NAME'..."
        distrobox rm --yes "$CONTAINER_NAME" >/dev/null || log_warn "Failed to remove container '$CONTAINER_NAME'"
    else
        log_info "No test container '$CONTAINER_NAME' to clean up."
    fi
}

# Register cleanup trap
trap cleanup EXIT INT TERM

# --- Host Pre-checks ---
log_info "Performing host system checks..."
if ! command -v distrobox &>/dev/null; then
    log_error "distrobox is not installed on host"
    exit 1
fi

if [[ -z "${RUNTIME:-}" ]]; then
    if command -v podman &>/dev/null; then
        RUNTIME="podman"
    elif command -v docker &>/dev/null; then
        RUNTIME="docker"
    else
        log_error "Neither podman nor docker is installed on host"
        exit 1
    fi
fi
export DBX_CONTAINER_MANAGER="${RUNTIME}"
log_success "Host checks passed. Runtime: $RUNTIME, Distrobox: $(distrobox --version | head -n 1)"

# --- Build Container ---
if [[ "${SKIP_BUILD:-false}" = "true" ]]; then
    log_info "Skipping build since SKIP_BUILD=true. Using existing image $IMAGE_NAME..."
else
    log_info "Building image $IMAGE_NAME..."
    "$RUNTIME" build -t "$IMAGE_NAME" -f Containerfile .
    log_success "Built image successfully."
fi

# --- Create Distrobox ---
log_info "Creating distrobox container '$CONTAINER_NAME'..."
# If it already exists for some reason, remove it
if distrobox list --no-color | grep -qw "$CONTAINER_NAME"; then
    log_warn "Container '$CONTAINER_NAME' already exists. Removing first..."
    distrobox rm --yes "$CONTAINER_NAME" >/dev/null
fi

distrobox create -i "$IMAGE_NAME" -n "$CONTAINER_NAME" --yes
log_success "Created distrobox container '$CONTAINER_NAME'."

# --- Run Assertions Inside Distrobox ---
log_info "Running test assertions inside the container..."

# We execute distrobox enter to run our test suite
# shellcheck disable=SC2016
distrobox enter "$CONTAINER_NAME" -- bash -euo pipefail -c '
    RED="\033[0;31m"
    GREEN="\033[0;32m"
    NC="\033[0m"

    assert_cmd() {
        local name=$1
        local cmd=$2
        local ver_cmd=$3
        
        echo -n "Checking $name... "
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}FAILED (not found in PATH)${NC}"
            return 1
        fi
        
        # Verify it runs and outputs successfully
        if ! eval "$ver_cmd" &>/dev/null; then
            echo -e "${RED}FAILED (command failed to execute)${NC}"
            return 1
        fi
        
        echo -e "${GREEN}PASSED${NC}"
        return 0
    }

    errors=0

    # Assert CNCF Tools
    assert_cmd "kubectl" "kubectl" "kubectl version --client" || errors=$((errors+1))
    assert_cmd "helm" "helm" "helm version" || errors=$((errors+1))
    assert_cmd "k9s" "k9s" "k9s version" || errors=$((errors+1))

    # Assert AI Agent Tools
    assert_cmd "Gemini CLI" "gemini" "gemini --help" || errors=$((errors+1))
    assert_cmd "Google ADK" "adk" "adk --help" || errors=$((errors+1))
    assert_cmd "Antigravity CLI (agy)" "agy" "agy --version" || errors=$((errors+1))
    assert_cmd "Antigravity SDK" "python3" "python3 -c \"import google.antigravity\"" || errors=$((errors+1))

    # Assert Desktop Apps (Checking path & permissions)
    assert_cmd "Google Chrome" "google-chrome-stable" "google-chrome-stable --version" || errors=$((errors+1))
    assert_cmd "Antigravity 2.0" "antigravity" "test -x /usr/bin/antigravity" || errors=$((errors+1))
    assert_cmd "Antigravity IDE" "antigravity-ide" "test -x /usr/bin/antigravity-ide" || errors=$((errors+1))

    if [ "$errors" -gt 0 ]; then
        echo -e "${RED}✗ $errors test assertions failed inside the container.${NC}"
        exit 1
    else
        echo -e "${GREEN}✓ All test assertions passed inside the container!${NC}"
        exit 0
    fi
'

log_success "Integration tests finished successfully!"
