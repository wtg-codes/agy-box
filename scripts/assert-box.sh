#!/bin/bash
# scripts/assert-box.sh - Asserts that the toolchain is healthy inside the container.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
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
    local ver_out
    if ! ver_out=$(eval "$ver_cmd" 2>&1); then
        echo -e "${RED}FAILED (command failed to execute)${NC}"
        echo -e "${YELLOW}Command: $ver_cmd${NC}"
        echo -e "${YELLOW}Output:${NC} $ver_out"
        return 1
    fi
    
    echo -e "${GREEN}PASSED${NC}"
    return 0
}

errors=0

# Assert System & Sandbox User Privileges
assert_cmd "Passwordless sudo" "sudo" "sudo -n true" || errors=$((errors+1))

# Assert CNCF Tools
assert_cmd "kubectl" "kubectl" "kubectl version --client" || errors=$((errors+1))
assert_cmd "helm" "helm" "helm version" || errors=$((errors+1))
assert_cmd "k9s" "k9s" "k9s version" || errors=$((errors+1))

# Assert AI Agent Tools
assert_cmd "Toolchain installer (agy-install-toolchain)" "agy-install-toolchain" "test -f /usr/local/bin/agy-install-toolchain && test -x /usr/local/bin/agy-install-toolchain" || errors=$((errors+1))
assert_cmd "Gemini CLI" "gemini" "gemini --help" || errors=$((errors+1))
assert_cmd "Google ADK" "adk" "adk --help" || errors=$((errors+1))
assert_cmd "Antigravity CLI (agy)" "agy" "agy --version" || errors=$((errors+1))
assert_cmd "Antigravity SDK (Agent + LocalAgentConfig, offline)" "python3" "python3 -c \"from google.antigravity import Agent, LocalAgentConfig; LocalAgentConfig(api_key='ci-offline-check')\"" || errors=$((errors+1))
# Login shells find the toolchain on PATH
assert_cmd "Toolchain on login-shell PATH (profile.d)" "sh" "env PATH=/usr/local/bin:/usr/bin:/bin sh -c '. /etc/profile.d/agy-toolchain.sh && test -n \"\$(command -v agy)\"'" || errors=$((errors+1))

# Assert Desktop Apps (Checking path & permissions)
assert_cmd "Google Chrome" "google-chrome-stable" "google-chrome-stable --version" || errors=$((errors+1))
assert_cmd "Google Antigravity (Agent UI)" "antigravity" "{ test -x /usr/local/bin/antigravity && test -d /opt/antigravity; } || { test -x \"$HOME/.local/bin/antigravity\" && test -d \"$HOME/.local/share/antigravity\"; }" || errors=$((errors+1))
assert_cmd "No legacy Antigravity IDE" "sh" "! test -e /usr/local/bin/antigravity-ide && ! test -d /opt/antigravity-ide" || errors=$((errors+1))
assert_cmd "Visual Studio Code" "code" "code --version" || errors=$((errors+1))
assert_cmd "Zed" "zed" "zed --version" || errors=$((errors+1))
assert_cmd "JetBrains IDE Installer" "agy-install-ide" "test -x /usr/local/bin/agy-install-ide" || errors=$((errors+1))
assert_cmd "IceWM Startup Script" "icewm-session" "test -x /etc/X11/icewm/startup" || errors=$((errors+1))
assert_cmd "IceWM Preferences" "icewm-session" "test -f /etc/X11/icewm/preferences" || errors=$((errors+1))
assert_cmd "PCManFM quick_exec=1 config" "pcmanfm" "grep -q '^quick_exec=1' /etc/xdg/libfm/libfm.conf && grep -q '^quick_exec=1' /etc/skel/.config/libfm/libfm.conf" || errors=$((errors+1))
assert_cmd "Deduplicated Desktop Launchers & Icons" "sh" "test -f /etc/skel/Desktop/Antigravity.desktop && ! test -e /etc/skel/Desktop/Antigravity2.desktop && grep -q '^Name=Google Antigravity$' /etc/skel/Desktop/Antigravity.desktop && grep -q '^Icon=/usr/share/pixmaps/antigravity.png$' /etc/skel/Desktop/Antigravity.desktop && test -s /usr/share/pixmaps/antigravity.png && grep -q '^Name=Python SDK & ADK$' /etc/skel/Desktop/AntigravitySDK.desktop" || errors=$((errors+1))
assert_cmd "D-Bus session tools & wrapper --password-store=basic" "dbus-daemon" "command -v dbus-send >/dev/null && grep -q -- '--password-store=basic' /usr/local/bin/antigravity && grep -q -- '--password-store=basic' /usr/bin/code && grep -q -- '--password-store=basic' /usr/bin/google-chrome-stable" || errors=$((errors+1))

assert_cmd "No bundled Open WebUI" "sh" "! test -e /opt/open-webui-venv && ! command -v open-webui >/dev/null 2>&1" || errors=$((errors+1))

if [ "$errors" -gt 0 ]; then
    echo -e "${RED}✗ $errors test assertions failed inside the container.${NC}"
    exit 1
else
    echo -e "${GREEN}✓ All test assertions passed inside the container!${NC}"
    exit 0
fi
