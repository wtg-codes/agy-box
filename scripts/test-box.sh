#!/bin/bash
# test-box.sh - Integration test runner for agy-box Sandbox (default) and Workstation (Distrobox) modes
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

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

CONTAINER_NAME="agy-box-test-sandbox"
DBX_CONTAINER_NAME="agy-box-test-workstation"
IMAGE_NAME="${IMAGE_NAME:-localhost/agy-box:dev}"

TEST_ROOT="$(mktemp -d /tmp/agy-box-test.XXXXXX)"
SANDBOX_HOME="$TEST_ROOT/sandbox-home"
DBX_HOME="$TEST_ROOT/dbx-home"
mkdir -p "$SANDBOX_HOME" "$DBX_HOME"

log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(dirname "$SCRIPT_DIR")

cleanup_one() {
    local rt="$1" cname="$2"
    if "$rt" ps -a --format '{{.Names}}' 2>/dev/null | grep -qw "$cname"; then
        log_info "Removing container '$cname'..."
        if command -v distrobox &>/dev/null && distrobox list --no-color 2>/dev/null | grep -qw "$cname"; then
            distrobox rm --yes "$cname" >/dev/null 2>&1 || true
        fi
        "$rt" rm -f "$cname" >/dev/null 2>&1 || true
    fi
}

cleanup() {
    log_info "Cleaning up..."
    local rt="${RUNTIME:-}"
    if [[ -z "$rt" ]]; then
        if command -v podman &>/dev/null; then rt="podman"; else rt="docker"; fi
    fi
    cleanup_one "$rt" "$CONTAINER_NAME"
    cleanup_one "$rt" "$DBX_CONTAINER_NAME"
    if [[ "$rt" = "podman" ]] && [[ "$(id -u)" -ne 0 ]]; then
        podman unshare rm -rf "$TEST_ROOT" 2>/dev/null || true
    fi
    rm -rf "$TEST_ROOT" 2>/dev/null || true
}
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
    log_success "Host checks passed. Runtime: $RUNTIME (Distrobox optional / not installed)"
fi

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

if [[ "${PULL:-false}" = "true" ]]; then
    log_info "Pulling $IMAGE_NAME..."
    "$RUNTIME" pull "$IMAGE_NAME"
    SKIP_BUILD=true
fi

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
    log_success "Using pre-built image $IMAGE_NAME."
else
    log_info "Building image $IMAGE_NAME..."
    "$RUNTIME" build -t "$IMAGE_NAME" -f "$REPO_DIR/Containerfile" "$REPO_DIR"
    log_success "Built image successfully."
    mkdir -p "$(dirname "$STATE_FILE")"
    echo "$CURRENT_HASH" > "$STATE_FILE"
fi

# --- 1. Validate Default Isolated Sandbox Mode (Podman/Docker) ---
cleanup_one "$RUNTIME" "$CONTAINER_NAME"
log_info "Starting Isolated Sandbox container '$CONTAINER_NAME'..."
sandbox_flags=(
    -d
    --name "$CONTAINER_NAME"
    --hostname "$CONTAINER_NAME"
    -v "$SANDBOX_HOME:/home/agyuser"
    -v "$REPO_DIR:/mnt/repo:ro"
)
if [[ "$RUNTIME" = "podman" ]]; then
    if [[ "$(id -u)" -ne 0 ]]; then
        podman unshare chown -R 9000:9000 "$SANDBOX_HOME" 2>/dev/null || true
    fi
    sandbox_flags+=(--security-opt label=disable)
else
    sandbox_flags+=(-e "PUID=$(id -u)" -e "PGID=$(id -g)")
fi

"${RUNTIME}" run "${sandbox_flags[@]}" "$IMAGE_NAME" sleep infinity
sleep 3

log_info "Running assertions & agy-doctor inside Sandbox container as agyuser..."
"${RUNTIME}" exec -u agyuser -w /home/agyuser "$CONTAINER_NAME" /mnt/repo/scripts/assert-box.sh
"${RUNTIME}" exec -e HOME=/home/agyuser -u agyuser -w /home/agyuser "$CONTAINER_NAME" /usr/local/bin/agy-doctor
"${RUNTIME}" exec -u agyuser -w /home/agyuser "$CONTAINER_NAME" sh -c '
    test -s /home/agyuser/.local/state/agy-box/entrypoint.log &&
    test -w /home/agyuser/.local/state/agy-box/entrypoint.log &&
    test -s /home/agyuser/.local/state/agy-box/doctor.log &&
    grep -q "^quick_exec=1" /etc/xdg/libfm/libfm.conf &&
    grep -q "^quick_exec=1" /home/agyuser/.config/libfm/libfm.conf &&
    test -f /home/agyuser/Desktop/Antigravity.desktop &&
    ! test -e /home/agyuser/Desktop/Antigravity2.desktop &&
    ! test -e /home/agyuser/Desktop/SetupAssistant.desktop &&
    grep -q -- "--password-store=basic" /usr/local/bin/antigravity &&
    grep -q -- "--password-store=basic" /usr/bin/code &&
    grep -q -- "--password-store=basic" /usr/bin/google-chrome-stable
'

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
    "$RUNTIME" exec -u agyuser "$CONTAINER_NAME" test -s /home/agyuser/.local/state/agy-box/vdi.log
    "$RUNTIME" exec -u agyuser "$CONTAINER_NAME" test -L /tmp/agy-vdi.log
    kill "$vdi_pid" 2>/dev/null || true
    "$RUNTIME" exec -u agyuser "$CONTAINER_NAME" pkill -f "websockify|x11vnc|Xvfb" 2>/dev/null || true
    if [[ "$vdi_ready" != "true" ]]; then
        log_error "noVNC/RFB WebSocket did not respond within 30 seconds:"
        cat "$TEST_ROOT/vdi.log" >&2 || true
        exit 1
    fi
    log_success "VDI web desktop & RFB WebSocket responded on port 6080."
fi
cleanup_one "$RUNTIME" "$CONTAINER_NAME"
log_success "Default Isolated Sandbox mode checks passed!"

# --- 2. Optional Workstation Mode (Distrobox, when supported on host/arch) ---
cleanup_one "$RUNTIME" "$DBX_CONTAINER_NAME"
if command -v distrobox &>/dev/null && \
   log_info "Testing optional Workstation mode ('$DBX_CONTAINER_NAME')..." && \
   distrobox create -i "$IMAGE_NAME" -n "$DBX_CONTAINER_NAME" --hostname "$DBX_CONTAINER_NAME" --home "$DBX_HOME" --yes && \
   sleep 2 && \
   distrobox enter "$DBX_CONTAINER_NAME" -- true 2>/dev/null; then
    distrobox enter "$DBX_CONTAINER_NAME" -- "$REPO_DIR/scripts/assert-box.sh"
    distrobox enter "$DBX_CONTAINER_NAME" -- /usr/local/bin/agy-doctor
    distrobox enter "$DBX_CONTAINER_NAME" -- test -s "$DBX_HOME/.local/state/agy-box/doctor.log"
    cleanup_one "$RUNTIME" "$DBX_CONTAINER_NAME"
    log_success "Optional Distrobox Workstation mode checks passed!"
else
    log_warn "Distrobox enter unavailable on this host/runtime (${RUNTIME}); skipped optional Workstation mode check."
    cleanup_one "$RUNTIME" "$DBX_CONTAINER_NAME"
fi

log_success "Integration tests finished successfully!"
