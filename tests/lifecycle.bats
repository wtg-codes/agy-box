#!/usr/bin/env bats
# Tests for agy-box-manager lifecycle commands:
#   - config loading & defaults initialization
#   - first-run setup wizard (non-interactive / --defaults)
#   - isolated keyring configuration
#   - backup & restore roundtrip
#   - check & update --check diagnostics

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  mkdir -p "$HOME"
  MOCK_BIN="$TEST_DIR/bin"
  mkdir -p "$MOCK_BIN"

  create_mock() {
    local cmd="$1"
    local code="$2"
    cat <<EOF2 > "$MOCK_BIN/$cmd"
#!/bin/bash
$code
EOF2
    chmod +x "$MOCK_BIN/$cmd"
  }

  export ORIGINAL_PATH="$PATH"
  export ORIGINAL_HOME="$HOME"
  export PATH="$MOCK_BIN:$PATH"
}

teardown() {
  export PATH="$ORIGINAL_PATH"
  export HOME="$ORIGINAL_HOME"
  rm -rf "$TEST_DIR"
}

@test "agy-box-manager: init_defaults creates config.env with valid default states" {
  run bash -c 'source ./agy-box-manager && init_defaults "silent"'
  [ "$status" -eq 0 ]
  [ -f "$HOME/.config/agy-box/config.env" ]

  run grep -E '^AGY_CONTAINER_MANAGER=' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]

  run grep -E '^AGY_KEYRING_MODE="host"' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]

  run grep -E '^AGY_AUTH_METHOD="oauth"' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]

  run grep -E '^AGY_DEFAULT_IDE="code"' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]

  run grep -E '^AGY_PROFILE_SEEDING="false"' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]

  run grep -E '^AGY_TELEMETRY="false"' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: init_defaults preserves existing config.env" {
  mkdir -p "$HOME/.config/agy-box"
  cat <<'EOF' > "$HOME/.config/agy-box/config.env"
AGY_CONTAINER_MANAGER="docker"
AGY_KEYRING_MODE="isolated"
AGY_DEFAULT_IDE="zed"
EOF
  run bash -c 'source ./agy-box-manager && init_defaults "silent"'
  [ "$status" -eq 0 ]

  run grep -E '^AGY_KEYRING_MODE="isolated"' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]
  run grep -E '^AGY_DEFAULT_IDE="zed"' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: load_config loads settings and configures DBX_CONTAINER_MANAGER" {
  mkdir -p "$HOME/.config/agy-box"
  create_mock "custom-podman" 'exit 0'
  cat <<'EOF' > "$HOME/.config/agy-box/config.env"
AGY_CONTAINER_MANAGER="custom-podman"
AGY_KEYRING_MODE="isolated"
AGY_DEFAULT_IDE="zed"
AGY_PROFILE_SEEDING="true"
EOF

  run bash -c 'source ./agy-box-manager && load_config && echo "$AGY_KEYRING_MODE|$AGY_DEFAULT_IDE|$AGY_PROFILE_SEEDING|$DBX_CONTAINER_MANAGER"'
  [ "$status" -eq 0 ]
  [ "$output" = "isolated|zed|true|custom-podman" ]
}

@test "agy-box-manager: wizard --defaults runs non-interactively and writes config.env" {
  run ./agy-box-manager wizard --defaults
  [ "$status" -eq 0 ]
  [ -f "$HOME/.config/agy-box/config.env" ]

  run grep -E '^AGY_KEYRING_MODE="host"' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: apply_keyring_configuration sets up EncryptedKeyring for isolated mode" {
  mkdir -p "$HOME/.config/agy-box"
  cat <<'EOF' > "$HOME/.config/agy-box/config.env"
AGY_KEYRING_MODE="isolated"
EOF

  run bash -c 'source ./agy-box-manager && load_config && apply_keyring_configuration'
  [ "$status" -eq 0 ]
  [ -f "$HOME/.config/agy-box/home/.config/python_keyring/keyringrc.cfg" ]
  [ -f "$HOME/.config/agy-box/home/.config/environment.d/keyring.conf" ]

  run grep -F "keyrings.alt.file.EncryptedKeyring" "$HOME/.config/agy-box/home/.config/python_keyring/keyringrc.cfg"
  [ "$status" -eq 0 ]
  run grep -F "keyrings.alt.file.EncryptedKeyring" "$HOME/.config/agy-box/home/.config/environment.d/keyring.conf"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: apply_keyring_configuration removes file keyring in host mode" {
  mkdir -p "$HOME/.config/agy-box/home/.config/python_keyring"
  mkdir -p "$HOME/.config/agy-box/home/.config/environment.d"
  touch "$HOME/.config/agy-box/home/.config/python_keyring/keyringrc.cfg"
  touch "$HOME/.config/agy-box/home/.config/environment.d/keyring.conf"

  cat <<'EOF' > "$HOME/.config/agy-box/config.env"
AGY_KEYRING_MODE="host"
EOF

  run bash -c 'source ./agy-box-manager && load_config && apply_keyring_configuration'
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.config/agy-box/home/.config/python_keyring/keyringrc.cfg" ]
  [ ! -f "$HOME/.config/agy-box/home/.config/environment.d/keyring.conf" ]
}

@test "agy-box-manager: backup and restore roundtrip preserves config and container state" {
  # Create sample configuration and state
  mkdir -p "$HOME/.config/agy-box/home/.gemini"
  mkdir -p "$HOME/.config/agy-box/home/.config/zed"
  cat <<'EOF' > "$HOME/.config/agy-box/config.env"
AGY_CONTAINER_MANAGER="podman"
AGY_KEYRING_MODE="isolated"
AGY_DEFAULT_IDE="zed"
EOF
  echo '{"saved": "transcript-data"}' > "$HOME/.config/agy-box/home/.gemini/test-transcript.json"
  echo '{"auto_install_extensions": {"antigravity": true}}' > "$HOME/.config/agy-box/home/.config/zed/settings.json"

  local backup_tar="$TEST_DIR/backup.tar.gz"
  run bash -c "source ./agy-box-manager && cmd_backup '$backup_tar'"
  [ "$status" -eq 0 ]
  [ -f "$backup_tar" ]

  # Now erase existing config and state
  rm -rf "$HOME/.config/agy-box"

  # Restore from archive
  run bash -c "source ./agy-box-manager && cmd_restore -y '$backup_tar'"
  [ "$status" -eq 0 ]

  # Verify recovered files
  [ -f "$HOME/.config/agy-box/config.env" ]
  [ -f "$HOME/.config/agy-box/home/.gemini/test-transcript.json" ]
  [ -f "$HOME/.config/agy-box/home/.config/zed/settings.json" ]
  run grep -F "isolated" "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]
  run grep -F "transcript-data" "$HOME/.config/agy-box/home/.gemini/test-transcript.json"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: check command executes cleanly and inspects environment" {
  create_mock "distrobox" 'echo "distrobox: 1.8.0"'
  create_mock "podman" 'if [ "$1" = "ps" ]; then exit 0; elif [ "$1" = "info" ]; then echo "rootless: true"; else echo "podman version 5.2.4"; fi'

  run ./agy-box-manager check
  [ "$status" -eq 0 ]
  local check_out="$output"
  run grep -F "Component & Status Inspector" <<< "$check_out"
  [ "$status" -eq 0 ]
  run grep -F "Host OS:" <<< "$check_out"
  [ "$status" -eq 0 ]
  run grep -F "Container Engine:" <<< "$check_out"
  [ "$status" -eq 0 ]
  run grep -F "Keyring Mode:" <<< "$check_out"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: update --check runs dry run without error" {
  create_mock "distrobox" 'echo "distrobox: 1.8.0"'
  create_mock "podman" 'if [ "$1" = "ps" ]; then echo "agy-box"; else echo "podman version 5.2.4"; fi'

  run ./agy-box-manager update --check
  [ "$status" -eq 0 ]
  run grep -F "Checking status and component versions" <<< "$output"
  [ "$status" -eq 0 ]
}
