#!/usr/bin/env bats
# Tests for the per-user Antigravity toolchain flow:
#   - scripts/install-agent-toolchain.sh (shipped as /usr/local/bin/agy-install-toolchain)
#   - agy-box-manager helpers that run it inside the box and export the agy CLI

setup() {
  TEST_DIR="$(mktemp -d)"
  MOCK_BIN="$TEST_DIR/bin"
  mkdir -p "$MOCK_BIN"
  export TEST_LOG="$TEST_DIR/invocations.log"
  touch "$TEST_LOG"

  create_mock() {
    local cmd="$1"
    local code="$2"
    cat <<EOF2 > "$MOCK_BIN/$cmd"
#!/bin/bash
echo "$cmd \$*" >> "$TEST_LOG"
$code
EOF2
    chmod +x "$MOCK_BIN/$cmd"
  }

  export ORIGINAL_PATH="$PATH"
  export ORIGINAL_HOME="$HOME"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  export PATH="$MOCK_BIN:$PATH"
}

# Fails if the pattern matches (a bare `! grep` would not fail a bats test).
refute_grep() {
  if grep "$@"; then
    echo "unexpected match: $*"
    return 1
  fi
}

teardown() {
  export PATH="$ORIGINAL_PATH"
  export HOME="$ORIGINAL_HOME"
  rm -rf "$TEST_DIR"
}

# Mocks for the installer: no network, deterministic identity/arch.
mock_installer_env() {
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  create_mock "id" 'echo 1000'
  create_mock "uname" 'echo x86_64'
  create_mock "python3" 'exit 0'
  create_mock "sha256sum" '[ ! -t 0 ] && cat >/dev/null || true; exit 0'
  create_mock "sha512sum" '[ ! -t 0 ] && cat >/dev/null || true; exit 0'
  # curl: honour -o by creating the output file
  create_mock "curl" '
    out=""
    while [ $# -gt 0 ]; do
      if [ "$1" = "-o" ]; then out="$2"; shift; fi
      shift
    done
    if [ -n "$out" ]; then : > "$out"; fi
    exit 0'
  # tar: populate the -C target with an "antigravity" executable (and mock uv when extracting uv)
  create_mock "tar" '
    [ ! -t 0 ] && cat >/dev/null || true
    dir=""; prev=""
    for a in "$@"; do
      if [ "$prev" = "-C" ]; then dir="$a"; fi
      prev="$a"
    done
    mkdir -p "$dir"
    : > "$dir/antigravity"
    case "$*" in
      *uv-*)
        cat <<UVEOF > "$dir/uv"
#!/bin/bash
echo "uv \$*" >> "$TEST_LOG"
py=""; p=""
for arg in "\$@"; do
  if [ "\$p" = "--python" ]; then py="\$arg"; fi
  p="\$arg"
done
if [ -n "\$py" ]; then
  vbin="\$(dirname "\$py")"
  mkdir -p "\$vbin"
  printf "#!/bin/sh\n" > "\$vbin/adk"
  chmod +x "\$vbin/adk"
fi
exit 0
UVEOF
        chmod +x "$dir/uv"
        ;;
    esac
    exit 0'
  # pip3/npm: create the console scripts they would install into ~/.local/bin (or --prefix/bin)
  create_mock "pip3" '
    case "$*" in
      *google-adk*) mkdir -p "$HOME/.local/bin"; printf "#!/bin/sh\n" > "$HOME/.local/bin/adk"; chmod +x "$HOME/.local/bin/adk" ;;
    esac
    exit 0'
  create_mock "npm" '
    prefix="$HOME/.local"; prev=""
    for a in "$@"; do
      if [ "$prev" = "--prefix" ]; then prefix="$a"; fi
      prev="$a"
    done
    mkdir -p "$prefix/bin"; printf "#!/bin/sh\n" > "$prefix/bin/gemini"; chmod +x "$prefix/bin/gemini"
    exit 0'
}

@test "install-agent-toolchain.sh installs the pinned toolchain into ~/.local (never /usr/bin) and cleans up legacy antigravity-ide" {
  mock_installer_env
  mkdir -p "$HOME/.local/bin" "$HOME/.local/share/antigravity-ide" "$HOME/Desktop"
  touch "$HOME/.local/bin/antigravity-ide" "$HOME/Desktop/AntigravityIDE.desktop"
  TMPDIR="$TEST_DIR" run ./scripts/install-agent-toolchain.sh
  echo "$output"
  [ "$status" -eq 0 ]

  for bin in agy antigravity adk gemini; do
    [ -x "$HOME/.local/bin/$bin" ]
  done
  [ -f "$HOME/.local/share/antigravity/antigravity" ]
  [ ! -e "$HOME/.local/bin/antigravity-ide" ]
  [ ! -d "$HOME/.local/share/antigravity-ide" ]
  [ ! -e "$HOME/Desktop/AntigravityIDE.desktop" ]
  [ ! -e "$HOME/.local/bin/agy.new" ]
  [ ! -e "$HOME/.local/share/antigravity.new" ]

  grep -F 'https://storage.googleapis.com/antigravity-public/antigravity-hub/2.31.0-6379060755038208/linux-x64/Antigravity.tar.gz' "$TEST_LOG"
  grep -F 'https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.5-6740358537805824/linux-x64/cli_linux_x64.tar.gz' "$TEST_LOG"
  grep -F 'pip3 install --user --break-system-packages --no-cache-dir --retries 10 google-antigravity==0.1.23' "$TEST_LOG"
  grep -F 'pip3 install --user --break-system-packages --no-cache-dir --retries 10 google-adk==2.1.0' "$TEST_LOG"
  grep -F "npm install -g --prefix $HOME/.local --omit=dev --no-audit --no-fund @google/gemini-cli@0.43.0" "$TEST_LOG"
  refute_grep -F '/usr/bin/agy' "$TEST_LOG"
  [ -f "$HOME/.config/zed/settings.json" ]
  grep -F '"antigravity": true' "$HOME/.config/zed/settings.json"
}

@test "install-agent-toolchain.sh installs Antigravity VS Code extension when code is available" {
  mock_installer_env
  create_mock "code" 'exit 0'
  TMPDIR="$TEST_DIR" run ./scripts/install-agent-toolchain.sh
  [ "$status" -eq 0 ]

  grep -F 'code --install-extension Google.google-antigravity --force' "$TEST_LOG"
}

@test "install-agent-toolchain.sh --system writes /etc/skel/.vscode/extensions.json without invoking code --install-extension" {
  mock_installer_env
  create_mock "id" 'echo 0'
  create_mock "code" 'exit 0'

  sed -e "s|/etc/skel|$TEST_DIR/etc/skel|g" \
      -e "s|/usr/local|$TEST_DIR/usr/local|g" \
      -e "s|/usr/share|$TEST_DIR/usr/share|g" \
      -e "s|/opt|$TEST_DIR/opt|g" \
      ./scripts/install-agent-toolchain.sh > "$TEST_DIR/install-agent-toolchain.sh"
  chmod +x "$TEST_DIR/install-agent-toolchain.sh"

  TMPDIR="$TEST_DIR" run "$TEST_DIR/install-agent-toolchain.sh" --system
  echo "$output"
  [ "$status" -eq 0 ]

  [ -f "$TEST_DIR/etc/skel/.vscode/extensions.json" ]
  grep -F '{"recommendations": ["Google.google-antigravity"]}' "$TEST_DIR/etc/skel/.vscode/extensions.json"
  refute_grep -F 'code --install-extension' "$TEST_LOG"
  for bin in agy antigravity adk gemini; do
    [ -x "$TEST_DIR/usr/local/bin/$bin" ]
  done

  # Preserves existing extensions.json if already present
  echo '{"recommendations": ["custom.ext"]}' > "$TEST_DIR/etc/skel/.vscode/extensions.json"
  TMPDIR="$TEST_DIR" run "$TEST_DIR/install-agent-toolchain.sh" --system
  [ "$status" -eq 0 ]
  grep -F '"custom.ext"' "$TEST_DIR/etc/skel/.vscode/extensions.json"
}

@test "install-agent-toolchain.sh supports aarch64 and downloads arm64 binaries" {
  mock_installer_env
  create_mock "uname" 'echo aarch64'
  TMPDIR="$TEST_DIR" run ./scripts/install-agent-toolchain.sh
  echo "$output"
  [ "$status" -eq 0 ]

  grep -F 'https://storage.googleapis.com/antigravity-public/antigravity-cli/1.5.5-6740358537805824/linux-arm/cli_linux_arm64.tar.gz' "$TEST_LOG"
  grep -F 'https://storage.googleapis.com/antigravity-public/antigravity-hub/2.31.0-6379060755038208/linux-arm/Antigravity.tar.gz' "$TEST_LOG"
  [ -x "$HOME/.local/bin/agy" ]
}

@test "install-agent-toolchain.sh is idempotent and preserves existing user settings" {
  mock_installer_env
  TMPDIR="$TEST_DIR" run ./scripts/install-agent-toolchain.sh
  [ "$status" -eq 0 ]

  echo '{"custom": true}' > "$HOME/.config/Antigravity/User/settings.json"
  TMPDIR="$TEST_DIR" run ./scripts/install-agent-toolchain.sh
  echo "$output"
  [ "$status" -eq 0 ]
  grep -F '"custom": true' "$HOME/.config/Antigravity/User/settings.json"
  [ -x "$HOME/.local/bin/agy" ]
}

@test "install-agent-toolchain.sh fails loudly on checksum mismatch" {
  mock_installer_env
  create_mock "sha256sum" 'exit 1'
  TMPDIR="$TEST_DIR" run ./scripts/install-agent-toolchain.sh
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR: step"* ]]
  [ ! -e "$HOME/.local/bin/agy" ]
}

@test "install-agent-toolchain.sh refuses to run as root without --system" {
  mock_installer_env
  create_mock "id" 'echo 0'
  TMPDIR="$TEST_DIR" run ./scripts/install-agent-toolchain.sh
  [ "$status" -ne 0 ]
  [[ "$output" == *"do not run as root"* ]]
}

@test "Containerfile bakes toolchain with --system and ships the installer" {
  grep -E 'install-agent-toolchain.sh --system' Containerfile
  grep -E '^COPY scripts/install-agent-toolchain.sh /usr/local/bin/agy-install-toolchain$' Containerfile
  grep -F '/usr/local/bin/agy-install-toolchain' Containerfile | grep -v '^COPY'
}

# Mock distrobox: logs calls and emulates `distrobox-export --bin X --export-path D`
mock_distrobox() {
  create_mock "distrobox" '
    name=""; bin=""; dest=""; prev=""
    for a in "$@"; do
      if [ "$prev" = "enter" ]; then name="$a"; fi
      if [ "$prev" = "--bin" ]; then bin="$a"; fi
      if [ "$prev" = "--export-path" ]; then dest="$a"; fi
      prev="$a"
    done
    case "$*" in
      *test\ -x\ /usr/local/bin/agy*) exit "${MOCK_HAS_AGY:-0}" ;;
      *agy-install-toolchain*) exit "${MOCK_INSTALL_RC:-0}" ;;
    esac
    if [ -n "$bin" ] && [ -n "$dest" ]; then
      printf "#!/bin/sh\n# distrobox_binary\n# name: %s\nexec distrobox-enter -n %s -- %s\n" "$name" "$name" "$bin" > "$dest/$(basename "$bin")"
    fi
    exit 0'
}

@test "agy-box-manager: install_toolchain_in_box exports the pre-baked /usr/local/bin/agy" {
  mock_distrobox
  mkdir -p "$TEST_DIR/export"
  run bash -c 'source ./agy-box-manager && install_toolchain_in_box agy-box "$1/boxhome" "$1/export"' _ "$TEST_DIR"
  echo "$output"
  [ "$status" -eq 0 ]

  export_line=$(grep -n -F "distrobox enter agy-box -- distrobox-export --bin /usr/local/bin/agy --export-path $TEST_DIR/export" "$TEST_LOG" | cut -d: -f1)
  [ -n "$export_line" ]
  grep -F "# name: agy-box" "$TEST_DIR/export/agy"
  refute_grep -F '/usr/bin/agy' "$TEST_LOG"
}

@test "agy-box-manager: installer failure aborts before export and prints the retry command" {
  mock_distrobox
  mkdir -p "$TEST_DIR/export"
  MOCK_HAS_AGY=1 MOCK_INSTALL_RC=1 run bash -c 'source ./agy-box-manager && install_toolchain_in_box agy-box-dev "$1/boxhome" "$1/export"' _ "$TEST_DIR"
  echo "$output"
  [ "$status" -ne 0 ]
  [[ "$output" == *"agy-box-manager update-toolchain dev"* ]]
  refute_grep -F 'distrobox-export --bin' "$TEST_LOG"
  [ ! -e "$TEST_DIR/export/agy" ]
}

@test "agy-box-manager: export never clobbers a host-native agy" {
  mock_distrobox
  mkdir -p "$TEST_DIR/export"
  printf '#!/bin/sh\necho native\n' > "$TEST_DIR/export/agy"
  run bash -c 'source ./agy-box-manager && export_agy_cli agy-box "$1/boxhome" "$1/export"' _ "$TEST_DIR"
  echo "$output"
  [ "$status" -eq 0 ]
  grep -F 'echo native' "$TEST_DIR/export/agy"
  refute_grep -F 'distrobox-export --bin' "$TEST_LOG"
}

@test "agy-box-manager: export is skipped when the box shares the host home and user binary exists" {
  mock_distrobox
  mkdir -p "$TEST_DIR/home/.local/bin"
  touch "$TEST_DIR/home/.local/bin/agy"
  chmod +x "$TEST_DIR/home/.local/bin/agy"
  run bash -c 'source ./agy-box-manager && export_agy_cli agy-box "$1/home" "$1/home/.local/bin"' _ "$TEST_DIR"
  [ "$status" -eq 0 ]
  refute_grep -F 'distrobox-export --bin' "$TEST_LOG"
}

@test "agy-box-manager: unexport removes only this box's agy shim" {
  mkdir -p "$TEST_DIR/export"
  printf '#!/bin/sh\n# distrobox_binary\n# name: agy-box-dev\n' > "$TEST_DIR/export/agy"
  run bash -c 'source ./agy-box-manager && unexport_agy_cli agy-box "$1/export"' _ "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ -e "$TEST_DIR/export/agy" ]

  run bash -c 'source ./agy-box-manager && unexport_agy_cli agy-box-dev "$1/export"' _ "$TEST_DIR"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_DIR/export/agy" ]
}

@test "agy-box-manager: no references to the removed /usr/bin/agy; update-toolchain is wired up" {
  refute_grep -F '/usr/bin/agy' agy-box-manager
  grep -F 'update-toolchain) check_deps "quiet"' agy-box-manager
  grep -F '"  update-toolchain ' agy-box-manager
}

@test "agy-box-manager: sourcing does not run the CLI" {
  run bash -c 'source ./agy-box-manager && echo sourced-ok'
  [ "$status" -eq 0 ]
  [ "$output" = "sourced-ok" ]
}

@test "agy-box-manager: detect_runtime honors DBX_CONTAINER_MANAGER when on PATH" {
  create_mock "custom-engine" 'exit 0'
  create_mock "podman" 'exit 0'
  create_mock "docker" 'exit 0'
  run bash -c 'source ./agy-box-manager && DBX_CONTAINER_MANAGER="custom-engine" detect_runtime'
  [ "$status" -eq 0 ]
  [ "$output" = "custom-engine" ]
}

@test "agy-box-manager: detect_runtime falls back to podman when DBX_CONTAINER_MANAGER is unset" {
  mkdir -p "$TEST_DIR/mock-podman"
  cat <<'EOF' > "$TEST_DIR/mock-podman/podman"
#!/bin/sh
exit 0
EOF
  chmod +x "$TEST_DIR/mock-podman/podman"
  local bash_bin
  bash_bin="$(command -v bash)"
  run env -i PATH="$TEST_DIR/mock-podman" "$bash_bin" -c 'source ./agy-box-manager && detect_runtime'
  [ "$status" -eq 0 ]
  [ "$output" = "podman" ]
}

@test "agy-box-manager: detect_runtime falls back to docker when podman not found" {
  mkdir -p "$TEST_DIR/mock-docker"
  cat <<'EOF' > "$TEST_DIR/mock-docker/docker"
#!/bin/sh
exit 0
EOF
  chmod +x "$TEST_DIR/mock-docker/docker"
  local bash_bin
  bash_bin="$(command -v bash)"
  run env -i PATH="$TEST_DIR/mock-docker" "$bash_bin" -c 'source ./agy-box-manager && detect_runtime'
  [ "$status" -eq 0 ]
  [ "$output" = "docker" ]
}

@test "Desktop and IceWM launchers use antigravity icon and dynamic SDK version lookup" {
  grep -F 'Icon=antigravity' rootfs/etc/skel/Desktop/Antigravity2.desktop
  refute_grep -F 'system-run' rootfs/etc/skel/Desktop/Antigravity2.desktop
  grep -F '"antigravity" antigravity' rootfs/etc/X11/icewm/menu
  grep -F '"antigravity" antigravity' rootfs/etc/X11/icewm/toolbar
  refute_grep -F '"system-run" antigravity' rootfs/etc/X11/icewm/menu
  refute_grep -F '"system-run" antigravity' rootfs/etc/X11/icewm/toolbar

  for f in rootfs/etc/skel/Desktop/AntigravitySDK.desktop rootfs/etc/X11/icewm/menu rootfs/etc/X11/icewm/toolbar; do
    grep -F "importlib.metadata.version('google-antigravity')" "$f"
    refute_grep -F 'v0.1.0' "$f"
  done
}


