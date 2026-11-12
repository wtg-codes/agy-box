#!/usr/bin/env bats
# Tests for agy-box-manager v0.8.0 unified multi-box fleet & structured logging:
#   - config loading, defaults (AGY_DEFAULT_MODE="sandbox"), and legacy migration
#   - unified multi-box fleet (stable & dev channels, 2-word slugs, .agy-box-meta, labels)
#   - zero host dotfile/RC or ~/.local/bin/agy mutations
#   - resolve_target_box, permanent box names (rename rejection), clean --all
#   - structured tool logging, 5 MB rotation, failure hints, and 'logs' subcommand

setup() {
  TEST_DIR="$(mktemp -d)"
  export HOME="$TEST_DIR/home"
  export AGY_LOG_DIR="$HOME/.config/agy-box/logs"
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

  # Mock ss by default so host open sockets (e.g. 6080) never affect deterministic port offset tests
  create_mock "ss" 'exit 0'

  export ORIGINAL_PATH="$PATH"
  export ORIGINAL_HOME="$HOME"
  export PATH="$MOCK_BIN:$PATH"
}

teardown() {
  export PATH="$ORIGINAL_PATH"
  export HOME="$ORIGINAL_HOME"
  unset AGY_LOG_DIR
  chmod -R u+w "$TEST_DIR" 2>/dev/null || true
  rm -rf "$TEST_DIR" 2>/dev/null || true
}

@test "agy-box-manager: VERSION is 0.8.0 and script size is strictly under 118000 bytes" {
  run bash -c 'source ./agy-box-manager && echo "$VERSION"'
  [ "$status" -eq 0 ]
  [ "$output" = "0.8.0" ]

  local size
  size=$(wc -c < ./agy-box-manager)
  [ "$size" -lt 118000 ]

  run bash -c "$(cat ./agy-box-manager)" --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"agy-box-manager version 0.8.0"* ]]

  run bash <(cat ./agy-box-manager) --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"agy-box-manager version 0.8.0"* ]]
}

@test "agy-box-manager: init_defaults creates config.env with AGY_DEFAULT_MODE=sandbox and preserves existing config" {
  run bash -c 'source ./agy-box-manager && init_defaults "silent"'
  [ "$status" -eq 0 ]
  [ -f "$HOME/.config/agy-box/config.env" ]

  run grep -E '^AGY_CONTAINER_MANAGER=' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]
  run grep -E '^AGY_DEFAULT_MODE="sandbox"' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]
  run grep -E '^AGY_KEYRING_MODE="host"' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]
  run grep -E '^AGY_DEFAULT_IDE="code"' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]
  run grep -E '^AGY_PROFILE_SEEDING="false"' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]
  run grep -E '^AGY_TELEMETRY="false"' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]

  cat <<'EOF' > "$HOME/.config/agy-box/config.env"
AGY_CONTAINER_MANAGER="docker"
AGY_DEFAULT_MODE="workstation"
AGY_KEYRING_MODE="isolated"
AGY_DEFAULT_IDE="zed"
EOF
  run bash -c 'source ./agy-box-manager && init_defaults "silent"'
  [ "$status" -eq 0 ]
  run grep -E '^AGY_DEFAULT_MODE="workstation"' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]
  run grep -E '^AGY_DEFAULT_IDE="zed"' "$HOME/.config/agy-box/config.env"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: load_config migrates legacy AGY_PRIMARY_ENGINE when AGY_DEFAULT_MODE is absent" {
  mkdir -p "$HOME/.config/agy-box"
  create_mock "custom-podman" 'exit 0'
  cat <<'EOF' > "$HOME/.config/agy-box/config.env"
AGY_CONTAINER_MANAGER="custom-podman"
AGY_PRIMARY_ENGINE="distrobox"
AGY_KEYRING_MODE="isolated"
AGY_DEFAULT_IDE="zed"
AGY_PROFILE_SEEDING="true"
EOF

  run bash -c 'source ./agy-box-manager && load_config && echo "$AGY_DEFAULT_MODE|$AGY_KEYRING_MODE|$AGY_DEFAULT_IDE|$AGY_PROFILE_SEEDING|$DBX_CONTAINER_MANAGER"'
  [ "$status" -eq 0 ]
  [ "$output" = "workstation|isolated|zed|true|custom-podman" ]

  cat <<'EOF' > "$HOME/.config/agy-box/config.env"
AGY_PRIMARY_ENGINE="podman"
EOF
  run bash -c 'source ./agy-box-manager && load_config && echo "$AGY_DEFAULT_MODE"'
  [ "$status" -eq 0 ]
  [ "$output" = "sandbox" ]
}

@test "agy-box-manager: doctor, check alias, doctor <box>, and update --check execute cleanly" {
  local mock_log="$TEST_DIR/doctor_mock.log"
  create_mock "distrobox" 'echo "distrobox: 1.8.0"'
  create_mock "podman" '
echo "podman $*" >> "'"$mock_log"'"
if [ "$1" = "ps" ]; then
  echo "agy-box-golden-spark"
elif [ "$1" = "info" ]; then
  echo "rootless: true"
elif [ "$1" = "exec" ]; then
  echo "agy-doctor container health ok"
else
  echo "podman version 5.2.4"
fi
'

  run ./agy-box-manager check
  [ "$status" -eq 0 ]
  [[ "$output" == *"AGY Box Doctor Diagnostics"* ]]
  [[ "$output" == *"Container Engine:"* ]]
  [[ "$output" == *"Default Mode:              sandbox"* ]]
  [[ "$output" == *"agy-box-golden-spark"* ]]

  run ./agy-box-manager doctor golden-spark
  [ "$status" -eq 0 ]
  [[ "$output" == *"agy-doctor container health ok"* ]]
  run grep -F "podman exec -u agyuser -w /home/agyuser agy-box-golden-spark /usr/local/bin/agy-doctor" "$mock_log"
  [ "$status" -eq 0 ]

  run ./agy-box-manager update --check
  [ "$status" -eq 0 ]
  [[ "$output" == *"Checking status and component versions"* ]]
}

@test "agy-box-manager: get_box_home uses uniform homes/<box> and keeps legacy home fallback only for pre-existing agy-box" {
  run bash -c 'source ./agy-box-manager && get_box_home agy-box-golden-spark'
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.config/agy-box/homes/agy-box-golden-spark" ]

  run bash -c 'source ./agy-box-manager && get_box_home agy-box-dev-lunar-comet'
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.config/agy-box/homes/agy-box-dev-lunar-comet" ]

  run bash -c 'source ./agy-box-manager && get_box_home agy-box'
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.config/agy-box/homes/agy-box" ]

  mkdir -p "$HOME/.config/agy-box/home"
  run bash -c 'source ./agy-box-manager && get_box_home agy-box'
  [ "$status" -eq 0 ]
  [ "$output" = "$HOME/.config/agy-box/home" ]
}

@test "agy-box-manager: default install (without --new or --name) creates distinct two-word stable sandbox boxes" {
  local mock_log="$TEST_DIR/fleet_install.log"
  local state_file="$TEST_DIR/containers.txt"
  touch "$state_file"

  cat <<EOF2 > "$MOCK_BIN/podman"
#!/bin/bash
echo "podman \$*" >> "$mock_log"
if [ "\$1" = "run" ]; then
  for ((i=1; i<=\$#; i++)); do
    if [ "\${!i}" = "--name" ]; then
      j=\$((i+1))
      echo "\${!j}" >> "$state_file"
    fi
  done
elif [ "\$1" = "ps" ]; then
  cat "$state_file"
fi
exit 0
EOF2
  chmod +x "$MOCK_BIN/podman"

  run ./agy-box-manager install -y --no-enter
  [ "$status" -eq 0 ]

  run ./agy-box-manager install -y --no-enter
  [ "$status" -eq 0 ]

  local count
  count=$(wc -l < "$state_file")
  [ "$count" -eq 2 ]

  local box1 box2
  box1=$(sed -n '1p' "$state_file")
  box2=$(sed -n '2p' "$state_file")
  [[ "$box1" =~ ^agy-box-[a-z]+-[a-z]+$ ]]
  [[ "$box2" =~ ^agy-box-[a-z]+-[a-z]+$ ]]
  [ "$box1" != "$box2" ]
  [ ! -d "$HOME/.config/agy-box/home" ]
  [ -d "$HOME/.config/agy-box/homes/$box1" ]
  [ -d "$HOME/.config/agy-box/homes/$box2" ]
  [ -f "$HOME/.config/agy-box/homes/$box1/.agy-box-meta" ]

  run grep -F 'AGY_BOX_CHANNEL="stable"' "$HOME/.config/agy-box/homes/$box1/.agy-box-meta"
  [ "$status" -eq 0 ]
  run grep -F 'AGY_BOX_MODE="sandbox"' "$HOME/.config/agy-box/homes/$box1/.agy-box-meta"
  [ "$status" -eq 0 ]
  run grep -F -- "--label agy-box.managed=true --label agy-box.channel=stable --label agy-box.branch=release --label agy-box.mode=sandbox -p 6080:6080" "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: dev builds stable channel from main branch and dev channel from feature branch" {
  local repo_dir="$TEST_DIR/repo"
  mkdir -p "$repo_dir"
  printf 'FROM scratch\n' > "$repo_dir/Containerfile"

  local mock_log="$TEST_DIR/dev_build.log"
  local state_file="$TEST_DIR/dev_containers.txt"
  touch "$state_file"

  cat <<EOF2 > "$MOCK_BIN/podman"
#!/bin/bash
echo "podman \$*" >> "$mock_log"
if [ "\$1" = "image" ] && [ "\$2" = "inspect" ]; then
  exit 0
elif [ "\$1" = "run" ]; then
  for ((i=1; i<=\$#; i++)); do
    if [ "\${!i}" = "--name" ]; then
      j=\$((i+1))
      echo "\${!j}" >> "$state_file"
    fi
  done
elif [ "\$1" = "ps" ]; then
  cat "$state_file"
fi
exit 0
EOF2
  chmod +x "$MOCK_BIN/podman"

  # Mock git returning 'main' first
  create_mock "git" 'if [ "$1" = "rev-parse" ]; then echo "main"; exit 0; fi; exit 1'
  local mgr_abs
  mgr_abs="$(pwd)/agy-box-manager"

  run bash -c "cd '$repo_dir' && '$mgr_abs' dev -y --no-enter"
  [ "$status" -eq 0 ]
  local stable_box
  stable_box=$(sed -n '1p' "$state_file")
  [[ "$stable_box" =~ ^agy-box-[a-z]+-[a-z]+$ ]]
  [[ "$stable_box" != agy-box-dev-* ]]
  run grep -F "podman build -t localhost/agy-box:stable -f Containerfile ." "$mock_log"
  [ "$status" -eq 0 ]
  run grep -F 'AGY_BOX_CHANNEL="stable"' "$HOME/.config/agy-box/homes/$stable_box/.agy-box-meta"
  [ "$status" -eq 0 ]
  run grep -F 'AGY_BOX_BRANCH="main"' "$HOME/.config/agy-box/homes/$stable_box/.agy-box-meta"
  [ "$status" -eq 0 ]

  # Mock git returning 'feat/v080' next
  create_mock "git" 'if [ "$1" = "rev-parse" ]; then echo "feat/v080"; exit 0; fi; exit 1'
  run bash -c "cd '$repo_dir' && '$mgr_abs' dev -y --no-enter"
  [ "$status" -eq 0 ]
  local dev_box
  dev_box=$(sed -n '2p' "$state_file")
  [[ "$dev_box" =~ ^agy-box-dev-[a-z]+-[a-z]+$ ]]
  run grep -F "podman build -t localhost/agy-box:dev -f Containerfile ." "$mock_log"
  [ "$status" -eq 0 ]
  run grep -F 'AGY_BOX_CHANNEL="dev"' "$HOME/.config/agy-box/homes/$dev_box/.agy-box-meta"
  [ "$status" -eq 0 ]
  run grep -F 'AGY_BOX_BRANCH="feat/v080"' "$HOME/.config/agy-box/homes/$dev_box/.agy-box-meta"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: boxes cannot be renamed via rename subcommand or --rename flag" {
  create_mock "podman" 'exit 0'

  run ./agy-box-manager rename old-box new-box
  [ "$status" -ne 0 ]
  [[ "$output" == *"Boxes cannot be renamed"* ]]

  run ./agy-box-manager install --rename new-box
  [ "$status" -ne 0 ]
  [[ "$output" == *"Boxes cannot be renamed"* ]]

  run ./agy-box-manager update --rename new-box
  [ "$status" -ne 0 ]
  [[ "$output" == *"Boxes cannot be renamed"* ]]
}

@test "agy-box-manager: install-global and autocomplete never touch host dotfiles or ~/.local/bin/agy" {
  mkdir -p "$HOME/.local/bin"
  printf '#!/bin/sh\necho "host-native-agy"\n' > "$HOME/.local/bin/agy"
  chmod +x "$HOME/.local/bin/agy"
  printf '# untouched bashrc\n' > "$HOME/.bashrc"
  printf '# untouched zshrc\n' > "$HOME/.zshrc"

  create_mock "podman" 'exit 0'

  run ./agy-box-manager install-global
  [ "$status" -eq 0 ]
  [ -x "$HOME/.local/bin/agy-box-manager" ]

  run ./agy-box-manager install -n agy-box-cleanhost -y --no-enter
  [ "$status" -eq 0 ]

  # Host agy binary and shell RC files are 100% untouched
  run "$HOME/.local/bin/agy"
  [ "$output" = "host-native-agy" ]
  [ "$(cat "$HOME/.bashrc")" = "# untouched bashrc" ]
  [ "$(cat "$HOME/.zshrc")" = "# untouched zshrc" ]
  [ ! -e "$HOME/.local/share/bash-completion/completions/agy" ]
  [ -f "$HOME/.local/share/bash-completion/completions/agy-box-manager" ]

  local comp_file="$TEST_DIR/agy-completion.bash"
  run ./agy-box-manager autocomplete bash
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" > "$comp_file"
  run bash -n "$comp_file"
  [ "$status" -eq 0 ]
  run bash -c "source '$comp_file' && declare -F _agy_box_manager >/dev/null && ! declare -F _agy >/dev/null"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: resolve_target_box handles 0 boxes, auto-selects 1 box, channels, and slug suffixes" {
  create_mock "podman" 'exit 0'
  run bash -c 'source ./agy-box-manager && resolve_target_box ""'
  [ "$status" -ne 0 ]
  [[ "$output" == *"No AGY boxes installed"* ]]

  # Single box auto-selected
  create_mock "podman" 'if [ "$1" = "ps" ]; then echo "agy-box-golden-spark"; fi; exit 0'
  run bash -c 'source ./agy-box-manager && resolve_target_box ""'
  [ "$status" -eq 0 ]
  [ "$output" = "agy-box-golden-spark" ]

  # Multiple boxes: channel & suffix resolution; empty non-interactive fails cleanly
  mkdir -p "$HOME/.config/agy-box/homes/agy-box-golden-spark"
  echo 'AGY_BOX_CHANNEL="stable"' > "$HOME/.config/agy-box/homes/agy-box-golden-spark/.agy-box-meta"
  mkdir -p "$HOME/.config/agy-box/homes/agy-box-dev-lunar-comet"
  echo 'AGY_BOX_CHANNEL="dev"' > "$HOME/.config/agy-box/homes/agy-box-dev-lunar-comet/.agy-box-meta"

  create_mock "podman" '
if [ "$1" = "ps" ]; then
  echo "agy-box-golden-spark"
  echo "agy-box-dev-lunar-comet"
fi
exit 0
'
  run bash -c 'AGY_NONINTERACTIVE=1; source ./agy-box-manager && resolve_target_box "" < /dev/null'
  [ "$status" -ne 0 ]
  [[ "$output" == *"Multiple AGY boxes installed"* ]]

  run bash -c 'source ./agy-box-manager && resolve_target_box "stable"'
  [ "$status" -eq 0 ]
  [ "$output" = "agy-box-golden-spark" ]

  run bash -c 'source ./agy-box-manager && resolve_target_box "dev"'
  [ "$status" -eq 0 ]
  [ "$output" = "agy-box-dev-lunar-comet" ]

  run bash -c 'source ./agy-box-manager && resolve_target_box "golden-spark"'
  [ "$status" -eq 0 ]
  [ "$output" = "agy-box-golden-spark" ]

  run bash -c 'source ./agy-box-manager && resolve_target_box "lunar-comet"'
  [ "$status" -eq 0 ]
  [ "$output" = "agy-box-dev-lunar-comet" ]
}

@test "agy-box-manager: calculate_box_port_offset starts at 0 (6080) and increments on collision" {
  create_mock "podman" 'exit 0'
  run bash -c 'source ./agy-box-manager && calculate_box_port_offset "agy-box-golden-spark"'
  [ "$status" -eq 0 ]
  [ "$output" -eq 0 ]

  create_mock "podman" '
if [ "$1" = "ps" ] && [[ "$*" == *"{{.Ports}}"* ]]; then
  echo "0.0.0.0:6080->6080/tcp"
  echo "0.0.0.0:6081->6080/tcp"
fi
exit 0
'
  run bash -c 'source ./agy-box-manager && calculate_box_port_offset "agy-box-lunar-comet"'
  [ "$status" -eq 0 ]
  [ "$output" -eq 2 ]
}

@test "agy-box-manager: install works without distrobox by default and rejects explicit --mode workstation without distrobox" {
  local no_dbx_bin="$TEST_DIR/no_dbx_bin"
  mkdir -p "$no_dbx_bin"
  local util
  for util in bash sh mkdir rm ls cat grep awk sed sort head tail cut du id chmod cp mv mktemp uname tr printf dirname basename sleep clear date od wc tee touch; do
    if command -v "$util" >/dev/null 2>&1; then
      ln -sf "$(command -v "$util")" "$no_dbx_bin/$util"
    fi
  done

  local mock_log="$TEST_DIR/no_dbx_mock.log"
  cat <<EOF2 > "$no_dbx_bin/podman"
#!/bin/bash
echo "podman \$*" >> "$mock_log"
exit 0
EOF2
  chmod +x "$no_dbx_bin/podman"
  ln -sf "$MOCK_BIN/ss" "$no_dbx_bin/ss"

  PATH="$no_dbx_bin" run ./agy-box-manager install -n agy-box-nodistrobox -y --no-enter
  [ "$status" -eq 0 ]
  run grep -F "podman run -d --name agy-box-nodistrobox" "$mock_log"
  [ "$status" -eq 0 ]

  # Explicit --mode workstation fails cleanly when distrobox is missing
  PATH="$no_dbx_bin" run ./agy-box-manager install -n agy-box-explicit-ws --mode workstation -y --no-enter
  [ "$status" -ne 0 ]
  [[ "$output" == *"distrobox is not installed"* ]]
}

@test "agy-box-manager: install --image localhost/... skips pull and docker sandbox passes PUID/PGID" {
  local mock_log="$TEST_DIR/docker_local.log"
  mkdir -p "$HOME/.config/agy-box"
  echo 'AGY_CONTAINER_MANAGER="docker"' > "$HOME/.config/agy-box/config.env"
  cat <<EOF2 > "$MOCK_BIN/docker"
#!/bin/bash
echo "docker \$*" >> "$mock_log"
if [ "\$1" = "image" ] && [ "\$2" = "inspect" ]; then
  exit 0
fi
exit 0
EOF2
  chmod +x "$MOCK_BIN/docker"

  run ./agy-box-manager install --name agy-box-spark --image localhost/agy-box:stable -y --no-enter
  [ "$status" -eq 0 ]
  [[ "$output" == *"Using local container image 'localhost/agy-box:stable'..."* ]]
  if grep -F "docker pull" "$mock_log"; then
    return 1
  fi
  run grep -F -e "-e PUID=$(id -u) -e PGID=$(id -g)" "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: AGY_PROFILE_SEEDING=true mounts host ssh, gitconfig, and gcloud uniformly" {
  local mock_log="$TEST_DIR/seeding.log"
  mkdir -p "$HOME/.ssh" "$HOME/.config/gcloud" "$HOME/.config/agy-box"
  touch "$HOME/.gitconfig"
  cat <<'EOF' > "$HOME/.config/agy-box/config.env"
AGY_CONTAINER_MANAGER="podman"
AGY_PROFILE_SEEDING="true"
EOF
  create_mock "podman" "echo \"podman \$*\" >> '$mock_log'; exit 0"

  run ./agy-box-manager install -n agy-box-seeded -y --no-enter
  [ "$status" -eq 0 ]
  run grep -F -e "-v $HOME/.ssh:/home/agyuser/.ssh:ro" "$mock_log"
  [ "$status" -eq 0 ]
  run grep -F -e "-v $HOME/.gitconfig:/home/agyuser/.gitconfig:ro" "$mock_log"
  [ "$status" -eq 0 ]
  run grep -F -e "-v $HOME/.config/gcloud:/home/agyuser/.config/gcloud:ro" "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_enter supports auto-selection, shorthand, and non-TTY command execution" {
  local mock_log="$TEST_DIR/enter_mock.log"
  create_mock "podman" "echo \"podman \$*\" >> '$mock_log'; if [ \"\$1\" = \"ps\" ]; then echo \"agy-box-staging\"; fi; exit 0"

  run bash -c "./agy-box-manager enter -- agy --version < /dev/null"
  [ "$status" -eq 0 ]
  run grep -F "podman exec -u agyuser -w /home/agyuser agy-box-staging agy --version" "$mock_log"
  [ "$status" -eq 0 ]

  run bash -c "./agy-box-manager enter staging -- id < /dev/null"
  [ "$status" -eq 0 ]
  run grep -F "podman exec -u agyuser -w /home/agyuser agy-box-staging id" "$mock_log"
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: cmd_desktop logs to vdi.log, supports --detach/--stop, and passes workstation D-Bus env selectively" {
  local mock_log="$TEST_DIR/desktop_mock.log"
  create_mock "podman" "echo \"podman \$*\" >> '$mock_log'; if [ \"\$1\" = \"ps\" ]; then echo \"agy-box-test\"; fi; exit 0"

  run ./agy-box-manager desktop agy-box-test -r 2560x1440 --detach
  [ "$status" -eq 0 ]
  [[ "$output" == *"VDI Desktop is accessible at"* ]]
  run grep -F '$HOME/.local/state/agy-box/vdi.log' "$mock_log"
  [ "$status" -eq 0 ]
  run grep -F -- "-p 6080 -r 2560x1440" "$mock_log"
  [ "$status" -eq 0 ]

  create_mock "podman" "echo \"podman \$*\" >> '$mock_log'; if [ \"\$1\" = \"ps\" ]; then echo \"agy-box-test\"; elif [ \"\$1\" = \"exec\" ] && [[ \"\$*\" == *\"pgrep\"* ]]; then exit 1; fi; exit 0"
  run ./agy-box-manager desktop agy-box-test --stop
  [ "$status" -eq 0 ]
  [[ "$output" == *"stopped cleanly"* ]]

  # Workstation host vs isolated D-Bus forwarding
  local ws_log="$TEST_DIR/desktop_ws.log"
  mkdir -p "$HOME/.config/agy-box"
  printf 'AGY_CONTAINER_MANAGER="podman"\nAGY_KEYRING_MODE="host"\n' > "$HOME/.config/agy-box/config.env"
  create_mock "distrobox" 'exit 0'
  create_mock "podman" '
echo "podman $*" >> "'"$ws_log"'"
if [ "$1" = "ps" ]; then echo "agy-box-ws";
elif [ "$1" = "inspect" ] && [[ "$*" == *"manager"* ]]; then echo "distrobox";
elif [ "$1" = "inspect" ] && [[ "$*" == *"State.Running"* ]]; then echo "true";
elif [ "$1" = "exec" ] && [[ "$*" == *"pgrep"* ]]; then [ -f "'"$TEST_DIR"'/ws_started" ] && exit 0 || exit 1;
elif [ "$1" = "exec" ] && [ "$2" = "-d" ]; then touch "'"$TEST_DIR"'/ws_started";
fi
exit 0
'
  run env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" XDG_RUNTIME_DIR="/run/user/1000" \
    ./agy-box-manager desktop agy-box-ws -p 6092 --detach
  [ "$status" -eq 0 ]
  run grep -F -- "-e DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus" "$ws_log"
  [ "$status" -eq 0 ]

  rm -f "$ws_log" "$TEST_DIR/ws_started"
  printf 'AGY_CONTAINER_MANAGER="podman"\nAGY_KEYRING_MODE="isolated"\n' > "$HOME/.config/agy-box/config.env"
  run env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus" XDG_RUNTIME_DIR="/run/user/1000" \
    ./agy-box-manager desktop agy-box-ws --detach
  [ "$status" -eq 0 ]
  local exec_line
  exec_line=$(grep -F "podman exec -d" "$ws_log")
  [[ "$exec_line" == *"-e AGY_KEYRING_MODE=isolated"* ]]
  [[ "$exec_line" != *"DBUS_SESSION_BUS_ADDRESS"* ]]
}

@test "agy-box-manager: workstation install heals subuid ownership after distrobox enter without EncryptedKeyring files" {
  local mock_log="$TEST_DIR/ws_perm.log"
  local ws_home="$HOME/.config/agy-box/homes/agy-box-ws-perm"

  create_mock "podman" '
echo "podman $*" >> "'"$mock_log"'"
if [ "$1" = "unshare" ]; then
  chmod -R u+rwx "'"$ws_home"'" 2>/dev/null || true
  exit 0
elif [ "$1" = "ps" ] && [ -f "'"$TEST_DIR"'/ws_created" ]; then
  echo "agy-box-ws-perm"
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

  run ./agy-box-manager install -n agy-box-ws-perm --mode workstation -y --no-enter
  [ "$status" -eq 0 ]
  [ ! -e "$ws_home/.config/python_keyring/keyringrc.cfg" ]

  local enter_line chown_last_line
  enter_line=$(grep -nF "distrobox enter agy-box-ws-perm -- true" "$mock_log" | head -n1 | cut -d: -f1)
  chown_last_line=$(grep -nF "podman unshare chown -R 0:0 $ws_home" "$mock_log" | tail -n1 | cut -d: -f1)
  [ "$chown_last_line" -gt "$enter_line" ]
}

@test "agy-box-manager: cmd_clean enforces non-interactive safety and supports clean --all --purge -y" {
  local mock_log="$TEST_DIR/clean_all.log"
  create_mock "podman" '
echo "podman $*" >> "'"$mock_log"'"
if [ "$1" = "ps" ]; then
  echo "agy-box-golden-spark"
  echo "agy-box-dev-lunar-comet"
fi
exit 0
'
  mkdir -p "$HOME/.config/agy-box/homes/agy-box-golden-spark"
  echo "a" > "$HOME/.config/agy-box/homes/agy-box-golden-spark/f"
  mkdir -p "$HOME/.config/agy-box/homes/agy-box-dev-lunar-comet"
  echo "b" > "$HOME/.config/agy-box/homes/agy-box-dev-lunar-comet/f"

  # Non-interactive single-box clean without --purge/--keep fails safely
  run bash -c "./agy-box-manager clean agy-box-golden-spark < /dev/null"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Non-interactive clean requires an explicit choice"* ]]
  [ -d "$HOME/.config/agy-box/homes/agy-box-golden-spark" ]

  # clean --all --purge -y removes every managed box and home directory
  run ./agy-box-manager clean --all --purge -y
  [ "$status" -eq 0 ]
  run grep -F "podman rm -f agy-box-golden-spark" "$mock_log"
  [ "$status" -eq 0 ]
  run grep -F "podman rm -f agy-box-dev-lunar-comet" "$mock_log"
  [ "$status" -eq 0 ]
  [ ! -d "$HOME/.config/agy-box/homes/agy-box-golden-spark" ]
  [ ! -d "$HOME/.config/agy-box/homes/agy-box-dev-lunar-comet" ]

  # clean --all when 0 boxes exist succeeds cleanly
  create_mock "podman" 'exit 0'
  run ./agy-box-manager clean --all --purge -y
  [ "$status" -eq 0 ]
}

@test "agy-box-manager: structured logging records [CMD]/[EXIT], rotates >5MB logs, prints hint on failure, and surfaces via logs CLI" {
  # 1. Test > 5MB log rotation
  mkdir -p "$AGY_LOG_DIR"
  dd if=/dev/zero of="$AGY_LOG_DIR/agy-box-manager.log" bs=1048576 count=6 2>/dev/null
  run bash -c 'source ./agy-box-manager && init_logging'
  [ "$status" -eq 0 ]
  [ -f "$AGY_LOG_DIR/agy-box-manager.log.1" ]
  [ ! -f "$AGY_LOG_DIR/agy-box-manager.log" ]

  # 2. Test failed install records [CMD] & [EXIT rc=...] and prints diagnostic hint
  create_mock "podman" '
if [ "$1" = "pull" ]; then
  echo "simulated registry timeout" >&2
  exit 42
fi
exit 0
'
  run ./agy-box-manager install -n agy-box-broken-pull -y --no-enter
  [ "$status" -ne 0 ]
  [[ "$output" == *"📋 Diagnostic log:"* ]]
  [[ "$output" == *"agy-box-manager logs agy-box-broken-pull"* ]]
  [ -f "$AGY_LOG_DIR/agy-box-manager.log" ]
  [ -f "$AGY_LOG_DIR/agy-box-broken-pull.log" ]

  run grep -F "[CMD] podman pull" "$AGY_LOG_DIR/agy-box-broken-pull.log"
  [ "$status" -eq 0 ]
  run grep -F "simulated registry timeout" "$AGY_LOG_DIR/agy-box-broken-pull.log"
  [ "$status" -eq 0 ]
  run grep -E '\[EXIT rc=42 elapsed=[0-9]+s\] podman pull' "$AGY_LOG_DIR/agy-box-broken-pull.log"
  [ "$status" -eq 0 ]

  # 3. 'logs <box>' works even when container creation failed and container does not exist!
  run ./agy-box-manager logs broken-pull
  [ "$status" -eq 0 ]
  [[ "$output" == *"simulated registry timeout"* ]]

  # 4. Container state logs (.local/state/agy-box/{doctor,vdi,toolchain}.log) surfaced cleanly
  local st_dir="$HOME/.config/agy-box/homes/agy-box-broken-pull/.local/state/agy-box"
  mkdir -p "$st_dir"
  echo "doctor check passed in 12ms" > "$st_dir/doctor.log"
  echo "vdi websockify ready on 6080" > "$st_dir/vdi.log"
  echo "toolchain agy 1.5.5 verified" > "$st_dir/toolchain.log"

  run ./agy-box-manager logs
  [ "$status" -eq 0 ]
  [[ "$output" == *"Manager Diagnostic Log"* ]]
  [[ "$output" == *"agy-box-broken-pull (doctor)"* ]]
  [[ "$output" == *"agy-box-broken-pull (vdi)"* ]]

  run ./agy-box-manager logs broken-pull --doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"doctor check passed in 12ms"* ]]

  run ./agy-box-manager logs broken-pull --vdi
  [ "$status" -eq 0 ]
  [[ "$output" == *"vdi websockify ready on 6080"* ]]

  run ./agy-box-manager logs broken-pull
  [ "$status" -eq 0 ]
  [[ "$output" == *"Host Provisioning & Tool Log"* ]]
  [[ "$output" == *"doctor check passed in 12ms"* ]]
  [[ "$output" == *"vdi websockify ready on 6080"* ]]
  [[ "$output" == *"toolchain agy 1.5.5 verified"* ]]
}
