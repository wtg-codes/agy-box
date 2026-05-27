#!/bin/bash
# scripts/assert-box.sh - Asserts that the toolchain is healthy inside the container.
set -euo pipefail

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
assert_cmd "Google Antigravity (Agent UI)" "antigravity" "test -x /usr/bin/antigravity" || errors=$((errors+1))
assert_cmd "Antigravity IDE" "antigravity-ide" "test -x /usr/bin/antigravity-ide" || errors=$((errors+1))

if [ "$errors" -gt 0 ]; then
    echo -e "${RED}✗ $errors test assertions failed inside the container.${NC}"
    exit 1
else
    echo -e "${GREEN}✓ All test assertions passed inside the container!${NC}"
    exit 0
fi
