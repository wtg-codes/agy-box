#!/usr/bin/env bats
# Tests for container-side health doctor, non-blocking keyring check, bloat removal,
# and structured logging ($HOME/.local/state/agy-box/*.log).

setup() {
  TEST_DIR="$(mktemp -d)"
  MOCK_BIN="$TEST_DIR/bin"
  MOCK_PY="$TEST_DIR/pylib"
  mkdir -p "$MOCK_BIN" "$MOCK_PY"

  export ORIGINAL_PATH="$PATH"
  export ORIGINAL_HOME="$HOME"
  export HOME="$TEST_DIR/home"
  export XDG_RUNTIME_DIR="$TEST_DIR/runtime"
  mkdir -p "$HOME" "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"
  unset DBUS_SESSION_BUS_ADDRESS
  unset KEYRING_CRYPT_PASSWORD
  unset PYTHON_KEYRING_BACKEND
  unset AGY_BOX_STATE_DIR
  unset AGY_LOG_DISABLED
  export AGY_VDI_COMPAT_LOG="$TEST_DIR/agy-vdi.log"
  export PATH="$MOCK_BIN:$PATH"
}

teardown() {
  export PATH="$ORIGINAL_PATH"
  export HOME="$ORIGINAL_HOME"
  rm -rf "$TEST_DIR"
}

@test "legacy setup bloat and on-demand IDE installer are removed; agy-doctor is v0.8.0 and < 80 lines" {
  [ ! -e rootfs/etc/profile.d/agy-setup-check.sh ]
  [ ! -e rootfs/usr/local/bin/agy-setup-helper ]
  [ ! -e rootfs/usr/local/bin/agy-install-ide ]
  [ ! -e rootfs/etc/skel/Desktop/SetupAssistant.desktop ]
  ! grep -q "agy-setup-helper" rootfs/etc/X11/icewm/menu
  ! grep -q "agy-setup-helper" rootfs/etc/X11/icewm/toolbar
  ! grep -q "agy-install-ide" Containerfile
  ! grep -q "agy-setup-check.sh" Containerfile
  grep -q "/usr/local/bin/agy-doctor" Containerfile

  [ -x rootfs/usr/local/bin/agy-doctor ]
  line_count=$(wc -l < rootfs/usr/local/bin/agy-doctor)
  [ "$line_count" -lt 80 ]

  run ./rootfs/usr/local/bin/agy-doctor --version
  [ "$status" -eq 0 ]
  [[ "$output" == *"0.8.0"* ]]
}

@test "check_keyring returns rc=4 in < 2s on EncryptedKeyring without KEYRING_CRYPT_PASSWORD and never blocks on /dev/tty" {
  mkdir -p "$MOCK_PY/keyrings/alt"
  touch "$MOCK_PY/keyrings/__init__.py" "$MOCK_PY/keyrings/alt/__init__.py"
  cat <<'PYEOF' > "$MOCK_PY/keyrings/alt/file.py"
import getpass
class EncryptedKeyring:
    def set_password(self, service, user, password):
        # Would block on /dev/tty if check_keyring failed to short-circuit or detach TTY
        getpass.getpass("Please enter password for encrypted keyring: ")
    def get_password(self, service, user):
        return None
    def delete_password(self, service, user):
        pass
PYEOF
  cat <<'PYEOF' > "$MOCK_PY/keyring.py"
from keyrings.alt.file import EncryptedKeyring
_kr = EncryptedKeyring()
def get_keyring():
    return _kr
def set_password(s, u, p):
    return _kr.set_password(s, u, p)
def get_password(s, u):
    return _kr.get_password(s, u)
def delete_password(s, u):
    return _kr.delete_password(s, u)
PYEOF

  start_sec=$(date +%s)
  PYTHONPATH="$MOCK_PY" run bash -c 'source ./rootfs/usr/local/bin/agy-doctor && check_keyring'
  end_sec=$(date +%s)
  elapsed=$((end_sec - start_sec))

  echo "status=$status elapsed=${elapsed}s output=$output"
  [ "$status" -eq 4 ]
  [ "$elapsed" -le 2 ]
  [ -s "$HOME/.local/state/agy-box/doctor.log" ]
  grep -q "keyrings.alt.file.EncryptedKeyring" "$HOME/.local/state/agy-box/doctor.log"
  grep -q "\[EXIT rc=4" "$HOME/.local/state/agy-box/doctor.log"
}

@test "check_keyring aborts within <= 5s via SIGALRM/timeout when set_password hangs" {
  cat <<'PYEOF' > "$MOCK_PY/keyring.py"
import time
class HungKeyring:
    pass
def get_keyring():
    return HungKeyring()
def set_password(s, u, p):
    time.sleep(30)
def get_password(s, u):
    return p
def delete_password(s, u):
    pass
PYEOF

  start_sec=$(date +%s)
  PYTHONPATH="$MOCK_PY" run bash -c 'source ./rootfs/usr/local/bin/agy-doctor && check_keyring'
  end_sec=$(date +%s)
  elapsed=$((end_sec - start_sec))

  echo "status=$status elapsed=${elapsed}s"
  [ "$status" -eq 124 ]
  [ "$elapsed" -le 5 ]
  grep -q "HungKeyring" "$HOME/.local/state/agy-box/doctor.log"
  grep -q "\[EXIT rc=124" "$HOME/.local/state/agy-box/doctor.log"
}

@test "check_keyring returns rc=5 in < 2s when host D-Bus org.freedesktop.secrets collection is locked" {
  cat <<'PYEOF' > "$MOCK_PY/keyring.py"
class SecretServiceKeyring:
    pass
SecretServiceKeyring.__module__ = "keyring.backends.SecretService"
SecretServiceKeyring.__name__ = "Keyring"
def get_keyring():
    return SecretServiceKeyring()
def set_password(s, u, p):
    raise AssertionError("set_password must not be called when collection is locked")
PYEOF

  cat <<'EOF' > "$MOCK_BIN/dbus-send"
#!/bin/bash
case "$*" in
  *ListNames*) echo '   string "org.freedesktop.secrets"' ;;
  *Locked*) echo '   variant       boolean true' ;;
esac
exit 0
EOF
  chmod +x "$MOCK_BIN/dbus-send"

  start_sec=$(date +%s)
  DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus" PYTHONPATH="$MOCK_PY" \
    run bash -c 'source ./rootfs/usr/local/bin/agy-doctor && check_keyring'
  end_sec=$(date +%s)
  elapsed=$((end_sec - start_sec))

  echo "status=$status elapsed=${elapsed}s"
  [ "$status" -eq 5 ]
  [ "$elapsed" -le 2 ]
  grep -q "keyring.backends.SecretService.Keyring" "$HOME/.local/state/agy-box/doctor.log"
  grep -q "Host keyring collection is locked" "$HOME/.local/state/agy-box/doctor.log"
  grep -q "\[EXIT rc=5" "$HOME/.local/state/agy-box/doctor.log"
}

@test "check_keyring succeeds (rc=0) with healthy backend and writes ISO-8601 diagnostic log" {
  cat <<'PYEOF' > "$MOCK_PY/keyring.py"
_store = {}
class HealthyMemoryKeyring:
    pass
def get_keyring():
    return HealthyMemoryKeyring()
def set_password(s, u, p):
    _store[(s, u)] = p
def get_password(s, u):
    return _store.get((s, u))
def delete_password(s, u):
    _store.pop((s, u), None)
PYEOF

  PYTHONPATH="$MOCK_PY" run bash -c 'source ./rootfs/usr/local/bin/agy-doctor && check_keyring'
  [ "$status" -eq 0 ]
  [ -s "$HOME/.local/state/agy-box/doctor.log" ]
  grep -E '^\[20[0-9]{2}-[0-9]{2}-[0-9]{2}T' "$HOME/.local/state/agy-box/doctor.log"
  grep -q "\[CMD\] check_keyring" "$HOME/.local/state/agy-box/doctor.log"
  grep -q "keyring.HealthyMemoryKeyring" "$HOME/.local/state/agy-box/doctor.log"
  grep -q "\[EXIT rc=0 duration_ms=" "$HOME/.local/state/agy-box/doctor.log"
}

@test "entrypoint.sh writes timestamped entrypoint.log when writable and tolerates read-only HOME" {
  run ./rootfs/usr/local/bin/entrypoint.sh true
  [ "$status" -eq 0 ]
  [ -s "$HOME/.local/state/agy-box/entrypoint.log" ]
  grep -q "\[entrypoint\] \[INFO\]" "$HOME/.local/state/agy-box/entrypoint.log"
  grep -q "\[entrypoint\] \[CMD\] exec true" "$HOME/.local/state/agy-box/entrypoint.log"

  # Read-only HOME must not break entrypoint execution
  ro_home="$TEST_DIR/ro-home"
  mkdir -p "$ro_home"
  chmod 500 "$ro_home"
  HOME="$ro_home" run ./rootfs/usr/local/bin/entrypoint.sh true
  chmod 700 "$ro_home"
  [ "$status" -eq 0 ]
}

@test "agy-vdi writes structured vdi.log and creates compat symlink" {
  # Provide a minimal PATH missing Xvfb so agy-vdi logs startup + missing dependency error cleanly
  ln -s "$(command -v bash)" "$MOCK_BIN/bash"
  ln -s "$(command -v date)" "$MOCK_BIN/date"
  ln -s "$(command -v mkdir)" "$MOCK_BIN/mkdir"
  ln -s "$(command -v touch)" "$MOCK_BIN/touch"
  ln -s "$(command -v ln)" "$MOCK_BIN/ln"
  ln -s "$(command -v rm)" "$MOCK_BIN/rm"

  PATH="$MOCK_BIN" AGY_VDI_COMPAT_LOG="$TEST_DIR/agy-vdi.log" \
    run ./rootfs/usr/local/bin/agy-vdi
  [ "$status" -ne 0 ]
  [ -s "$HOME/.local/state/agy-box/vdi.log" ]
  [ -L "$TEST_DIR/agy-vdi.log" ]
  grep -q "\[agy-vdi\] \[INFO\] Starting VDI session" "$HOME/.local/state/agy-box/vdi.log"
  grep -q "\[agy-vdi\] \[EXIT\] rc=1" "$HOME/.local/state/agy-box/vdi.log"
}
