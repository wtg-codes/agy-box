#!/bin/bash
# ==============================================================================
# agy-install-toolchain  (source: scripts/install-agent-toolchain.sh)
#
# Installs or updates the Antigravity agent toolchain for the CURRENT user into
# $HOME/.local. The toolchain is intentionally NOT baked into the image
# (component separation, #19); this installer is shipped in the image as
# /usr/local/bin/agy-install-toolchain and is run inside the box by
# `agy-box-manager install`, `agy-box-manager dev` and
# `agy-box-manager update-toolchain`:
#
#     distrobox enter <box> -- agy-install-toolchain
#
# It installs (all versions pinned, downloads verified by checksum):
#   - Google Antigravity (Agent UI)  ~/.local/bin/antigravity     (+ ~/.local/share/antigravity)
#   - Antigravity IDE                ~/.local/bin/antigravity-ide (+ ~/.local/share/antigravity-ide)
#   - Antigravity CLI                ~/.local/bin/agy
#   - Antigravity SDK                pip --user google-antigravity
#   - Google ADK                     pip --user google-adk        (~/.local/bin/adk)
#   - Gemini CLI                     npm --prefix ~/.local        (~/.local/bin/gemini)
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
Usage: ${PROG} [-h|--help]

Install or update the Antigravity agent toolchain (Agent UI, IDE, agy CLI,
SDK, ADK, Gemini CLI) for the current user into \$HOME/.local.
Run it as your normal (non-root) user inside the agy-box. Safe to re-run.
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    "") ;;
    *) echo "${PROG}: unknown argument: $1" >&2; usage >&2; exit 2 ;;
esac

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
if [ "$(id -u)" -eq 0 ]; then
    die "do not run as root; run as your normal user inside the box (installs into \$HOME/.local)."
fi
if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ] || [ ! -w "$HOME" ]; then
    die "HOME ('${HOME:-}') is not set or not a writable directory."
fi
arch="$(uname -m)"
if [ "$arch" != "x86_64" ]; then
    die "unsupported architecture '${arch}': the Antigravity downloads are linux-x64 only."
fi
for cmd in curl tar sha256sum sha512sum python3 pip3 npm; do
    command -v "$cmd" >/dev/null 2>&1 || die "required command '${cmd}' not found in PATH."
done

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

BIN_DIR="$HOME/.local/bin"
SHARE_DIR="$HOME/.local/share"
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
IDE_URL="https://storage.googleapis.com/antigravity-public/antigravity-hub/${IDE_VERSION}-${IDE_EXEC_ID}/linux-x64/Antigravity.tar.gz"
IDE_SHA256="0727e1f56961b6d2347941f278da69cc6c17de3befe988524848cd167380e9ab"
install_app_tarball "$IDE_URL" "$IDE_SHA256" "$SHARE_DIR/antigravity"

write_file_atomic "$BIN_DIR/antigravity" 0755 << 'EOF'
#!/bin/bash
if [ -e /run/.containerenv ] || [ -e /run/.toolboxenv ]; then
    mkdir -p "$HOME/.config/Antigravity-box/User"
    if [ ! -f "$HOME/.config/Antigravity-box/User/settings.json" ]; then
        echo '{"antigravity.account.enableTelemetry": false, "antigravity.browser.chromeBinaryPath": "/usr/bin/google-chrome-stable", "window.titleBarStyle": "native"}' > "$HOME/.config/Antigravity-box/User/settings.json"
    elif command -v jq &>/dev/null; then
        jq '.["antigravity.browser.chromeBinaryPath"] = "/usr/bin/google-chrome-stable" | .["window.titleBarStyle"] = "native"' "$HOME/.config/Antigravity-box/User/settings.json" > "$HOME/.config/Antigravity-box/User/settings.json.tmp" && mv "$HOME/.config/Antigravity-box/User/settings.json.tmp" "$HOME/.config/Antigravity-box/User/settings.json"
    fi
    exec "$HOME/.local/share/antigravity/antigravity" --user-data-dir "$HOME/.config/Antigravity-box" --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "$@"
else
    exec "$HOME/.local/share/antigravity/antigravity" --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "$@"
fi
EOF

# Disable Antigravity telemetry (only when no settings exist yet)
ensure_default_settings "$HOME/.config/Antigravity/User/settings.json"


# --- 2. Antigravity IDE (Stable 1.23.2 Tarball) -------------------------------
step "Installing Antigravity IDE"
IDE_VERSION="1.23.2"
IDE_URL="https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/stable/${IDE_VERSION}-4781536860569600/linux-x64/Antigravity.tar.gz"
IDE_SHA256="5232a4048ff4fa15685d9a981ba4fba573e297f3efc9b76f638e794baf775725"
install_app_tarball "$IDE_URL" "$IDE_SHA256" "$SHARE_DIR/antigravity-ide"

write_file_atomic "$BIN_DIR/antigravity-ide" 0755 << 'EOF'
#!/bin/bash
if [ -e /run/.containerenv ] || [ -e /run/.toolboxenv ]; then
    mkdir -p "$HOME/.config/Antigravity-ide-box/User"
    if [ ! -f "$HOME/.config/Antigravity-ide-box/User/settings.json" ]; then
        echo '{"antigravity.account.enableTelemetry": false, "antigravity.browser.chromeBinaryPath": "/usr/bin/google-chrome-stable", "window.titleBarStyle": "native"}' > "$HOME/.config/Antigravity-ide-box/User/settings.json"
    elif command -v jq &>/dev/null; then
        jq '.["antigravity.browser.chromeBinaryPath"] = "/usr/bin/google-chrome-stable" | .["window.titleBarStyle"] = "native"' "$HOME/.config/Antigravity-ide-box/User/settings.json" > "$HOME/.config/Antigravity-ide-box/User/settings.json.tmp" && mv "$HOME/.config/Antigravity-ide-box/User/settings.json.tmp" "$HOME/.config/Antigravity-ide-box/User/settings.json"
    fi
    exec "$HOME/.local/share/antigravity-ide/antigravity" --user-data-dir "$HOME/.config/Antigravity-ide-box" --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "$@"
else
    exec "$HOME/.local/share/antigravity-ide/antigravity" --disable-dev-shm-usage --disable-gpu --disable-crash-reporter --no-sandbox "$@"
fi
EOF

# Disable telemetry for IDE (only when no settings exist yet)
ensure_default_settings "$HOME/.config/Antigravity-ide/User/settings.json"


# --- 3. Antigravity CLI (1.0.0 Tarball) ---------------------------------------
step "Installing Antigravity CLI (agy)"
CLI_VERSION="1.0.0"
CLI_EXEC_ID="5288553236791296"
CLI_URL="https://storage.googleapis.com/antigravity-public/antigravity-cli/${CLI_VERSION}-${CLI_EXEC_ID}/linux-x64/cli_linux_x64.tar.gz"
CLI_SHA512="5ccdcc01fb863c7e8e56473c6c95dba75fed4fd2a242200d80cfc4c7fab811b733f5a7fab25332130aad298e72627e1018e6911a5658f4f059ef6e019f211972"

download_verify "$CLI_URL" sha512 "$CLI_SHA512" "$WORK_DIR/cli_linux_x64.tar.gz"
tar -xzf "$WORK_DIR/cli_linux_x64.tar.gz" -C "$WORK_DIR" antigravity
# Copy next to the target and rename, so a running agy is replaced atomically.
cp "$WORK_DIR/antigravity" "$BIN_DIR/agy.new"
chmod 0755 "$BIN_DIR/agy.new"
mv -f "$BIN_DIR/agy.new" "$BIN_DIR/agy"


# --- 4. Antigravity SDK (google-antigravity) ----------------------------------
step "Installing Antigravity SDK"
pip3 install --user --break-system-packages --no-cache-dir --retries 10 google-antigravity==0.1.0


# --- 5. Google ADK ------------------------------------------------------------
step "Installing Google ADK"
pip3 install --user --break-system-packages --no-cache-dir --retries 10 google-adk==2.1.0


# --- 6. Gemini CLI ------------------------------------------------------------
step "Installing Gemini CLI"
npm install -g --prefix "$HOME/.local" --omit=dev --no-audit --no-fund @google/gemini-cli@0.43.0


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

echo "Agent toolchain installed successfully at user level ($BIN_DIR)."
case ":${PATH}:" in
    *":$BIN_DIR:"*) ;;
    *) echo "Note: $BIN_DIR is not on your PATH in this shell; open a new login shell (or run: export PATH=\"$BIN_DIR:\$PATH\")." ;;
esac
