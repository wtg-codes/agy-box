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
  chmod -R u+w "$TEST_DIR" 2>/dev/null || true
  rm -rf "$TEST_DIR" 2>/dev/null || true
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

@test "agy-box-manager: cmd_install_official provisions isolated sandbox for named box by default" {
  local mock_log="$TEST_DIR/install_mock.log"
  cat <<EOF2 > "$MOCK_BIN/podman"
#!/bin/bash
echo "podman \$*" >> "$mock_log"
exit 0
EOF2
  chmod +x "$MOCK_BIN/podman"

  create_mock "distrobox" 'exit 0'

  run ./agy-box-manager install --name agy-box-v060 --image ghcr.io/wtg-codes/agy-box:v0.6.0 -y
  [ "$status" -eq 0 ]
  [ -d "$HOME/.config/agy-box/homes/agy-box-v060" ]
  run grep -F "podman pull ghcr.io/wtg-codes/agy-box:v0.6.0" "$mock_log"
  [ "$status" -eq 0 ]
  run grep -F "podman run -d --name agy-box-v060 --hostname agy-box-v060 --label manager=agy-box-podman --label agy-box.mode=sandbox" "$mock_log"
  [ "$status" -eq 0 ]
  run grep -F -e "-v $HOME/.config/agy-box/homes/agy-box-v060:/home/agyuser:Z" "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_install_official --mode workstation provisions Distrobox environment" {
  local mock_log="$TEST_DIR/install_ws_mock.log"
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

  run ./agy-box-manager install --name agy-box-ws --image ghcr.io/wtg-codes/agy-box:latest --mode workstation -y
  [ "$status" -eq 0 ]
  run grep -F "distrobox create -i ghcr.io/wtg-codes/agy-box:latest -n agy-box-ws --hostname agy-box-ws" "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_enter enters specified named container in sandbox mode" {
  local mock_log="$TEST_DIR/enter_mock.log"
  create_mock "podman" "echo \"podman \$*\" >> '$mock_log'; if [ \"\$1\" = \"ps\" ]; then echo \"agy-box-staging\"; fi; exit 0"
  create_mock "distrobox" "echo \"distrobox \$*\" >> '$mock_log'; exit 0"

  # Direct full name
  run ./agy-box-manager enter agy-box-staging
  [ "$status" -eq 0 ]
  run grep -F "podman exec -it -u agyuser -w /home/agyuser agy-box-staging /bin/bash" "$mock_log"
  [ "$status" -eq 0 ]

  # Shorthand resolving to agy-box-staging
  run ./agy-box-manager enter staging
  [ "$status" -eq 0 ]
  run grep -F "podman exec -it -u agyuser -w /home/agyuser agy-box-staging /bin/bash" "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_desktop forwards custom port and resolution in sandbox mode" {
  local mock_log="$TEST_DIR/desktop_mock.log"
  create_mock "podman" "echo \"podman \$*\" >> '$mock_log'; if [ \"\$1\" = \"ps\" ]; then echo \"agy-box-test\"; fi; exit 0"
  create_mock "distrobox" "echo \"distrobox \$*\" >> '$mock_log'; exit 0"

  run ./agy-box-manager desktop agy-box-test -p 6082 -r 2560x1440
  [ "$status" -eq 0 ]
  run grep -F 'podman exec -d -u agyuser -w /home/agyuser agy-box-test sh -c exec /usr/local/bin/agy-vdi "$@" >/tmp/agy-vdi.log 2>&1 _ -p 6080 -r 2560x1440' "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_clean removes named container and purges custom home while keeping primary intact" {
  local mock_log="$TEST_DIR/clean_mock.log"
  create_mock "podman" "echo \"podman \$*\" >> '$mock_log'; if [ \"\$1\" = \"ps\" ]; then echo -e \"agy-box\nagy-box-demo\"; fi; exit 0"
  create_mock "distrobox" "echo \"distrobox \$*\" >> '$mock_log'; exit 0"

  # Create primary and custom home data
  mkdir -p "$HOME/.config/agy-box/home"
  echo "primary-data" > "$HOME/.config/agy-box/home/data.txt"
  mkdir -p "$HOME/.config/agy-box/homes/agy-box-demo"
  echo "demo-data" > "$HOME/.config/agy-box/homes/agy-box-demo/data.txt"

  run ./agy-box-manager clean agy-box-demo --purge
  [ "$status" -eq 0 ]
  run grep -F "podman rm -f agy-box-demo" "$mock_log"
  [ "$status" -eq 0 ]

  # Custom home was purged, primary home is untouched
  [ ! -d "$HOME/.config/agy-box/homes/agy-box-demo" ]
  [ -f "$HOME/.config/agy-box/home/data.txt" ]
}

@test "agy-box-manager: cmd_clean non-interactive without choice fails safely" {
  create_mock "podman" 'if [ "$1" = "ps" ]; then echo "agy-box-safetest"; fi; exit 0'
  create_mock "distrobox" 'exit 0'
  mkdir -p "$HOME/.config/agy-box/homes/agy-box-safetest"
  echo "test" > "$HOME/.config/agy-box/homes/agy-box-safetest/file"

  run bash -c "./agy-box-manager clean agy-box-safetest < /dev/null"
  [ "$status" -ne 0 ]
  run grep -F "Non-interactive clean requires an explicit choice" <<< "$output"
  [ "$status" -eq 0 ]
  [ -d "$HOME/.config/agy-box/homes/agy-box-safetest" ]
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
  run grep -F "just agy-clean agy-box-staging" <<< "$cli_out"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_install_official --enter automatically invokes cmd_enter for target box" {
  local mock_log="$TEST_DIR/enter_after_install.log"
  cat <<EOF2 > "$MOCK_BIN/podman"
#!/bin/bash
echo "podman \$*" >> "$mock_log"
if [ "\$1" = "run" ]; then
  touch "$TEST_DIR/created"
fi
if [ "\$1" = "ps" ] && [ -f "$TEST_DIR/created" ]; then
  echo "agy-box-autoenter"
fi
exit 0
EOF2
  chmod +x "$MOCK_BIN/podman"
  create_mock "distrobox" 'exit 0'

  run ./agy-box-manager install -n agy-box-autoenter --enter
  [ "$status" -eq 0 ]
  run grep -F "podman exec -it -u agyuser -w /home/agyuser agy-box-autoenter /bin/bash" "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: check_container_exists matches exact container names without substring collisions" {
  cat <<EOF2 > "$MOCK_BIN/podman"
#!/bin/bash
if [ "\$1" = "ps" ]; then
  echo "agy-box"
  echo "agy-box-test2"
fi
exit 0
EOF2
  chmod +x "$MOCK_BIN/podman"

  run bash -c "source ./agy-box-manager && check_container_exists 'test2'"
  [ "$status" -ne 0 ]

  run bash -c "source ./agy-box-manager && check_container_exists 'agy-box-test2'"
  [ "$status" -eq 0 ]

  run bash -c "source ./agy-box-manager && check_container_exists 'agy-box'"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: docker sandbox passes host PUID/PGID and entrypoint configures passwordless sudo" {
  local mock_log="$TEST_DIR/docker_sandbox.log"
  mkdir -p "$HOME/.config/agy-box"
  echo 'AGY_CONTAINER_MANAGER="docker"' > "$HOME/.config/agy-box/config.env"
  cat <<EOF2 > "$MOCK_BIN/docker"
#!/bin/bash
echo "docker \$*" >> "$mock_log"
exit 0
EOF2
  chmod +x "$MOCK_BIN/docker"

  run ./agy-box-manager install --name agy-box-spark --mode sandbox -y
  [ "$status" -eq 0 ]
  run grep -F -e "-e PUID=$(id -u) -e PGID=$(id -g)" "$mock_log"
  [ "$status" -eq 0 ]
  run grep -F "NOPASSWD:ALL" rootfs/usr/local/bin/entrypoint.sh
  [ "$status" -eq 0 ]
  run grep -F "NOPASSWD:ALL" Containerfile
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: autocomplete bash generates valid bash syntax and sources cleanly" {
  local comp_file="$TEST_DIR/agy-completion.bash"
  run ./agy-box-manager autocomplete bash
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$comp_file"

  run bash -n "$comp_file"
  [ "$status" -eq 0 ]

  run bash -c "source '$comp_file' && declare -F _agy_box_manager >/dev/null && declare -F _agy >/dev/null"
  [ "$status" -eq 0 ]

  run grep -F "mic-serve" "$comp_file"
  [ "$status" -eq 0 ]
  run grep -F "remote-control" "$comp_file"
  [ "$status" -eq 0 ]
  run grep -F -- "--effort" "$comp_file"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: install automatically falls back to sandbox mode when distrobox is absent on host" {
  local no_dbx_bin="$TEST_DIR/no_dbx_bin"
  mkdir -p "$no_dbx_bin"
  local util
  for util in bash sh mkdir rm ls cat grep awk sed sort head cut du id chmod cp mktemp uname tr printf dirname basename sleep clear; do
    if command -v "$util" >/dev/null 2>&1; then
      ln -sf "$(command -v "$util")" "$no_dbx_bin/$util"
    fi
  done

  local mock_log="$TEST_DIR/fallback_mock.log"
  cat <<EOF2 > "$no_dbx_bin/podman"
#!/bin/bash
echo "podman \$*" >> "$mock_log"
exit 0
EOF2
  chmod +x "$no_dbx_bin/podman"

  PATH="$no_dbx_bin" run ./agy-box-manager install -y --no-enter
  [ "$status" -eq 0 ]
  run grep -i "falling back to sandbox mode" <<< "$output"
  [ "$status" -eq 0 ]
  run grep -F "podman run -d --name agy-box --hostname agy-box --label manager=agy-box-podman --label agy-box.mode=sandbox" "$mock_log"
  [ "$status" -eq 0 ]

  # Explicit --mode workstation still fails when distrobox is absent
  PATH="$no_dbx_bin" run ./agy-box-manager install --name agy-box-explicit-ws --mode workstation -y --no-enter
  [ "$status" -ne 0 ]
}

@test "agy-box-manager: install --image localhost/... skips pull when local image exists" {
  local mock_log="$TEST_DIR/local_image_mock.log"
  cat <<EOF2 > "$MOCK_BIN/podman"
#!/bin/bash
echo "podman \$*" >> "$mock_log"
if [ "\$1" = "image" ] && [ "\$2" = "inspect" ]; then
  exit 0
fi
exit 0
EOF2
  chmod +x "$MOCK_BIN/podman"

  run ./agy-box-manager install --name agy-box-local --image localhost/agy-box:local-test --mode sandbox -y --no-enter
  [ "$status" -eq 0 ]
  run grep -F "Using local container image 'localhost/agy-box:local-test'..." <<< "$output"
  [ "$status" -eq 0 ]
  run grep -F "podman image inspect localhost/agy-box:local-test" "$mock_log"
  [ "$status" -eq 0 ]
  if grep -F "podman pull" "$mock_log"; then
    echo "unexpected podman pull for local image"
    return 1
  fi
  run grep -F "podman run -d --name agy-box-local" "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_enter strips -- and omits -it for non-TTY sandbox commands" {
  local mock_log="$TEST_DIR/enter_nontty_mock.log"
  create_mock "podman" "echo \"podman \$*\" >> '$mock_log'; if [ \"\$1\" = \"ps\" ]; then echo \"agy-box-cmdtest\"; fi; exit 0"

  run bash -c "./agy-box-manager enter agy-box-cmdtest -- agy --version < /dev/null"
  [ "$status" -eq 0 ]
  run grep -F "podman exec -u agyuser -w /home/agyuser agy-box-cmdtest agy --version" "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_clean accepts -y/--yes and rejects unknown flags" {
  local mock_log="$TEST_DIR/clean_y_mock.log"
  create_mock "podman" "echo \"podman \$*\" >> '$mock_log'; if [ \"\$1\" = \"ps\" ]; then echo \"agy-box-demo\"; fi; exit 0"
  create_mock "distrobox" "echo \"distrobox \$*\" >> '$mock_log'; exit 0"

  mkdir -p "$HOME/.config/agy-box/homes/agy-box-demo"
  echo "demo-data" > "$HOME/.config/agy-box/homes/agy-box-demo/data.txt"

  # Accepts -y alongside --purge without treating -y as container name
  run ./agy-box-manager clean agy-box-demo --purge -y
  [ "$status" -eq 0 ]
  run grep -F "podman rm -f agy-box-demo" "$mock_log"
  [ "$status" -eq 0 ]
  [ ! -d "$HOME/.config/agy-box/homes/agy-box-demo" ]

  # Rejects unknown flags
  run ./agy-box-manager clean agy-box-demo --unknown-flag
  [ "$status" -ne 0 ]
  run grep -F "Unknown option: --unknown-flag" <<< "$output"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: VERSION is 0.7.2" {
  run bash -c 'source ./agy-box-manager && echo "$VERSION"'
  [ "$status" -eq 0 ]
  [ "$output" = "0.7.2" ]

  run ./agy-box-manager version
  [ "$status" -eq 0 ]
  [[ "$output" == *"agy-box-manager version 0.7.2"* ]]
}

@test "agy-box-manager: script size is strictly under 120000 bytes and avoids E2BIG" {
  local size
  size=$(wc -c < ./agy-box-manager)
  [ "$size" -lt 120000 ]

  run /usr/bin/bash -c "$(cat ./agy-box-manager)" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"agy-box-manager version 0.7.2"* ]]

  run bash <(cat ./agy-box-manager) --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"agy-box-manager version 0.7.2"* ]]
}

@test "agy-box-manager: run_step surfaces failure logs without swallowing gum spin" {
  create_mock "gum" '
if [ "$1" = "spin" ]; then
  echo "mock-gum-spinner-rendered"
  while [ "$1" != "--" ]; do shift; done
  shift
  "$@"
else
  "$@"
fi
'

  run bash -c 'source ./agy-box-manager && AGY_NONINTERACTIVE=1 run_step "Failing task" bash -c "echo simulated failure; exit 2"'
  [ "$status" -eq 2 ]
  [[ "$output" == *"simulated failure"* ]]

  run bash -c '
source ./agy-box-manager
run_step_with_mock_gum() {
  local title=$1
  shift
  local rc=0
  local log_file
  log_file=$(mktemp)
  gum spin --spinner dot --title "$title" -- bash -c '\''log="$1"; shift; "$@" >"$log" 2>&1'\'' _ "$log_file" "$@" || rc=$?
  if [ "$rc" -ne 0 ]; then cat "$log_file"; fi
  rm -f "$log_file"
  return "$rc"
}
run_step_with_mock_gum "Failing task with spinner" bash -c "echo surfaced child error; exit 3"
'
  [ "$status" -eq 3 ]
  [[ "$output" == *"mock-gum-spinner-rendered"* ]]
  [[ "$output" == *"surfaced child error"* ]]
}

@test "agy-box-manager: cmd_install_official emits visible [1/4] through [4/4] progress steps in sandbox mode" {
  local mock_log="$TEST_DIR/install_steps_mock.log"
  cat <<EOF2 > "$MOCK_BIN/podman"
#!/bin/bash
echo "podman \$*" >> "$mock_log"
exit 0
EOF2
  chmod +x "$MOCK_BIN/podman"
  create_mock "distrobox" 'exit 0'

  run ./agy-box-manager install --name agy-box-live --image ghcr.io/wtg-codes/agy-box:latest --mode sandbox -y --no-enter
  [ "$status" -eq 0 ]
  [[ "$output" == *"==> [1/4] Pulling container image"* ]]
  [[ "$output" == *"✓ [1/4] Pulling container image"* ]]
  [[ "$output" == *"==> [2/4] Creating sandbox environment"* ]]
  [[ "$output" == *"✓ [2/4] Creating sandbox environment"* ]]
  [[ "$output" == *"==> [3/4] Verifying sandbox container"* ]]
  [[ "$output" == *"✓ [3/4] Verifying sandbox container"* ]]
  [[ "$output" == *"==> [4/4] Configuring host shell integration"* ]]
  [[ "$output" == *"✓ Host shell integration ready"* ]]
}

@test "agy-box-manager: cmd_install_official emits visible [1/4] through [4/4] progress steps in workstation mode" {
  local mock_log="$TEST_DIR/install_ws_steps_mock.log"
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

  run ./agy-box-manager install --name agy-box-ws-live --image ghcr.io/wtg-codes/agy-box:latest --mode workstation -y --no-enter
  [ "$status" -eq 0 ]
  [[ "$output" == *"==> [1/4] Pulling container image"* ]]
  [[ "$output" == *"✓ [1/4] Pulling container image"* ]]
  [[ "$output" == *"==> [2/4] Creating workstation environment"* ]]
  [[ "$output" == *"✓ [2/4] Creating workstation environment"* ]]
  [[ "$output" == *"==> [3/4] Initializing 'agy-box-ws-live' container & CLI integration"* ]]
  [[ "$output" == *"✓ [3/4] Initializing 'agy-box-ws-live' container & CLI integration"* ]]
  [[ "$output" == *"==> [4/4] Configuring host shell integration"* ]]
  [[ "$output" == *"✓ Host shell integration ready"* ]]
  run grep -F "distrobox enter agy-box-ws-live -- true" "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_desktop supports --stop to terminate VDI session" {
  local mock_log="$TEST_DIR/desktop_stop_mock.log"
  create_mock "podman" "echo \"podman \$*\" >> '$mock_log'; if [ \"\$1\" = \"ps\" ]; then echo \"agy-box-test\"; elif [ \"\$1\" = \"exec\" ] && [[ \"\$*\" == *\"pgrep\"* ]]; then exit 1; fi; exit 0"
  create_mock "distrobox" "echo \"distrobox \$*\" >> '$mock_log'; exit 0"

  run ./agy-box-manager desktop agy-box-test --stop
  [ "$status" -eq 0 ]
  [[ "$output" == *"VDI session for 'agy-box-test' stopped cleanly"* ]]
  run grep -F 'pkill -TERM -f "[a]gy-vdi|[w]ebsockify|[x]11vnc|[i]cewm-session|[X]vfb"' "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_desktop supports --detach to launch in background" {
  local mock_log="$TEST_DIR/desktop_detach_mock.log"
  create_mock "podman" "echo \"podman \$*\" >> '$mock_log'; if [ \"\$1\" = \"ps\" ]; then echo \"agy-box-test\"; fi; exit 0"
  create_mock "distrobox" "echo \"distrobox \$*\" >> '$mock_log'; exit 0"

  run ./agy-box-manager desktop agy-box-test --detach
  [ "$status" -eq 0 ]
  [[ "$output" == *"VDI Desktop is accessible at"* ]]
  run grep -F 'podman exec -d -u agyuser -w /home/agyuser agy-box-test sh -c exec /usr/local/bin/agy-vdi "$@" >/tmp/agy-vdi.log 2>&1 _ -p 6080' "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: generate_box_name produces two-word kebab name and avoids collisions" {
  source ./agy-box-manager
  local name1 name2
  name1=$(generate_box_name "agy-box")
  [[ "$name1" =~ ^agy-box-[a-z]+-[a-z]+$ ]]

  mkdir -p "$HOME/.config/agy-box/homes/$name1"
  name2=$(generate_box_name "agy-box")
  [[ "$name2" =~ ^agy-box-[a-z]+-[a-z]+$ ]]
  [ "$name1" != "$name2" ]
}

@test "agy-box-manager: calculate_box_port_offset allocates lowest unused offset >= 1" {
  source ./agy-box-manager
  run calculate_box_port_offset "agy-box"
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  run calculate_box_port_offset "agy-box-alpha-beta"
  [ "$status" -eq 0 ]
  [ "$output" -eq 1 ]

  # Simulate existing container using port 6081
  local mock_code='
if [ "$1" = "ps" ] && [[ "$*" == *"{{.Ports}}"* ]]; then
  echo "6081->6080/tcp"
fi
exit 0
'
  create_mock "podman" "$mock_code"
  create_mock "docker" "$mock_code"
  run calculate_box_port_offset "agy-box-gamma-delta"
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

@test "agy-box-manager: ensure_distrobox_ready initializes stopped and recovers half-initialized containers" {
  local mock_log="$TEST_DIR/ready_mock.log"
  create_mock "podman" '
echo "podman $*" >> "'"$mock_log"'"
if [ "$1" = "inspect" ] && [[ "$*" == *"State.Running"* ]]; then
  echo "false"
fi
exit 0
'
  create_mock "distrobox" '
echo "distrobox $*" >> "'"$mock_log"'"
exit 0
'

  run bash -c 'source ./agy-box-manager && ensure_distrobox_ready "test-box"'
  [ "$status" -eq 0 ]
  run grep -F "distrobox enter test-box -- true" "$mock_log"
  [ "$status" -eq 0 ]

  rm -f "$mock_log"
  local pass_file="$TEST_DIR/passwd_checked"
  create_mock "podman" '
echo "podman $*" >> "'"$mock_log"'"
if [ "$1" = "inspect" ] && [[ "$*" == *"State.Running"* ]]; then
  echo "true"
elif [ "$1" = "exec" ] && [[ "$*" == *"getent passwd"* ]]; then
  if [ ! -f "'"$pass_file"'" ]; then
    touch "'"$pass_file"'"
    exit 1
  else
    exit 0
  fi
fi
exit 0
'
  run bash -c 'source ./agy-box-manager && ensure_distrobox_ready "test-box"'
  [ "$status" -eq 0 ]
  run grep -F "podman stop test-box" "$mock_log"
  [ "$status" -eq 0 ]
  run grep -F "distrobox enter test-box -- true" "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_desktop reports error and exits 1 when VDI fails to start" {
  local mock_log="$TEST_DIR/desktop_fail_mock.log"
  create_mock "podman" '
echo "podman $*" >> "'"$mock_log"'"
if [ "$1" = "ps" ]; then
  echo "agy-box-test"
elif [ "$1" = "exec" ] && [[ "$*" == *"pgrep"* ]]; then
  exit 1
elif [ "$1" = "exec" ] && [[ "$*" == *"cat /tmp/agy-vdi.log"* ]]; then
  echo "Error: unable to find user wtg: no matching entries in passwd file" >&2
fi
exit 0
'
  create_mock "distrobox" 'exit 0'

  run env AGY_VDI_TIMEOUT=1 ./agy-box-manager desktop agy-box-test --detach
  [ "$status" -ne 0 ]
  [[ "$output" == *"❌ Error: VDI failed to start:"* ]]
}

@test "agy-box-manager: workstation cmd_desktop passes DBUS_SESSION_BUS_ADDRESS and XDG_RUNTIME_DIR when AGY_KEYRING_MODE=host" {
  local mock_log="$TEST_DIR/desktop_ws_host.log"
  mkdir -p "$HOME/.config/agy-box"
  cat <<'EOF' > "$HOME/.config/agy-box/config.env"
AGY_CONTAINER_MANAGER="podman"
AGY_KEYRING_MODE="host"
EOF

  create_mock "podman" '
echo "podman $*" >> "'"$mock_log"'"
if [ "$1" = "ps" ]; then
  echo "agy-box-ws"
elif [ "$1" = "inspect" ] && [[ "$*" == *"manager"* ]]; then
  echo "distrobox"
elif [ "$1" = "inspect" ] && [[ "$*" == *"State.Running"* ]]; then
  echo "true"
elif [ "$1" = "exec" ] && [[ "$*" == *"pgrep"* ]]; then
  if [ -f "'"$TEST_DIR"'/vdi_started" ]; then exit 0; else exit 1; fi
elif [ "$1" = "exec" ] && [ "$2" = "-d" ]; then
  touch "'"$TEST_DIR"'/vdi_started"
fi
exit 0
'
  create_mock "distrobox" 'exit 0'

  run env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" \
          XDG_RUNTIME_DIR="/run/user/1000" \
          GNOME_KEYRING_CONTROL="/run/user/1000/keyring" \
          ./agy-box-manager desktop agy-box-ws -p 6092 --detach
  [ "$status" -eq 0 ]

  local exec_line
  exec_line=$(grep -F "podman exec -d" "$mock_log")
  [[ "$exec_line" == *"-e AGY_KEYRING_MODE=host"* ]]
  [[ "$exec_line" == *"-e XDG_RUNTIME_DIR=/run/user/1000"* ]]
  [[ "$exec_line" == *"-e DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"* ]]
  [[ "$exec_line" == *"-e GNOME_KEYRING_CONTROL=/run/user/1000/keyring"* ]]
  [[ "$exec_line" == *"-p 6092"* ]]
}

@test "agy-box-manager: workstation cmd_desktop omits DBUS_SESSION_BUS_ADDRESS when AGY_KEYRING_MODE=isolated" {
  local mock_log="$TEST_DIR/desktop_ws_isolated.log"
  mkdir -p "$HOME/.config/agy-box"
  cat <<'EOF' > "$HOME/.config/agy-box/config.env"
AGY_CONTAINER_MANAGER="podman"
AGY_KEYRING_MODE="isolated"
EOF

  create_mock "podman" '
echo "podman $*" >> "'"$mock_log"'"
if [ "$1" = "ps" ]; then
  echo "agy-box-ws"
elif [ "$1" = "inspect" ] && [[ "$*" == *"manager"* ]]; then
  echo "distrobox"
elif [ "$1" = "inspect" ] && [[ "$*" == *"State.Running"* ]]; then
  echo "true"
elif [ "$1" = "exec" ] && [[ "$*" == *"pgrep"* ]]; then
  if [ -f "'"$TEST_DIR"'/vdi_started_iso" ]; then exit 0; else exit 1; fi
elif [ "$1" = "exec" ] && [ "$2" = "-d" ]; then
  touch "'"$TEST_DIR"'/vdi_started_iso"
fi
exit 0
'
  create_mock "distrobox" 'exit 0'

  run env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" \
          XDG_RUNTIME_DIR="/run/user/1000" \
          GNOME_KEYRING_CONTROL="/run/user/1000/keyring" \
          ./agy-box-manager desktop agy-box-ws --detach
  [ "$status" -eq 0 ]

  local exec_line
  exec_line=$(grep -F "podman exec -d" "$mock_log")
  [[ "$exec_line" == *"-e AGY_KEYRING_MODE=isolated"* ]]
  [[ "$exec_line" != *"DBUS_SESSION_BUS_ADDRESS"* ]]
  [[ "$exec_line" != *"XDG_RUNTIME_DIR"* ]]
  [[ "$exec_line" != *"GNOME_KEYRING_CONTROL"* ]]
}

@test "agy-box-manager: apply_keyring_configuration falls back to podman unshare when .config is not writable" {
  local mock_log="$TEST_DIR/keyring_unshare.log"
  local iso_home="$HOME/.config/agy-box/home"
  mkdir -p "$iso_home/.config"
  chmod 0500 "$iso_home/.config"

  create_mock "podman" '
echo "podman $*" >> "'"$mock_log"'"
if [ "$1" = "unshare" ]; then
  chmod -R u+rwx "'"$iso_home"'" 2>/dev/null || true
  shift
  "$@"
  exit $?
fi
exit 0
'

  run env AGY_KEYRING_MODE="isolated" bash -c 'source ./agy-box-manager && apply_keyring_configuration "'"$iso_home"'"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Permission denied"* ]]
  run grep -F "podman unshare bash -c" "$mock_log"
  [ "$status" -eq 0 ]
  [ -f "$iso_home/.config/python_keyring/keyringrc.cfg" ]
  [ -f "$iso_home/.config/environment.d/keyring.conf" ]

  chmod 0500 "$iso_home/.config"
  run env AGY_KEYRING_MODE="host" bash -c 'source ./agy-box-manager && apply_keyring_configuration "'"$iso_home"'"'
  [ "$status" -eq 0 ]
  [[ "$output" != *"Permission denied"* ]]
  [ ! -e "$iso_home/.config/python_keyring/keyringrc.cfg" ]
  [ ! -e "$iso_home/.config/environment.d/keyring.conf" ]
}

@test "agy-box-manager: cmd_install_official and cmd_desktop heal subuid ownership after distrobox enter" {
  local mock_log="$TEST_DIR/ws_subuid_order.log"
  local ws_home="$HOME/.config/agy-box/homes/agy-box-ws-perm"
  mkdir -p "$HOME/.config/agy-box"
  cat <<'EOF' > "$HOME/.config/agy-box/config.env"
AGY_CONTAINER_MANAGER="podman"
AGY_KEYRING_MODE="isolated"
EOF

  create_mock "podman" '
echo "podman $*" >> "'"$mock_log"'"
if [ "$1" = "unshare" ] && [ "$2" = "chown" ]; then
  chmod -R u+rwx "'"$ws_home"'" 2>/dev/null || true
  exit 0
elif [ "$1" = "unshare" ]; then
  chmod -R u+rwx "'"$ws_home"'" 2>/dev/null || true
  shift
  "$@"
  exit $?
elif [ "$1" = "ps" ]; then
  if [ -f "'"$TEST_DIR"'/ws_created" ]; then echo "agy-box-ws-perm"; fi
elif [ "$1" = "inspect" ] && [[ "$*" == *"manager"* ]]; then
  echo "distrobox"
elif [ "$1" = "inspect" ] && [[ "$*" == *"State.Running"* ]]; then
  echo "true"
elif [ "$1" = "exec" ] && [[ "$*" == *"pgrep"* ]]; then
  if [ -f "'"$TEST_DIR"'/ws_vdi_started" ]; then exit 0; else exit 1; fi
elif [ "$1" = "exec" ] && [ "$2" = "-d" ]; then
  touch "'"$TEST_DIR"'/ws_vdi_started"
fi
exit 0
'
  create_mock "distrobox" '
echo "distrobox $*" >> "'"$mock_log"'"
if [ "$1" = "create" ]; then
  touch "'"$TEST_DIR"'/ws_created"
elif [ "$1" = "enter" ] && [[ "$*" == *"-- true"* ]]; then
  mkdir -p "'"$ws_home"'/.config"
  chmod 0500 "'"$ws_home"'/.config"
fi
exit 0
'

  run ./agy-box-manager install agy-box-ws-perm --mode workstation --yes --no-enter
  [ "$status" -eq 0 ]
  [[ "$output" != *"Permission denied"* ]]
  [ -f "$ws_home/.config/python_keyring/keyringrc.cfg" ]

  local enter_line chown_last_line
  enter_line=$(grep -nF "distrobox enter agy-box-ws-perm -- true" "$mock_log" | head -n1 | cut -d: -f1)
  chown_last_line=$(grep -nF "podman unshare chown -R 0:0 $ws_home" "$mock_log" | tail -n1 | cut -d: -f1)
  [ -n "$enter_line" ]
  [ -n "$chown_last_line" ]
  [ "$chown_last_line" -gt "$enter_line" ]

  chmod 0500 "$ws_home/.config"
  run ./agy-box-manager desktop agy-box-ws-perm --detach
  [ "$status" -eq 0 ]
  [[ "$output" != *"Permission denied"* ]]
}

