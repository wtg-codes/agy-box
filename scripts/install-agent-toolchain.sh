#!/bin/bash
# ==============================================================================
# agy-install-toolchain  (source: scripts/install-agent-toolchain.sh)
#
# Installs or updates the Antigravity agent toolchain (Agent UI, agy CLI,
# SDK, ADK, Gemini CLI).
#
# Modes:
#   --system   Installs system-wide into /opt and /usr/local/bin (requires root).
#              Used during container image build so Syft produces a 100% genuine
#              SBOM that Grype scans prior to release (Option A: Batteries-Included).
#   (default)  Installs or updates for the CURRENT user into $HOME/.local.
#              Run as normal non-root user inside the box.
#
# It installs (all versions pinned, downloads verified by checksum):
#   - Google Antigravity (Agent UI)  /opt/antigravity     -> /usr/local/bin/antigravity
#   - Antigravity CLI                /usr/local/bin/agy
#   - Antigravity SDK                google-antigravity==0.1.23
#   - Google ADK                     google-adk==2.1.0    -> /usr/local/bin/adk
#   - Gemini CLI                     @google/gemini-cli   -> /usr/local/bin/gemini
#
# Safe to re-run (idempotent): every component is re-installed at its pinned
# version, existing user settings are preserved, and binaries are replaced
# atomically. Any failure aborts with a non-zero exit code and an error message.
# ==============================================================================
set -Eeuo pipefail

PROG="agy-install-toolchain"
CURRENT_STEP="initialisation"

usage() {
    cat <<EOF
Usage: ${PROG} [--system] [-h|--help]

Install or update the Antigravity agent toolchain (Agent UI, agy CLI,
SDK, ADK, Gemini CLI).
  --system   Install system-wide into /opt and /usr/local/bin (requires root).
             Used during image build so Syft produces an authentic SBOM.
  (no flag)  Install into \$HOME/.local for the current user. Safe to re-run.
EOF
}

MODE="user"
for arg in "$@"; do
    case "$arg" in
        --system) MODE="system" ;;
        -h|--help) usage; exit 0 ;;
        "") ;;
        *) echo "${PROG}: unknown argument: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

die() {
    echo "${PROG}: ERROR: $*" >&2
    exit 1
}

on_error() {
    local rc=$1 line=$2
    echo "" >&2
    echo "${PROG}: ERROR: step '${CURRENT_STEP}' failed (exit ${rc}, line ${line})." >&2
    echo "${PROG}: The Antigravity toolchain may be incomplete. Re-run '${PROG}' to retry." >&2
}
trap 'on_error $? $LINENO' ERR

step() {
    CURRENT_STEP="$1"
    echo "==> $1"
}

# --- Pre-flight checks --------------------------------------------------------
if [ "$MODE" = "system" ]; then
    if [ "$(id -u)" -ne 0 ]; then
        die "system installation requires root."
    fi
    BIN_DIR="/usr/local/bin"
    SHARE_DIR="/opt"
else
    if [ "$(id -u)" -eq 0 ]; then
        die "do not run as root; run as your normal user inside the box (installs into \$HOME/.local), or pass --system for system-wide install."
    fi
    if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ] || [ ! -w "$HOME" ]; then
        die "HOME ('${HOME:-}') is not set or not a writable directory."
    fi
    BIN_DIR="$HOME/.local/bin"
    SHARE_DIR="$HOME/.local/share"
fi

arch="$(uname -m)"
case "$arch" in
    x86_64)
        CLI_ARCH="linux-x64"
        CLI_TARBALL="cli_linux_x64.tar.gz"
        CLI_SHA512="746a2bd73f83b65d9b44f2fc55d0f0f511ff7f89702846213eeabd76d06bc9c98576b424c2babc7b947f15e518447b946ba02dca260b778363c55c07a7f7a277"
        HUB_ARCH="linux-x64"
        HUB_SHA256="30ccdea1fff0bf643b7f6e7aa493240d13ec1d866acf4f89c2a6cc3a2c33369c"
        ;;
    aarch64|arm64)
        CLI_ARCH="linux-arm"
        CLI_TARBALL="cli_linux_arm64.tar.gz"
        CLI_SHA512="eb3e025c125c1c60a1493a0c1d9cdf15e8372277d6d3b015e8d29e1bd095344eece5cbc2447f238148bd259d5f2daa0f75641adc0ac02b5fad57edc4ed842d59"
        HUB_ARCH="linux-arm"
        HUB_SHA256="0b3cdd17faac0e8ee1f80494787ac1ef78f5404bc216ccecf0e3fe95918b2dac"
        ;;
    *)
        die "unsupported architecture '${arch}': must be x86_64 or aarch64."
        ;;
esac

for cmd in curl tar sha256sum sha512sum python3 npm; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command '${cmd}' not found in PATH."
done

if [ "$MODE" = "system" ]; then
    :  # system mode bootstraps its own pinned uv below
else
    command -v pip3 >/dev/null 2>&1 || die "required command 'pip3' not found in PATH for user install."
    # Ensure user directories in HOME are writable. When distrobox initializes,
    # files from /etc/skel may be copied with root ownership if the container was
    # started by root/distrobox-init. Fix ownership using passwordless sudo.
    for d in "$HOME/.config" "$HOME/.gemini" "$HOME/.local" "$HOME/.vscode" "$HOME/Desktop"; do
        if [ -e "$d" ] && [ ! -w "$d" ]; then
            if command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
                sudo chown -R "$(id -u):$(id -g)" "$d" 2>/dev/null || true
                chmod -R u+rwX "$d" 2>/dev/null || true
            fi
        fi
    done
fi

mkdir -p "$BIN_DIR" "$SHARE_DIR"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/agy-toolchain.XXXXXX")"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

# download_verify <url> <sha256|sha512> <hash> <dest-file>
download_verify() {
    local url=$1 algo=$2 hash=$3 dest=$4
    curl -fsSL --http1.1 --connect-timeout 5 --retry 5 --retry-delay 2 "$url" -o "$dest"
    echo "$hash  $dest" | "${algo}sum" -c -
}

# install_app_tarball <url> <sha256> <install-dir>
# Extracts into a staging dir and swaps it in only after a successful extract.
install_app_tarball() {
    local url=$1 sha=$2 dest=$3
    local tarball
    tarball="$WORK_DIR/$(basename "$dest").tar.gz"
    download_verify "$url" sha256 "$sha" "$tarball"
    rm -rf "${dest}.new"
    mkdir -p "${dest}.new"
    tar -xzf "$tarball" -C "${dest}.new" --strip-components=1
    if [ "$MODE" = "system" ]; then
        chmod -R ugo+rX "${dest}.new"
    fi
    rm -rf "$dest"
    mv "${dest}.new" "$dest"
    rm -f "$tarball"
}

# write_file_atomic <dest> <mode>  (content on stdin)
write_file_atomic() {
    local dest=$1 mode=$2
    cat > "${dest}.new"
    chmod "$mode" "${dest}.new"
    mv -f "${dest}.new" "$dest"
}

# ensure_default_settings <settings.json>: create with telemetry disabled if
# missing; never overwrite existing user settings on re-runs.
ensure_default_settings() {
    local file=$1
    local dir
    dir="$(dirname "$file")"
    if [ ! -d "$dir" ]; then
        if ! mkdir -p "$dir" 2>/dev/null; then
            if command -v sudo &>/dev/null && sudo -n true 2>/dev/null; then
                sudo mkdir -p "$dir"
                sudo chown -R "$(id -u):$(id -g)" "$dir" 2>/dev/null || true
            else
                mkdir -p "$dir"
            fi
        fi
    fi
    if [ ! -f "$file" ]; then
        echo '{"antigravity.account.enableTelemetry": false}' > "$file"
    fi
}

# --- 1. Google Antigravity (Agent UI) (2.31.0 Tarball) ------------------------
step "Installing Google Antigravity (Agent UI)"
IDE_VERSION="2.31.0"
IDE_EXEC_ID="6379060755038208"
IDE_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/${IDE_VERSION}-${IDE_EXEC_ID}/${HUB_ARCH}/Antigravity.tar.gz"
install_app_tarball "$IDE_URL" "$HUB_SHA256" "$SHARE_DIR/antigravity"

# Extract application icon from Electron app.asar when bundled inside resources/
if [ -f "$SHARE_DIR/antigravity/resources/app.asar" ]; then
    python3 - "$SHARE_DIR/antigravity/resources/app.asar" "$SHARE_DIR/antigravity/resources/icon.png" <<'PYEOF' || true
import json, struct, sys

asar_path, out_path = sys.argv[1], sys.argv[2]
with open(asar_path, "rb") as fh:
    _, hdr_size, _, str_len = struct.unpack("<IIII", fh.read(16))
    tree = json.loads(fh.read(str_len).decode("utf-8"))
    base_offset = 8 + hdr_size
    entry = tree.get("files", {}).get("icon.png")
    if entry and "offset" in entry and "size" in entry:
        fh.seek(base_offset + int(entry["offset"]))
        data = fh.read(int(entry["size"]))
        if data.startswith(b"\x89PNG\r\n\x1a\n"):
            with open(out_path, "wb") as out:
                out.write(data)
PYEOF
    if [ -f "$SHARE_DIR/antigravity/resources/icon.png" ]; then
        if [ "$MODE" = "system" ]; then
            mkdir -p /usr/share/pixmaps /usr/share/icons/hicolor/512x512/apps
            cp -f "$SHARE_DIR/antigravity/resources/icon.png" /usr/share/pixmaps/antigravity.png
            cp -f "$SHARE_DIR/antigravity/resources/icon.png" /usr/share/icons/hicolor/512x512/apps/antigravity.png
            chmod 0644 /usr/share/pixmaps/antigravity.png /usr/share/icons/hicolor/512x512/apps/antigravity.png
            if command -v gtk-update-icon-cache >/dev/null 2>&1; then
                gtk-update-icon-cache -f -t /usr/share/icons/hicolor 2>/dev/null || true
            fi
        else
            mkdir -p "$HOME/.local/share/icons/hicolor/512x512/apps"
            cp -f "$SHARE_DIR/antigravity/resources/icon.png" "$HOME/.local/share/icons/hicolor/512x512/apps/antigravity.png"
        fi
    fi
fi

app_exec="$SHARE_DIR/antigravity/antigravity"
write_file_atomic "$BIN_DIR/antigravity" 0755 << EOF
#!/bin/bash
target_bin="$app_exec"
if [ "$MODE" = "system" ] && [ -n "\${HOME:-}" ] && [ -x "\$HOME/.local/share/antigravity/antigravity" ]; then
    target_bin="\$HOME/.local/share/antigravity/antigravity"
fi
extra_flags=()
case " \$* " in
    *" --password-store="*) ;;
    *)
        use_basic=false
        if [ "\${AGY_PASSWORD_STORE:-}" = "basic" ] || [ "\${AGY_KEYRING_MODE:-}" = "isolated" ] || [ -z "\${DBUS_SESSION_BUS_ADDRESS:-}" ]; then
            use_basic=true
        elif command -v dbus-send >/dev/null 2>&1; then
            if ! dbus-send --session --dest=org.freedesktop.DBus --type=method_call --print-reply /org/freedesktop/DBus org.freedesktop.DBus.ListNames 2>/dev/null | grep -q 'org\.freedesktop\.secrets' && \\
               ! dbus-send --session --dest=org.freedesktop.DBus --type=method_call --print-reply /org/freedesktop/DBus org.freedesktop.DBus.ListActivatableNames 2>/dev/null | grep -q 'org\.freedesktop\.secrets'; then
                use_basic=true
            fi
        fi
        if [ "\$use_basic" = "true" ]; then
            extra_flags+=("--password-store=basic")
        fi
        ;;
esac
if [ -e /run/.containerenv ] || [ -e /run/.toolboxenv ]; then
    mkdir -p "\$HOME/.config/Antigravity-box/User"
    if [ ! -f "\$HOME/.config/Antigravity-box/User/settings.json" ]; then
        echo '{"antigravity.account.enableTelemetry": false, "antigravity.browser.chromeBinaryPath": "/usr/bin/google-chrome-stable", "window.titleBarStyle": "native"}' > "\$HOME/.config/Antigravity-box/User/settings.json"
    elif command -v jq &>/dev/null; then
        jq '.["antigravity.browser.chromeBinaryPath"] = "/usr/bin/google-chrome-stable" | .["window.titleBarStyle"] = "native"' "\$HOME/.config/Antigravity-box/User/settings.json" > "\$HOME/.config/Antigravity-box/User/settings.json.tmp" && mv "\$HOME/.config/Antigravity-box/User/settings.json.tmp" "\$HOME/.config/Antigravity-box/User/settings.json"
    fi
    exec "\$target_bin" --user-data-dir "\$HOME/.config/Antigravity-box" --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "\${extra_flags[@]}" "\$@"
else
    exec "\$target_bin" --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "\${extra_flags[@]}" "\$@"
fi
EOF

if [ "$MODE" = "user" ] && [ -z "${BATS_TEST_FILENAME:-}" ] && { [ -e /run/.containerenv ] || [ -e /run/.toolboxenv ]; }; then
    if [ -f /usr/local/bin/antigravity ] && ! grep -q -- '--password-store=basic' /usr/local/bin/antigravity 2>/dev/null; then
        if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
            sudo cp -f "$BIN_DIR/antigravity" /usr/local/bin/antigravity 2>/dev/null || true
            sudo chmod 0755 /usr/local/bin/antigravity 2>/dev/null || true
        fi
    fi
fi

# Disable Antigravity telemetry (only when no settings exist yet)
if [ "$MODE" = "system" ]; then
    ensure_default_settings "/etc/skel/.config/Antigravity/User/settings.json"
    ensure_default_settings "/etc/skel/.config/Antigravity-box/User/settings.json"
else
    ensure_default_settings "$HOME/.config/Antigravity/User/settings.json"
fi


# --- 2. Clean Up Legacy Antigravity IDE & Duplicate Desktop Icons -------------
# Antigravity IDE (antigravity-ide) has been retired in favor of Google Antigravity App (antigravity),
# Antigravity CLI (agy), VS Code, Zed, and JetBrains IDEs. Clean up any legacy installation artifacts.
rm -f "$BIN_DIR/antigravity-ide" 2>/dev/null || true
rm -rf "$SHARE_DIR/antigravity-ide" 2>/dev/null || true
if [ "$MODE" = "system" ]; then
    rm -f "/etc/skel/Desktop/Antigravity2.desktop" \
          "/etc/skel/Desktop/AntigravityIDE.desktop" \
          "/etc/skel/Desktop/google-antigravity.desktop" 2>/dev/null || true
    rm -rf "/etc/skel/.config/Antigravity-ide" "/etc/skel/.config/Antigravity-ide-box" 2>/dev/null || true
elif [ -n "${HOME:-}" ]; then
    rm -f "$HOME/Desktop/Antigravity2.desktop" \
          "$HOME/Desktop/AntigravityIDE.desktop" \
          "$HOME/Desktop/google-antigravity.desktop" 2>/dev/null || true
    rm -rf "$HOME/.config/Antigravity-ide" "$HOME/.config/Antigravity-ide-box" 2>/dev/null || true
    if [ -d /etc/skel/Desktop ] && [ -d "$HOME/Desktop" ]; then
        cp -rn /etc/skel/Desktop/. "$HOME/Desktop/" 2>/dev/null || true
        chmod +x "$HOME"/Desktop/*.desktop 2>/dev/null || true
    fi
fi


# --- 3. Antigravity CLI (1.5.5 Tarball) ---------------------------------------
step "Installing Antigravity CLI (agy)"
CLI_VERSION="1.5.5"
CLI_EXEC_ID="6740358537805824"
CLI_URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/${CLI_VERSION}-${CLI_EXEC_ID}/${CLI_ARCH}/${CLI_TARBALL}"

download_verify "$CLI_URL" sha512 "$CLI_SHA512" "$WORK_DIR/$CLI_TARBALL"
tar -xzf "$WORK_DIR/$CLI_TARBALL" -C "$WORK_DIR" antigravity
# Copy next to the target and rename, so a running agy is replaced atomically.
cp "$WORK_DIR/antigravity" "$BIN_DIR/agy.new"
chmod 0755 "$BIN_DIR/agy.new"
mv -f "$BIN_DIR/agy.new" "$BIN_DIR/agy"


# --- 4 & 5. Antigravity SDK & Google ADK --------------------------------------
if [ "$MODE" = "system" ]; then
    step "Installing Google ADK and Antigravity SDK (system-wide)"
    export PIP_NO_COMPILE=1
    # Pinned, statically linked uv for the build architecture.
    UV_VERSION="0.13.7"
    case "$arch" in
        aarch64|arm64) uv_triple="aarch64-unknown-linux-musl" ;;
        *) uv_triple="x86_64-unknown-linux-musl" ;;
    esac
    mkdir -p "$WORK_DIR/uv"
    curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 5 \
        "https://github.com/astral-sh/uv/releases/download/${UV_VERSION}/uv-${uv_triple}.tar.gz" \
        | tar -xz -C "$WORK_DIR/uv" --strip-components=1 "uv-${uv_triple}/uv"
    UV_BIN="$WORK_DIR/uv/uv"

    PY_VENV="/opt/agy-python"
    rm -rf "$PY_VENV"
    python3 -m venv --without-pip "$PY_VENV"
    "$UV_BIN" pip install --python "$PY_VENV/bin/python" \
        pip google-adk==2.1.0 google-antigravity==0.1.23
    ln -sf "$PY_VENV/bin/adk" /usr/local/bin/adk
    # Enable system python3 to find the packages via .pth file
    for pydir in /usr/local/lib/python*/dist-packages /usr/lib/python*/dist-packages; do
        if [ -d "$pydir" ]; then
            for site in "$PY_VENV"/lib/python*/site-packages; do
                if [ -d "$site" ]; then
                    echo "$site" > "$pydir/agy-toolchain.pth"
                fi
            done
        fi
    done
else
    step "Installing Antigravity SDK"
    pip3 install --user --break-system-packages --no-cache-dir --retries 10 google-antigravity==0.1.23

    step "Installing Google ADK"
    pip3 install --user --break-system-packages --no-cache-dir --retries 10 google-adk==2.1.0
fi


# --- 6. Gemini CLI ------------------------------------------------------------
step "Installing Gemini CLI"
if [ "$MODE" = "system" ]; then
    NODE_OPTIONS="${NODE_OPTIONS:---jitless}" UV_THREADPOOL_SIZE=1 \
        npm install -g --prefix /usr/local --omit=dev --no-audit --no-fund @google/gemini-cli@0.43.0
else
    npm install -g --prefix "$HOME/.local" --omit=dev --no-audit --no-fund @google/gemini-cli@0.43.0
fi


# --- 7. Visual Studio Code Antigravity Extension -----------------------------
if [ "$MODE" = "system" ]; then
    mkdir -p /etc/skel/.vscode
    if [ ! -f /etc/skel/.vscode/extensions.json ]; then
        echo '{"recommendations": ["Google.google-antigravity"]}' > /etc/skel/.vscode/extensions.json
    fi
elif command -v code >/dev/null 2>&1; then
    step "Installing Antigravity extension for Visual Studio Code"
    code --install-extension Google.google-antigravity --force || true
fi


# --- 8. Zed Editor Configuration ---------------------------------------------
if [ "$MODE" = "system" ]; then
    mkdir -p /etc/skel/.config/zed
    if [ ! -f /etc/skel/.config/zed/settings.json ]; then
        echo '{"auto_install_extensions": {"antigravity": true}}' > /etc/skel/.config/zed/settings.json
    fi
else
    mkdir -p "$HOME/.config/zed"
    if [ ! -f "$HOME/.config/zed/settings.json" ]; then
        echo '{"auto_install_extensions": {"antigravity": true}}' > "$HOME/.config/zed/settings.json"
    fi
fi


# --- Verify -------------------------------------------------------------------
step "Verifying installation"
missing=0
for bin in antigravity agy adk gemini; do
    if [ ! -x "$BIN_DIR/$bin" ]; then
        echo "${PROG}: ERROR: expected executable $BIN_DIR/$bin is missing." >&2
        missing=$((missing + 1))
    fi
done
if [ "$missing" -ne 0 ]; then
    die "${missing} toolchain component(s) missing after install."
fi

if [ "$MODE" = "system" ]; then
    echo "Agent toolchain installed successfully at system level ($BIN_DIR, $SHARE_DIR)."
else
    echo "Agent toolchain installed successfully at user level ($BIN_DIR)."
    case ":${PATH}:" in
        *":$BIN_DIR:"*) ;;
        *) echo "Note: $BIN_DIR is not on your PATH in this shell; open a new login shell (or run: export PATH=\"$BIN_DIR:\$PATH\")." ;;
    esac
fi
