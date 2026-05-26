# Check if setup has already been marked as done
if [ ! -f "$HOME/.config/agy-box/.setup_done" ]; then
    # Only run in interactive, tty-connected shell sessions
    case "$-" in
        *i*)
            if [ -t 0 ] && [ -t 1 ]; then
                if [ -x /usr/local/bin/agy-setup-helper ]; then
                    /usr/local/bin/agy-setup-helper
                fi
            fi
            ;;
    esac
fi
