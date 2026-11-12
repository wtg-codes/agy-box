#!/bin/bash
# test-box.sh - Integration test runner for agy-box container and distrobox environment
#
# Environment:
#   IMAGE_NAME   image to test (default: localhost/agy-box:dev, built from source)
#   SKIP_BUILD   "true" to use IMAGE_NAME as-is (no local build)
#   FORCE_BUILD  "true" to rebuild even if sources are unchanged
#   PULL         "true" to pull IMAGE_NAME from its registry first (implies SKIP_BUILD)
#   VDI_TEST     "true" to also start agy-vdi and probe noVNC on port 6080
#   RUNTIME      podman | docker (default: auto-detect)
#
# Test a published release end to end:
#   PULL=true VDI_TEST=true IMAGE_NAME=ghcr.io/wtg-codes/agy-box:latest ./scripts/test-box.sh
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
        if command -v distrobox &>/dev/null && distrobox list --no-color 2>/dev/null | grep -qw "$CONTAINER_NAME"; then
            distrobox rm --yes "$CONTAINER_NAME" >/dev/null || true
        fi
        if "$rt" ps -a --format '{{.Names}}' 2>/dev/null | grep -qw "$CONTAINER_NAME"; then
            "$rt" rm -f "$CONTAINER_NAME" >/dev/null || true
        fi
    else
        log_info "No test container '$CONTAINER_NAME' to clean up."
    fi
    if [[ "$rt" = "podman" ]] && [[ "$(id -u)" -ne 0 ]]; then
        podman unshare rm -rf "$TEST_ROOT" 2>/dev/null || true
    fi
    rm -rf "$TEST_ROOT" 2>/dev/null || true
}

# Register cleanup trap
trap cleanup EXIT INT TERM

# --- Host Pre-checks ---
log_info "Performing host system checks..."
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
if command -v distrobox &>/dev/null; then
    log_success "Host checks passed. Runtime: $RUNTIME, Distrobox: $(distrobox --version | head -n 1)"
else
    log_warn "distrobox is not installed on host; falling back to Isolated Sandbox mode (${RUNTIME})."
    log_success "Host checks passed. Runtime: $RUNTIME (Distrobox: not installed)"
fi

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

# --- Pull published image (release E2E) ---
if [[ "${PULL:-false}" = "true" ]]; then
    log_info "Pulling $IMAGE_NAME..."
    "$RUNTIME" pull "$IMAGE_NAME"
    SKIP_BUILD=true
fi

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

# --- Create Distrobox (or Isolated Sandbox fallback) ---
# If it already exists for some reason, remove it
if "${RUNTIME}" ps -a --format '{{.Names}}' 2>/dev/null | grep -qw "$CONTAINER_NAME"; then
    log_warn "Container '$CONTAINER_NAME' already exists in ${RUNTIME}. Removing first..."
    if command -v distrobox &>/dev/null && distrobox list --no-color 2>/dev/null | grep -qw "$CONTAINER_NAME"; then
        distrobox rm --yes "$CONTAINER_NAME" >/dev/null || true
    fi
    if "${RUNTIME}" ps -a --format '{{.Names}}' 2>/dev/null | grep -qw "$CONTAINER_NAME"; then
        "${RUNTIME}" rm -f "$CONTAINER_NAME" >/dev/null || true
    fi
fi

# Probe whether distrobox is installed and create + enter works on this host/runtime
# (e.g. pure Podman/Docker hosts without distrobox, or Docker on Ubuntu 24.04 failing
# with 'openat dev/ptmx: no such device' when distrobox bind-mounts /dev).
# If so, fall back to Isolated Sandbox mode.
if command -v distrobox &>/dev/null && \
   log_info "Creating distrobox container '$CONTAINER_NAME'..." && \
   distrobox create -i "$IMAGE_NAME" -n "$CONTAINER_NAME" --hostname "$CONTAINER_NAME" --home "$TEST_HOME" --yes && \
   sleep 2 && \
   distrobox enter "$CONTAINER_NAME" -- true 2>/dev/null; then
    log_success "Created distrobox container '$CONTAINER_NAME'."
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
        if ! grep -qF "'/usr/local/bin/agy'" "$shim" && ! grep -qF "'$TEST_HOME/.local/bin/agy'" "$shim"; then
            log_error "Exported agy shim does not point at the box's /usr/local/bin/agy or ~/.local/bin/agy:"
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
    distrobox enter "$CONTAINER_NAME" -- "$REPO_DIR/scripts/assert-box.sh"
    distrobox enter "$CONTAINER_NAME" -- sh -c '
        grep -q "^quick_exec=1" /etc/xdg/libfm/libfm.conf &&
        grep -q "^quick_exec=1" /etc/skel/.config/libfm/libfm.conf &&
        test -f /etc/skel/Desktop/Antigravity.desktop &&
        ! test -e /etc/skel/Desktop/Antigravity2.desktop &&
        grep -q -- "--password-store=basic" /usr/local/bin/antigravity &&
        grep -q -- "--password-store=basic" /usr/bin/code &&
        grep -q -- "--password-store=basic" /usr/bin/google-chrome-stable
    '

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

    # --- Optional: headless VDI desktop (noVNC on :6080) ---
    if [[ "${VDI_TEST:-false}" = "true" ]]; then
        log_info "Starting agy-vdi and waiting for noVNC on http://127.0.0.1:6080 ..."
        distrobox enter "$CONTAINER_NAME" -- /usr/local/bin/agy-vdi > "$TEST_ROOT/vdi.log" 2>&1 &
        vdi_pid=$!
        vdi_ready=false
        for _ in {1..30}; do
            if curl -s -f http://127.0.0.1:6080/vnc.html >/dev/null 2>&1 && python3 -c '
import socket, sys
try:
    s = socket.create_connection(("127.0.0.1", 6080), timeout=2)
    s.sendall(b"GET /websockify HTTP/1.1\r\nHost: 127.0.0.1:6080\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: binary\r\n\r\n")
    res = s.recv(4096)
    if b"101 Switching Protocols" not in res:
        sys.exit(1)
    frame = s.recv(4096)
    if b"RFB 003." not in frame:
        sys.exit(1)
    sys.exit(0)
except Exception:
    sys.exit(1)
' 2>/dev/null; then
                vdi_ready=true
                break
            fi
            sleep 1
        done
        kill "$vdi_pid" 2>/dev/null || true
        distrobox enter "$CONTAINER_NAME" -- pkill -f "websockify|x11vnc|Xvfb" 2>/dev/null || true
        if [[ "$vdi_ready" != "true" ]]; then
            log_error "noVNC/RFB WebSocket did not respond within 30 seconds:"
            cat "$TEST_ROOT/vdi.log" >&2 || true
            exit 1
        fi
        log_success "VDI web desktop & RFB WebSocket responded on port 6080."
    fi
else
    log_warn "distrobox enter unavailable on this host/arch (${RUNTIME}); validating via Isolated Sandbox mode (agyuser)..."
    if command -v distrobox &>/dev/null; then
        distrobox rm --yes "$CONTAINER_NAME" >/dev/null 2>&1 || true
    fi
    "${RUNTIME}" rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true

    sandbox_flags=(
        -d
        --name "$CONTAINER_NAME"
        --hostname "$CONTAINER_NAME"
        -v "$TEST_HOME:/home/agyuser"
        -v "$REPO_DIR:/mnt/repo:ro"
    )
    if [[ "$RUNTIME" = "podman" ]]; then
        if [[ "$(id -u)" -ne 0 ]]; then
            podman unshare chown -R 9000:9000 "$TEST_HOME" 2>/dev/null || true
        fi
        sandbox_flags+=(--security-opt label=disable)
    else
        sandbox_flags+=(-e "PUID=$(id -u)" -e "PGID=$(id -g)")
    fi

    "${RUNTIME}" run "${sandbox_flags[@]}" "$IMAGE_NAME" sleep infinity

    # Wait briefly for entrypoint.sh to finish configuring agyuser and sudoers
    sleep 3

    log_info "Running test assertions inside sandbox container as agyuser..."
    "${RUNTIME}" exec -u agyuser -w /home/agyuser "$CONTAINER_NAME" /mnt/repo/scripts/assert-box.sh
    "${RUNTIME}" exec -u agyuser -w /home/agyuser "$CONTAINER_NAME" sh -c '
        grep -q "^quick_exec=1" /etc/xdg/libfm/libfm.conf &&
        grep -q "^quick_exec=1" /home/agyuser/.config/libfm/libfm.conf &&
        test -f /home/agyuser/Desktop/Antigravity.desktop &&
        ! test -e /home/agyuser/Desktop/Antigravity2.desktop &&
        grep -q -- "--password-store=basic" /usr/local/bin/antigravity &&
        grep -q -- "--password-store=basic" /usr/bin/code &&
        grep -q -- "--password-store=basic" /usr/bin/google-chrome-stable
    '

    # --- Optional: headless VDI desktop (noVNC on :6080) ---
    if [[ "${VDI_TEST:-false}" = "true" ]]; then
        log_info "Starting agy-vdi inside sandbox container and waiting for noVNC on http://127.0.0.1:6080 ..."
        "${RUNTIME}" exec -e HOME=/home/agyuser -u agyuser -w /home/agyuser "$CONTAINER_NAME" /usr/local/bin/agy-vdi > "$TEST_ROOT/vdi.log" 2>&1 &
        vdi_pid=$!
        vdi_ready=false
        for _ in {1..30}; do
            if "$RUNTIME" exec -u agyuser "$CONTAINER_NAME" curl -fsS http://127.0.0.1:6080/vnc.html >/dev/null 2>&1 && \
               "$RUNTIME" exec -u agyuser "$CONTAINER_NAME" python3 -c '
import socket, sys
try:
    s = socket.create_connection(("127.0.0.1", 6080), timeout=2)
    s.sendall(b"GET /websockify HTTP/1.1\r\nHost: 127.0.0.1:6080\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Protocol: binary\r\n\r\n")
    res = s.recv(4096)
    if b"101 Switching Protocols" not in res:
        sys.exit(1)
    frame = s.recv(4096)
    if b"RFB 003." not in frame:
        sys.exit(1)
    sys.exit(0)
except Exception:
    sys.exit(1)
' 2>/dev/null; then
                vdi_ready=true
                break
            fi
            sleep 1
        done
        kill "$vdi_pid" 2>/dev/null || true
        "$RUNTIME" exec -u agyuser "$CONTAINER_NAME" pkill -f "websockify|x11vnc|Xvfb" 2>/dev/null || true
        if [[ "$vdi_ready" != "true" ]]; then
            log_error "noVNC/RFB WebSocket did not respond within 30 seconds:"
            cat "$TEST_ROOT/vdi.log" >&2 || true
            exit 1
        fi
        log_success "VDI web desktop & RFB WebSocket responded on port 6080."
    fi
fi

log_success "Integration tests finished successfully!"
