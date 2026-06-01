#!/usr/bin/env bats

setup() {
  # Create a unique temp directory
  TEST_DIR="$(mktemp -d)"
  MOCK_BIN="$TEST_DIR/bin"
  
  # Create directories before we mock mkdir
  mkdir -p "$MOCK_BIN"
  mkdir -p "$TEST_DIR/usr/bin"
  mkdir -p "$TEST_DIR/var/lib/apt/lists"
  mkdir -p "$TEST_DIR/etc/apt/sources.list.d"
  mkdir -p "$TEST_DIR/usr/share/keyrings"
  
  export TEST_LOG="$TEST_DIR/invocations.log"
  touch "$TEST_LOG"
  
  # Create a generic mock builder helper
  create_mock() {
    local cmd="$1"
    local code="$2"
    cat <<EOF > "$MOCK_BIN/$cmd"
#!/bin/bash
echo "$cmd \$*" >> "$TEST_LOG"
$code
EOF
    chmod +x "$MOCK_BIN/$cmd"
  }

  # Create specific mocks
  # Mock curl: handles download files creation
  create_mock "curl" '
    for arg in "$@"; do
      if [[ "$arg" =~ http.*/([^/]+)$ ]]; then
        file="${BASH_REMATCH[1]}"
        if [[ "$file" == "checksums.sha256" ]]; then
          echo "dummyhash  k9s_Linux_amd64.tar.gz" > "$file"
          echo "dummyhash  k9s_Linux_arm64.tar.gz" >> "$file"
        elif [[ "$file" == "kubectl.sha256" ]]; then
          echo "dummyhash" > "$file"
        elif [[ "$file" == "helm-v3.21.0-linux-arm64.tar.gz.sha256" ]]; then
          echo "dummyhash" > "$file"
        else
          touch "$file"
        fi
      fi
    done
    exit 0
  '
  
  # Mock sha256sum
  create_mock "sha256sum" 'exit 0'
  create_mock "sha512sum" 'exit 0'
  
  # Mock tar: creates expected files when run
  create_mock "tar" '
    if [[ "$*" =~ k9s ]]; then
      touch k9s
    fi
    if [[ "$*" =~ helm ]]; then
      mkdir -p linux-amd64 linux-arm64
      touch linux-amd64/helm linux-arm64/helm
    fi
    if [[ "$*" =~ cli_linux_x64 ]]; then
      mkdir -p /tmp
      touch /tmp/antigravity
    fi
    exit 0
  '
  
  # Mock install
  create_mock "install" 'exit 0'
  
  # Mock pipx
  create_mock "pipx" 'exit 0'
  
  # Mock npm
  create_mock "npm" 'exit 0'

  # Mock pip3
  create_mock "pip3" 'exit 0'
  
  # Mock apt-get
  create_mock "apt-get" 'exit 0'
  
  # Mock wget
  create_mock "wget" 'exit 0'
  
  # Mock gpg
  create_mock "gpg" 'exit 0'
  
  # Prepend mock bin to PATH
  export ORIGINAL_PATH="$PATH"
  export PATH="$MOCK_BIN:$PATH"
}

teardown() {
  # Restore PATH and clean up temp directory
  export PATH="$ORIGINAL_PATH"
  rm -rf "$TEST_DIR"
}

@test "install-tools.sh pins and installs correct versions of kubectl, k9s, and helm" {
  run ./scripts/install-tools.sh
  [ "$status" -eq 0 ]
  
  # Verify kubectl version in curl commands
  grep -F 'curl -LO --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 https://dl.k8s.io/release/v1.36.1/bin/linux/amd64/kubectl' "$TEST_LOG"
  
  # Verify kubectl SHA256 verification
  grep -F 'sha256sum -c -' "$TEST_LOG"
  
  # Verify k9s version in curl commands
  grep -F 'curl -sSLO --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 https://github.com/derailed/k9s/releases/download/v0.50.18/k9s_Linux_amd64.tar.gz' "$TEST_LOG"
  grep -F 'curl -sSLO --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 https://github.com/derailed/k9s/releases/download/v0.50.18/checksums.sha256' "$TEST_LOG"
  
  # Verify helm version in curl commands
  grep -F 'curl -sSLO --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 https://get.helm.sh/helm-v3.21.0-linux-amd64.tar.gz' "$TEST_LOG"
}

@test "install-google-adk.sh pins and installs correct version of google-adk" {
  run ./scripts/install-google-adk.sh
  [ "$status" -eq 0 ]
  
  # Verify pipx install command pins google-adk to 2.1.0
  grep -E 'pipx install google-adk==2.1.0' "$TEST_LOG"
}

@test "install-gemini-cli.sh pins and installs correct version of gemini-cli" {
  run ./scripts/install-gemini-cli.sh
  [ "$status" -eq 0 ]
  
  # Verify npm install command pins @google/gemini-cli@0.43.0
  grep -E 'npm install -g --omit=dev --no-audit --no-fund @google/gemini-cli@0.43.0' "$TEST_LOG"
}

@test "install-agent-deps.sh pins and installs correct versions of gum and google-chrome-stable" {
  # Mock system commands to prevent actual wrapper modification or errors
  # (e.g. mv, printf, chmod, mkdir) since we don't want them to execute/fail
  create_mock "mv" 'exit 0'
  create_mock "printf" 'exit 0'
  create_mock "chmod" 'exit 0'
  create_mock "mkdir" 'exit 0'
  
  touch "$TEST_DIR/usr/bin/google-chrome-stable"
  
  sed -e "s|/etc/apt|$TEST_DIR/etc/apt|g" \
      -e "s|/usr/share|$TEST_DIR/usr/share|g" \
      -e "s|/usr/bin|$TEST_DIR/usr/bin|g" \
      -e "s|/var/lib|$TEST_DIR/var/lib|g" \
      ./scripts/install-agent-deps.sh > "$TEST_DIR/install-agent-deps.sh"
  chmod +x "$TEST_DIR/install-agent-deps.sh"
  
  run "$TEST_DIR/install-agent-deps.sh"
  [ "$status" -eq 0 ]
  
  # Verify gum and google-chrome-stable pins
  grep -F 'apt-get install -y --no-install-recommends gum=0.17.0-1' "$TEST_LOG"
  grep -F 'apt-get install -y --no-install-recommends google-chrome-stable=148.0.7778.215-1' "$TEST_LOG"
}

@test "install-agent-deps.sh on arm64 installs chromium" {
  create_mock "mv" 'exit 0'
  create_mock "printf" 'exit 0'
  create_mock "chmod" 'exit 0'
  create_mock "mkdir" 'exit 0'
  
  touch "$TEST_DIR/usr/bin/google-chrome-stable"
  
  sed -e "s|/etc/apt|$TEST_DIR/etc/apt|g" \
      -e "s|/usr/share|$TEST_DIR/usr/share|g" \
      -e "s|/usr/bin|$TEST_DIR/usr/bin|g" \
      -e "s|/var/lib|$TEST_DIR/var/lib|g" \
      ./scripts/install-agent-deps.sh > "$TEST_DIR/install-agent-deps.sh"
  chmod +x "$TEST_DIR/install-agent-deps.sh"
  
  run "$TEST_DIR/install-agent-deps.sh" arm64
  [ "$status" -eq 0 ]
  
  grep -F 'apt-get install -y --no-install-recommends gum=0.17.0-1' "$TEST_LOG"
  grep -E 'apt-get install -y --no-install-recommends chromium' "$TEST_LOG"
}

@test "install-tools.sh on arm64 fetches and installs arm64 versions" {
  run ./scripts/install-tools.sh arm64
  [ "$status" -eq 0 ]
  
  grep -F 'curl -LO --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 https://dl.k8s.io/release/v1.36.1/bin/linux/arm64/kubectl' "$TEST_LOG"
  grep -F 'curl -sSLO --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 https://github.com/derailed/k9s/releases/download/v0.50.18/k9s_Linux_arm64.tar.gz' "$TEST_LOG"
  grep -F 'curl -sSLO --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 https://get.helm.sh/helm-v3.21.0-linux-arm64.tar.gz' "$TEST_LOG"
}

@test "install-agent-toolchain.sh downloads and installs agent tools at user level" {
  # Mock home directory
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  
  run ./scripts/install-agent-toolchain.sh
  [ "$status" -eq 0 ]
  
  # Verify it downloaded UI and IDE tarballs
  grep -F 'curl -fsSL --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 https://storage.googleapis.com/antigravity-public/antigravity-hub/2.0.1-6566078776737792/linux-x64/Antigravity.tar.gz' "$TEST_LOG"
  grep -F 'curl -fsSL --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/1.23.2-4781536860569600/linux-x64/Antigravity.tar.gz' "$TEST_LOG"
  
  # Verify it installed python packages
  grep -F 'pip3 install --user --break-system-packages --no-cache-dir --retries 10 google-antigravity==0.1.0' "$TEST_LOG"
  grep -F 'pip3 install --user --break-system-packages --no-cache-dir --retries 10 google-adk==2.1.0' "$TEST_LOG"
  
  # Verify npm prefix installation
  grep -F 'npm install -g --prefix' "$TEST_LOG"
  grep -F '@google/gemini-cli@0.43.0' "$TEST_LOG"
}

