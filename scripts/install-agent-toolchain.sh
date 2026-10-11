#!/bin/bash
# ==============================================================================
# agy-install-toolchain  (source: scripts/install-agent-toolchain.sh)
#
# Installs or updates the Antigravity agent toolchain (Agent UI, IDE, agy CLI,
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
#   - Antigravity IDE                /opt/antigravity-ide -> /usr/local/bin/antigravity-ide
#   - Antigravity CLI                /usr/local/bin/agy
#   - Antigravity SDK                google-antigravity==0.1.0
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

Install or update the Antigravity agent toolchain (Agent UI, IDE, agy CLI,
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
        CLI_SHA512="5ccdcc01fb863c7e8e56473c6c95dba75fed4fd2a242200d80cfc4c7fab811b733f5a7fab25332130aad298e72627e1018e6911a5658f4f059ef6e019f211972"
        HUB_ARCH="linux-x64"
        HUB_SHA256="0727e1f56961b6d2347941f278da69cc6c17de3befe988524848cd167380e9ab"
        IDE_ARCH="linux-x64"
        IDE_SHA256="5232a4048ff4fa15685d9a981ba4fba573e297f3efc9b76f638e794baf775725"
        ;;
    aarch64|arm64)
        CLI_ARCH="linux-arm"
        CLI_TARBALL="cli_linux_arm64.tar.gz"
        CLI_SHA512="9797c7955d0e07fc57605f81fab16dfd2f390d43b2508af3ca697b1cfa498e37e43a3a9a55ad8b26eb1353d80bbec522d108eb75a0eb0eb00e979cb579d6e277"
        HUB_ARCH="linux-arm"
        HUB_SHA256="5af56cc9dda954f369a61045b7da2f348bcb0b3507d272b4c0e9aa7cd6175d9b"
        IDE_ARCH="linux-arm"
        IDE_SHA256="64d11085f17edc691adbe8952d59887f257d58448705dc2a19dfa23890d36df1"
        ;;
    *)
        die "unsupported architecture '${arch}': must be x86_64 or aarch64."
        ;;
esac

for cmd in curl tar sha256sum sha512sum python3 npm; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command '${cmd}' not found in PATH."
done

if [ "$MODE" = "system" ]; then
    command -v pipx >/dev/null 2>&1 || die "required command 'pipx' not found in PATH for system install."
else
    command -v pip3 >/dev/null 2>&1 || die "required command 'pip3' not found in PATH for user install."
    # Ensure user directories in HOME are writable. When distrobox initializes,
    # files from /etc/skel may be copied with root ownership if the container was
    # started by root/distrobox-init. Fix ownership using passwordless sudo.
    for d in "$HOME/.config" "$HOME/.gemini" "$HOME/.local" "$HOME/Desktop"; do
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

# --- 1. Google Antigravity (Agent UI) (2.0.1 Tarball) -------------------------
step "Installing Google Antigravity (Agent UI)"
IDE_VERSION="2.0.1"
IDE_EXEC_ID="6566078776737792"
IDE_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/${IDE_VERSION}-${IDE_EXEC_ID}/${HUB_ARCH}/Antigravity.tar.gz"
install_app_tarball "$IDE_URL" "$HUB_SHA256" "$SHARE_DIR/antigravity"

app_exec="$SHARE_DIR/antigravity/antigravity"
write_file_atomic "$BIN_DIR/antigravity" 0755 << EOF
#!/bin/bash
if [ -e /run/.containerenv ] || [ -e /run/.toolboxenv ]; then
    mkdir -p "\$HOME/.config/Antigravity-box/User"
    if [ ! -f "\$HOME/.config/Antigravity-box/User/settings.json" ]; then
        echo '{"antigravity.account.enableTelemetry": false, "antigravity.browser.chromeBinaryPath": "/usr/bin/google-chrome-stable", "window.titleBarStyle": "native"}' > "\$HOME/.config/Antigravity-box/User/settings.json"
    elif command -v jq &>/dev/null; then
        jq '.["antigravity.browser.chromeBinaryPath"] = "/usr/bin/google-chrome-stable" | .["window.titleBarStyle"] = "native"' "\$HOME/.config/Antigravity-box/User/settings.json" > "\$HOME/.config/Antigravity-box/User/settings.json.tmp" && mv "\$HOME/.config/Antigravity-box/User/settings.json.tmp" "\$HOME/.config/Antigravity-box/User/settings.json"
    fi
    exec "$app_exec" --user-data-dir "\$HOME/.config/Antigravity-box" --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "\$@"
else
    exec "$app_exec" --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "\$@"
fi
EOF

# Disable Antigravity telemetry (only when no settings exist yet)
if [ "$MODE" = "system" ]; then
    ensure_default_settings "/etc/skel/.config/Antigravity/User/settings.json"
    ensure_default_settings "/etc/skel/.config/Antigravity-box/User/settings.json"
else
    ensure_default_settings "$HOME/.config/Antigravity/User/settings.json"
fi


# --- 2. Antigravity IDE (Stable 1.23.2 Tarball) -------------------------------
step "Installing Antigravity IDE"
IDE_VERSION="1.23.2"
IDE_URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${IDE_VERSION}-4781536860569600/${IDE_ARCH}/Antigravity.tar.gz"
install_app_tarball "$IDE_URL" "$IDE_SHA256" "$SHARE_DIR/antigravity-ide"

ide_exec="$SHARE_DIR/antigravity-ide/antigravity"
write_file_atomic "$BIN_DIR/antigravity-ide" 0755 << EOF
#!/bin/bash
if [ -e /run/.containerenv ] || [ -e /run/.toolboxenv ]; then
    mkdir -p "\$HOME/.config/Antigravity-ide-box/User"
    if [ ! -f "\$HOME/.config/Antigravity-ide-box/User/settings.json" ]; then
        echo '{"antigravity.account.enableTelemetry": false, "antigravity.browser.chromeBinaryPath": "/usr/bin/google-chrome-stable", "window.titleBarStyle": "native"}' > "\$HOME/.config/Antigravity-ide-box/User/settings.json"
    elif command -v jq &>/dev/null; then
        jq '.["antigravity.browser.chromeBinaryPath"] = "/usr/bin/google-chrome-stable" | .["window.titleBarStyle"] = "native"' "\$HOME/.config/Antigravity-ide-box/User/settings.json" > "\$HOME/.config/Antigravity-ide-box/User/settings.json.tmp" && mv "\$HOME/.config/Antigravity-ide-box/User/settings.json.tmp" "\$HOME/.config/Antigravity-ide-box/User/settings.json"
    fi
    exec "$ide_exec" --user-data-dir "\$HOME/.config/Antigravity-ide-box" --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "\$@"
else
    exec "$ide_exec" --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "\$@"
fi
EOF

# Disable telemetry for IDE (only when no settings exist yet)
if [ "$MODE" = "system" ]; then
    ensure_default_settings "/etc/skel/.config/Antigravity-ide/User/settings.json"
    ensure_default_settings "/etc/skel/.config/Antigravity-ide-box/User/settings.json"
else
    ensure_default_settings "$HOME/.config/Antigravity-ide/User/settings.json"
fi


# --- 3. Antigravity CLI (1.0.0 Tarball) ---------------------------------------
step "Installing Antigravity CLI (agy)"
CLI_VERSION="1.0.0"
CLI_EXEC_ID="5288553236791296"
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
    PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx install --force google-adk==2.1.0
    PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin pipx inject google-adk google-antigravity==0.1.0
    # Enable system python3 to find the packages via .pth file
    for pydir in /usr/local/lib/python*/dist-packages /usr/lib/python*/dist-packages; do
        if [ -d "$pydir" ]; then
            for site in /opt/pipx/venvs/google-adk/lib/python*/site-packages; do
                if [ -d "$site" ]; then
                    echo "$site" > "$pydir/agy-toolchain.pth"
                fi
            done
        fi
    done
else
    step "Installing Antigravity SDK"
    pip3 install --user --break-system-packages --no-cache-dir --retries 10 google-antigravity==0.1.0

    step "Installing Google ADK"
    pip3 install --user --break-system-packages --no-cache-dir --retries 10 google-adk==2.1.0
fi


# --- 6. Gemini CLI ------------------------------------------------------------
step "Installing Gemini CLI"
if [ "$MODE" = "system" ]; then
    npm install -g --prefix /usr/local --omit=dev --no-audit --no-fund @google/gemini-cli@0.43.0
else
    npm install -g --prefix "$HOME/.local" --omit=dev --no-audit --no-fund @google/gemini-cli@0.43.0
fi


# --- 7. Visual Studio Code Antigravity Extension -----------------------------
if command -v code >/dev/null 2>&1; then
    step "Installing Antigravity extension for Visual Studio Code"
    if [ "$MODE" = "system" ]; then
        code --user-data-dir /tmp/vscode-root --extensions-dir /etc/skel/.vscode/extensions --install-extension Google.antigravity --force || true
        mkdir -p /root/.vscode
        cp -r /etc/skel/.vscode/extensions /root/.vscode/ 2>/dev/null || true
    else
        code --install-extension Google.antigravity --force || true
    fi
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
for bin in antigravity antigravity-ide agy adk gemini; do
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
