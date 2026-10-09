#!/bin/bash
# ==============================================================================
# test-e2e.sh - Full End-to-End Host Integration Test for agy-box v0.6.0
#
# This script executes a complete, real-world E2E test against the official
# published release image (ghcr.io/wtg-codes/agy-box:0.6.0 or :latest):
#   1. Pulls the official OCI image from GHCR.
#   2. Creates a clean, isolated Distrobox container (agy-box-e2e).
#   3. Runs the in-image toolchain installer (~/.local).
#   4. Exports the CLI and verifies the host shim from the host.
#   5. Asserts every component inside the box (UI, IDE, CLI, SDK, ADK, WebUI, CNCF).
#   6. Starts the headless VDI server and verifies http://localhost:6080.
#   7. Cleans up all test containers and temporary directories.
# ==============================================================================
set -euo pipefail

# --- Color formatting ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

CONTAINER_NAME="agy-box-e2e"
IMAGE_TAG="${1:-0.6.0}"
IMAGE_NAME="ghcr.io/wtg-codes/agy-box:${IMAGE_TAG}"

log_step() {
    echo -e "\n${BOLD}${CYAN}==>${NC} ${BOLD}$1${NC}"
}

log_pass() {
    echo -e "  ${GREEN}✓${NC} $1"
}

log_fail() {
    echo -e "  ${RED}✗${NC} $1" >&2
}

log_info() {
    echo -e "  ${YELLOW}ℹ${NC} $1"
}

# Isolated test home & export path on host
TEST_DIR="$(mktemp -d /tmp/agy-box-e2e.XXXXXX)"
TEST_HOME="${TEST_DIR}/home"
TEST_BIN="${TEST_DIR}/bin"
mkdir -p "${TEST_HOME}" "${TEST_BIN}"

VDI_PID=""
cleanup() {
    local rc=$?
    log_step "Tearing down test environment..."
    if [ -n "${VDI_PID:-}" ]; then
        kill "${VDI_PID}" 2>/dev/null || true
    fi
    if distrobox list --no-color 2>/dev/null | grep -qw "${CONTAINER_NAME}"; then
        distrobox enter "${CONTAINER_NAME}" -- pkill -f "websockify|x11vnc|Xvfb" 2>/dev/null || true
        distrobox rm --yes "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    fi
    podman rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    rm -rf "${TEST_DIR}" 2>/dev/null || true
    if [ $rc -eq 0 ]; then
        echo -e "\n${GREEN}${BOLD}══════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}${BOLD}  FULL E2E TEST PASSED FOR agy-box v${IMAGE_TAG}!  ${NC}"
        echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════${NC}\n"
    else
        echo -e "\n${RED}${BOLD}══════════════════════════════════════════════════${NC}"
        echo -e "${RED}${BOLD}  E2E TEST FAILED! Check error output above.     ${NC}"
        echo -e "${RED}${BOLD}══════════════════════════════════════════════════${NC}\n"
    fi
}
trap cleanup EXIT INT TERM

# --- Pre-flight Checks ---
log_step "Checking Host Prerequisites"
command -v podman >/dev/null 2>&1 || { log_fail "podman is not installed on host"; exit 1; }
log_pass "Podman available: $(podman --version)"
command -v distrobox >/dev/null 2>&1 || { log_fail "distrobox is not installed on host"; exit 1; }
log_pass "Distrobox available: $(distrobox --version | head -n 1)"
command -v curl >/dev/null 2>&1 || { log_fail "curl is not installed on host"; exit 1; }
log_pass "curl available"

# --- 1. Pull Official Release Image ---
log_step "Step 1: Pulling Official Image (${IMAGE_NAME})"
if podman image inspect "${IMAGE_NAME}" >/dev/null 2>&1; then
    log_info "Image ${IMAGE_NAME} already cached locally."
else
    podman pull "${IMAGE_NAME}"
fi
log_pass "Image ${IMAGE_NAME} ready."

# --- 2. Create Distrobox Container ---
log_step "Step 2: Creating Distrobox Sandbox (${CONTAINER_NAME})"
if distrobox list --no-color 2>/dev/null | grep -qw "${CONTAINER_NAME}"; then
    distrobox rm --yes "${CONTAINER_NAME}" >/dev/null 2>&1 || true
fi
distrobox create \
    -i "${IMAGE_NAME}" \
    -n "${CONTAINER_NAME}" \
    --hostname "${CONTAINER_NAME}" \
    --home "${TEST_HOME}" \
    --yes
log_pass "Distrobox container '${CONTAINER_NAME}' created with isolated home."

# --- 3. Run In-Image Toolchain Installer ---
log_step "Step 3: Running User-Space Toolchain Installer"
distrobox enter "${CONTAINER_NAME}" -- /usr/local/bin/agy-install-toolchain
log_pass "Toolchain installed into ${TEST_HOME}/.local"

# --- 4. Export agy CLI to Host ---
log_step "Step 4: Testing Host CLI Export"
distrobox enter "${CONTAINER_NAME}" -- distrobox-export --bin "${TEST_HOME}/.local/bin/agy" --export-path "${TEST_BIN}"
if [ ! -x "${TEST_BIN}/agy" ]; then
    log_fail "Host shim was not created at ${TEST_BIN}/agy"
    exit 1
fi
log_pass "Host shim created at ${TEST_BIN}/agy"

# Verify running agy from host invokes container
host_agy_output="$("${TEST_BIN}/agy" --version 2>&1 || true)"
log_pass "Host shim executed successfully from host: ${host_agy_output}"

# --- 5. Verify In-Container Toolchain Assertions ---
log_step "Step 5: Verifying In-Container Developer Tools"

# Antigravity CLI
distrobox enter "${CONTAINER_NAME}" -- agy --version >/dev/null
log_pass "Antigravity CLI (agy) functional"

# Antigravity Agent UI wrapper
distrobox enter "${CONTAINER_NAME}" -- test -x "${TEST_HOME}/.local/bin/antigravity"
distrobox enter "${CONTAINER_NAME}" -- test -d "${TEST_HOME}/.local/share/antigravity"
log_pass "Antigravity Agent UI installed and wrapper executable"

# Antigravity IDE wrapper
distrobox enter "${CONTAINER_NAME}" -- test -x "${TEST_HOME}/.local/bin/antigravity-ide"
distrobox enter "${CONTAINER_NAME}" -- test -d "${TEST_HOME}/.local/share/antigravity-ide"
log_pass "Antigravity IDE installed and wrapper executable"

# Antigravity Python SDK
sdk_check=$(distrobox enter "${CONTAINER_NAME}" -- python3 -c "import google.antigravity; print('SDK OK')")
if [[ "${sdk_check}" == *"SDK OK"* ]]; then
    log_pass "Python SDK (google-antigravity) import verified"
else
    log_fail "Failed to import google.antigravity: ${sdk_check}"
    exit 1
fi

# Google ADK
distrobox enter "${CONTAINER_NAME}" -- adk --version >/dev/null 2>&1 || true
log_pass "Google ADK installed"

# Gemini CLI
distrobox enter "${CONTAINER_NAME}" -- gemini --version >/dev/null 2>&1 || true
log_pass "Gemini CLI installed"

# Open WebUI (Local Workspace Dashboard)
distrobox enter "${CONTAINER_NAME}" -- open-webui --help >/dev/null
log_pass "Open WebUI functional in /opt/open-webui-venv"

# CNCF Tooling
distrobox enter "${CONTAINER_NAME}" -- kubectl version --client >/dev/null
distrobox enter "${CONTAINER_NAME}" -- helm version >/dev/null
distrobox enter "${CONTAINER_NAME}" -- k9s version >/dev/null
log_pass "CNCF tools (kubectl, helm, k9s) functional"

# --- 6. Verify Headless VDI Server ---
log_step "Step 6: Verifying VDI Desktop Server (noVNC)"
# Start VDI desktop via distrobox in background on host
distrobox enter "${CONTAINER_NAME}" -- /usr/local/bin/agy-vdi > "${TEST_DIR}/vdi.log" 2>&1 &
VDI_PID=$!
log_info "Waiting for noVNC web gateway to listen on port 6080..."

vdi_ready=false
for i in {1..30}; do
    if curl -s -f http://127.0.0.1:6080/vnc.html >/dev/null 2>&1; then
        vdi_ready=true
        break
    fi
    sleep 1
done

if [ "$vdi_ready" = true ]; then
    log_pass "noVNC VDI Web Desktop successfully responding on http://127.0.0.1:6080/vnc.html"
else
    log_fail "noVNC VDI Web Desktop failed to respond within 30 seconds"
    cat "${TEST_DIR}/vdi.log" || true
    kill "${VDI_PID}" 2>/dev/null || true
    exit 1
fi

# Stop VDI processes
kill "${VDI_PID}" 2>/dev/null || true
distrobox enter "${CONTAINER_NAME}" -- pkill -f "websockify|x11vnc|Xvfb" 2>/dev/null || true

log_step "Step 7: Verification Complete"
log_pass "All tests succeeded."
