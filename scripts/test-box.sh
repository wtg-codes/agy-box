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

# Like agy-box-manager, create the box with an isolated --home so the toolchain
# install and the agy host export are exercised exactly as for real users. Under
# /tmp because distrobox always bind-mounts /tmp at the same path in the box.
TEST_ROOT="$(mktemp -d /tmp/agy-box-test.XXXXXX)"
TEST_HOME="$TEST_ROOT/home"          # box $HOME (manager: ~/.config/agy-box/home)
TEST_EXPORT_DIR="$TEST_ROOT/bin"     # host export dir (manager: ~/.local/bin)
mkdir -p "$TEST_HOME" "$TEST_EXPORT_DIR"

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

# Find directory paths
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(dirname "$SCRIPT_DIR")

# Run a function from agy-box-manager (same code path as `agy-box-manager
# install|dev|update-toolchain|clean`). Sourced in a subshell so the manager's
# globals (e.g. CONTAINER_NAME) don't leak; arguments are expanded beforehand.
manager_fn() {
    (
        # shellcheck source=/dev/null
        source "$REPO_DIR/agy-box-manager"
        "$@"
    )
}

# --- Cleanup function ---
cleanup() {
    log_info "Cleaning up..."
    local rt="${RUNTIME:-}"
    if [[ -z "$rt" ]]; then
        if command -v podman &>/dev/null; then rt="podman"; else rt="docker"; fi
    fi
    if "$rt" ps -a --format '{{.Names}}' 2>/dev/null | grep -qw "$CONTAINER_NAME"; then
        log_info "Removing container '$CONTAINER_NAME'..."
        if distrobox list --no-color 2>/dev/null | grep -qw "$CONTAINER_NAME"; then
            distrobox rm --yes "$CONTAINER_NAME" >/dev/null || true
        fi
        if "$rt" ps -a --format '{{.Names}}' 2>/dev/null | grep -qw "$CONTAINER_NAME"; then
            "$rt" rm -f "$CONTAINER_NAME" >/dev/null || true
        fi
    else
        log_info "No test container '$CONTAINER_NAME' to clean up."
    fi
    rm -rf "$TEST_ROOT" 2>/dev/null || true
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

# --- Change Detection Hashing ---
calculate_build_hash() {
    local files_hash=""
    if command -v md5sum &>/dev/null; then
        files_hash=$(find "$REPO_DIR/Containerfile" "$REPO_DIR/scripts" "$REPO_DIR/rootfs" -type f -print0 2>/dev/null | sort -z | xargs -0 md5sum 2>/dev/null | md5sum | awk '{print $1}')
    elif command -v md5 &>/dev/null; then
        files_hash=$(find "$REPO_DIR/Containerfile" "$REPO_DIR/scripts" "$REPO_DIR/rootfs" -type f -print0 2>/dev/null | sort -z | xargs -0 md5 2>/dev/null | md5 | awk '{print $1}')
    else
        files_hash=$(find "$REPO_DIR/Containerfile" "$REPO_DIR/scripts" "$REPO_DIR/rootfs" -type f 2>/dev/null | sort | xargs stat -c "%Y" 2>/dev/null | shasum 2>/dev/null | awk '{print $1}')
    fi
    echo "${files_hash:-empty}"
}

# --- Build Container ---
STATE_FILE="$HOME/.config/agy-box/.last_build_hash"
CURRENT_HASH=$(calculate_build_hash)

IMAGE_EXISTS=false
if "${RUNTIME}" image inspect "$IMAGE_NAME" &>/dev/null; then
    IMAGE_EXISTS=true
fi

SKIP_BUILD_DETECTED=false
if [[ "${FORCE_BUILD:-false}" != "true" ]] && [[ "$IMAGE_EXISTS" = "true" ]]; then
    if [[ "${SKIP_BUILD:-false}" = "true" ]] || { [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" = "$CURRENT_HASH" ]]; }; then
        SKIP_BUILD_DETECTED=true
    fi
fi

if [[ "$SKIP_BUILD_DETECTED" = "true" ]]; then
    log_success "No container files modified since last build. Skipping image rebuild."
    log_info "(Set FORCE_BUILD=true to override)"
else
    log_info "Building image $IMAGE_NAME..."
    "$RUNTIME" build -t "$IMAGE_NAME" -f "$REPO_DIR/Containerfile" "$REPO_DIR"
    log_success "Built image successfully."
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$CURRENT_HASH" > "$STATE_FILE"
fi

# --- Create Distrobox ---
log_info "Creating distrobox container '$CONTAINER_NAME'..."
# If it already exists for some reason, remove it
if "${RUNTIME}" ps -a --format '{{.Names}}' 2>/dev/null | grep -qw "$CONTAINER_NAME"; then
    log_warn "Container '$CONTAINER_NAME' already exists in ${RUNTIME}. Removing first..."
    if distrobox list --no-color 2>/dev/null | grep -qw "$CONTAINER_NAME"; then
        distrobox rm --yes "$CONTAINER_NAME" >/dev/null || true
    fi
    if "${RUNTIME}" ps -a --format '{{.Names}}' 2>/dev/null | grep -qw "$CONTAINER_NAME"; then
        "${RUNTIME}" rm -f "$CONTAINER_NAME" >/dev/null || true
    fi
fi

distrobox create -i "$IMAGE_NAME" -n "$CONTAINER_NAME" --hostname "$CONTAINER_NAME" --home "$TEST_HOME" --yes
log_success "Created distrobox container '$CONTAINER_NAME'."

# Sleep briefly to ensure Podman container registration is fully synced to disk
sleep 2

# --- Install Toolchain (real user path) ---
# Runs the in-image /usr/local/bin/agy-install-toolchain inside the box and
# exports the agy CLI to the host, via the manager's own install_toolchain_in_box.
log_info "Installing agent toolchain inside the container (agy-box-manager install path)..."
manager_fn install_toolchain_in_box "$CONTAINER_NAME" "$TEST_HOME" "$TEST_EXPORT_DIR"
log_success "Toolchain installed and agy CLI exported."

# --- Verify the exported host shim ---
verify_host_shim() {
    local shim="$TEST_EXPORT_DIR/agy"
    log_info "Verifying exported host shim $shim..."
    if [[ ! -x "$shim" ]] || ! grep -q "distrobox_binary" "$shim"; then
        log_error "Exported agy shim missing or not a distrobox export: $shim"
        exit 1
    fi
    if ! grep -qF "'$TEST_HOME/.local/bin/agy'" "$shim"; then
        log_error "Exported agy shim does not point at the box's ~/.local/bin/agy:"
        cat "$shim" >&2
        exit 1
    fi
    # Run from the host (outside the box): the shim must enter the box and run agy.
    if ! (unset CONTAINER_ID; "$shim" --version); then
        log_error "Exported agy shim failed to run 'agy --version' from the host."
        exit 1
    fi
    log_success "Exported host shim runs agy from the host."
}
verify_host_shim

# --- Run Assertions Inside Distrobox ---
log_info "Running test assertions inside the container..."

# We execute distrobox enter to run our test suite script
distrobox enter "$CONTAINER_NAME" -- "$REPO_DIR/scripts/assert-box.sh"

# --- Re-run (agy-box-manager update-toolchain path) ---
log_info "Re-running the toolchain install to verify it is idempotent (update-toolchain path)..."
manager_fn install_toolchain_in_box "$CONTAINER_NAME" "$TEST_HOME" "$TEST_EXPORT_DIR"
verify_host_shim

# --- Uninstall path: remove the export (agy-box-manager clean) ---
log_info "Removing the exported agy CLI (agy-box-manager clean path)..."
manager_fn unexport_agy_cli "$CONTAINER_NAME" "$TEST_EXPORT_DIR"
if [[ -e "$TEST_EXPORT_DIR/agy" ]]; then
    log_error "Exported agy shim still present after unexport."
    exit 1
fi
log_success "Exported agy shim removed."

log_success "Integration tests finished successfully!"
