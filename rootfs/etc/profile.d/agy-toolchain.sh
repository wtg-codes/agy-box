# shellcheck shell=sh
# agy-box: /etc/profile.d/agy-toolchain.sh
# The Antigravity toolchain is installed per user into ~/.local by
# agy-install-toolchain (run by agy-box-manager install/dev/update-toolchain).
# Put ~/.local/bin on PATH for login shells, and hint if it is not installed.
# POSIX sh: /etc/profile may source this from sh as well as bash.

case ":${PATH}:" in
    *":${HOME}/.local/bin:"*) ;;
    *) PATH="${HOME}/.local/bin:${PATH}"; export PATH ;;
esac

if ! command -v agy >/dev/null 2>&1 && [ ! -x "${HOME}/.local/bin/agy" ]; then
    case "$-" in
        *i*)
            if [ -t 1 ]; then
                echo "agy-box: the Antigravity toolchain (agy, antigravity, antigravity-ide, SDK, ADK, gemini) is not installed."
                echo "         Install it with: agy-install-toolchain   (or on the host: agy-box-manager update-toolchain)"
            fi
            ;;
    esac
fi
