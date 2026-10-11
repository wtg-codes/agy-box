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

@test "agy-box-manager: get_box_home resolves correct paths for default, dev, and named boxes" {
  run bash -c 'source ./agy-box-manager && get_box_home agy-box'
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.config/agy-box/home" ]

  run bash -c 'source ./agy-box-manager && get_box_home agy-box-dev'
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.config/agy-box/home-dev" ]

  run bash -c 'source ./agy-box-manager && get_box_home agy-box-test'
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.config/agy-box/homes/agy-box-test" ]

  run bash -c 'source ./agy-box-manager && get_box_home custom-box'
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.config/agy-box/homes/custom-box" ]
}

@test "agy-box-manager: cmd_install_official provisions isolated home for named box and passes flags" {
  local mock_log="$TEST_DIR/install_mock.log"
  cat <<EOF2 > "$MOCK_BIN/podman"
#!/bin/bash
echo "podman \$*" >> "$mock_log"
exit 0
EOF2
  chmod +x "$MOCK_BIN/podman"

  cat <<EOF2 > "$MOCK_BIN/distrobox"
#!/bin/bash
echo "distrobox \$*" >> "$mock_log"
exit 0
EOF2
  chmod +x "$MOCK_BIN/distrobox"

  run ./agy-box-manager install --name agy-box-v060 --image ghcr.io/wtg-codes/agy-box:v0.6.0 -y
  [ "$status" -eq 0 ]
  [ -d "$HOME/.config/agy-box/homes/agy-box-v060" ]
  run grep -F "podman pull ghcr.io/wtg-codes/agy-box:v0.6.0" "$mock_log"
  [ "$status" -eq 0 ]
  run grep -F "distrobox create -i ghcr.io/wtg-codes/agy-box:v0.6.0 -n agy-box-v060 --hostname agy-box-v060" "$mock_log"
  [ "$status" -eq 0 ]
  run grep -F -e "--home $HOME/.config/agy-box/homes/agy-box-v060" "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_enter enters specified named container and resolves prefix" {
  local mock_log="$TEST_DIR/enter_mock.log"
  create_mock "podman" 'if [ "$1" = "ps" ]; then echo "agy-box-staging"; fi; exit 0'
  create_mock "distrobox" "echo \"distrobox \$*\" >> '$mock_log'; exit 0"

  # Direct full name
  run ./agy-box-manager enter agy-box-staging
  [ "$status" -eq 0 ]
  run grep -F "distrobox enter agy-box-staging" "$mock_log"
  [ "$status" -eq 0 ]

  # Shorthand resolving to agy-box-staging
  run ./agy-box-manager enter staging
  [ "$status" -eq 0 ]
  run grep -F "distrobox enter agy-box-staging" "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_desktop forwards custom port and resolution" {
  local mock_log="$TEST_DIR/desktop_mock.log"
  create_mock "podman" 'if [ "$1" = "ps" ]; then echo "agy-box-test"; fi; exit 0'
  create_mock "distrobox" "echo \"distrobox \$*\" >> '$mock_log'; exit 0"

  run ./agy-box-manager desktop agy-box-test -p 6082 -r 2560x1440
  [ "$status" -eq 0 ]
  run grep -F "distrobox enter agy-box-test -- /usr/local/bin/agy-vdi -p 6082 -r 2560x1440" "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_clean removes named container and purges custom home while keeping primary intact" {
  local mock_log="$TEST_DIR/clean_mock.log"
  create_mock "podman" 'if [ "$1" = "ps" ]; then echo -e "agy-box\nagy-box-demo"; fi; exit 0'
  create_mock "distrobox" "echo \"distrobox \$*\" >> '$mock_log'; exit 0"

  # Create primary and custom home data
  mkdir -p "$HOME/.config/agy-box/home"
  echo "primary-data" > "$HOME/.config/agy-box/home/data.txt"
  mkdir -p "$HOME/.config/agy-box/homes/agy-box-demo"
  echo "demo-data" > "$HOME/.config/agy-box/homes/agy-box-demo/data.txt"

  run ./agy-box-manager clean agy-box-demo --purge
  [ "$status" -eq 0 ]
  run grep -F "distrobox rm --yes agy-box-demo" "$mock_log"
  [ "$status" -eq 0 ]

  # Custom home was purged, primary home is untouched
  [ ! -d "$HOME/.config/agy-box/homes/agy-box-demo" ]
  [ -f "$HOME/.config/agy-box/home/data.txt" ]
}

@test "agy-box-manager: export_agy_cli protects primary host agy shim when secondary box exports" {
  local export_dir="$TEST_DIR/export"
  mkdir -p "$export_dir"
  # Existing primary shim
  printf '#!/bin/sh\n# distrobox_binary\n# name: agy-box\n' > "$export_dir/agy"

  # Attempt export from secondary box
  run bash -c "source ./agy-box-manager && export_agy_cli agy-box-secondary '$TEST_DIR/boxhome' '$export_dir'"
  [ "$status" -eq 0 ]
  local cli_out="$output"
  # Shim is unchanged
  run grep -F "# name: agy-box" "$export_dir/agy"
  [ "$status" -eq 0 ]
  # Output warned about leaving primary shim untouched
  run grep -F "already exported from primary 'agy-box'" <<< "$cli_out"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: status lists multiple boxes and their homes" {
  create_mock "distrobox" '
    if [ "$1" = "list" ]; then
      echo "ID | NAME | STATUS | IMAGE"
      echo "111 | agy-box | Up 2 days | ghcr.io/wtg-codes/agy-box:latest"
      echo "222 | agy-box-v060 | Up 1 hour | ghcr.io/wtg-codes/agy-box:v0.6.0"
    fi
  '
  run ./agy-box-manager status
  [ "$status" -eq 0 ]
  run grep -F "agy-box" <<< "$output"
  [ "$status" -eq 0 ]
  run grep -F "agy-box-v060" <<< "$output"
  [ "$status" -eq 0 ]
  run grep -F "$HOME/.config/agy-box/homes/agy-box-v060" <<< "$output"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_install_official displays status and next steps card after install" {
  create_mock "podman" 'exit 0'
  create_mock "distrobox" '
    if [ "$1" = "list" ]; then
      echo "ID | NAME | STATUS | IMAGE"
      echo "111 | agy-box | Up 9 days | ghcr.io/wtg-codes/agy-box:latest"
      echo "222 | agy-box-staging | Up 10 seconds | ghcr.io/wtg-codes/agy-box:latest"
    fi
    exit 0
  '

  run ./agy-box-manager install -n agy-box-staging --no-enter
  [ "$status" -eq 0 ]
  local cli_out="$output"
  run grep -F "AGY Box Environments Status" <<< "$cli_out"
  [ "$status" -eq 0 ]
  run grep -F "Environment 'agy-box-staging' is running and ready!" <<< "$cli_out"
  [ "$status" -eq 0 ]
  run grep -F "just agy-enter agy-box-staging" <<< "$cli_out"
  [ "$status" -eq 0 ]
  run grep -F "just agy-desktop agy-box-staging -p 6081" <<< "$cli_out"
  [ "$status" -eq 0 ]
  run grep -F "just agy-clean agy-box-staging --purge" <<< "$cli_out"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_install_official --enter automatically invokes cmd_enter for target box" {
  local mock_log="$TEST_DIR/enter_after_install.log"
  create_mock "podman" '
    if [ "$1" = "ps" ]; then
      if [ -f "'$TEST_DIR'/created" ]; then
        echo "agy-box-autoenter"
      fi
    fi
    exit 0
  '
  cat <<EOF2 > "$MOCK_BIN/distrobox"
#!/bin/bash
echo "distrobox \$*" >> "$mock_log"
if [ "\$1" = "create" ]; then
  touch "$TEST_DIR/created"
fi
if [ "\$1" = "list" ]; then
  echo "ID | NAME | STATUS | IMAGE"
  echo "111 | agy-box-autoenter | Up 1 second | ghcr.io/wtg-codes/agy-box:latest"
fi
exit 0
EOF2
  chmod +x "$MOCK_BIN/distrobox"

  run ./agy-box-manager install -n agy-box-autoenter --enter
  [ "$status" -eq 0 ]
  run grep -F "distrobox enter agy-box-autoenter" "$mock_log"
  [ "$status" -eq 0 ]
}

