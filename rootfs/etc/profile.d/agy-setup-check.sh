# Load and export environment variables defined in environment.d
if [ -d "$HOME/.config/environment.d" ]; then
    for conf in "$HOME/.config/environment.d"/*.conf; do
        if [ -f "$conf" ]; then
            while IFS= read -r line || [ -n "$line" ]; do
                # Ignore comments, empty lines, and lines without =
                if [[ ! "$line" =~ ^[[:space:]]*# ]] && [[ "$line" =~ = ]]; then
                    key=$(echo "$line" | cut -d= -f1 | xargs)
                    val=$(echo "$line" | cut -d= -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//')
                    export "$key"="$val"
                fi
            done < "$conf"
        fi
    done
fi

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

