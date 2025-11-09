
#!/usr/bin/env bash
#
# Standalone Fastfetch logo helper
# Uses logos from ~/.config/fastfetch/logo

CONFIG_DIR="$HOME/.config/fastfetch"
LOGO_DIR="$CONFIG_DIR/logo"

usage() {
    cat <<USAGE
Usage: fastfetch.sh [command]

Commands:
  logo     Display a random logo or specific type
  help     Show this help message

Examples:
  fastfetch.sh logo
  fastfetch.sh logo --rand
  fastfetch.sh logo --local
  fastfetch.sh logo --prof
USAGE
}

random_logo() {
    find -L "$LOGO_DIR" -maxdepth 1 -type f \
        \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.icon" -o -name "*logo*" \) \
        2>/dev/null | shuf -n 1
}

logo_command() {
    shift
    local image_list=()

    # If no arguments or --rand, just pick random
    if [ -z "$1" ] || [[ "$1" == "--rand" ]]; then
        random_logo
        return
    fi

    # If --prof, use ~/.face.icon if present
    if [[ " $* " == *" --prof "* ]] && [ -f "$HOME/.face.icon" ]; then
        image_list+=("$HOME/.face.icon")
    fi

    # If --local, include all local logos
    if [[ " $* " == *" --local "* ]]; then
        image_list+=("$LOGO_DIR")
    fi

    # If no specific matches, fallback to all logos
    if [ ${#image_list[@]} -eq 0 ]; then
        image_list+=("$LOGO_DIR")
    fi

    find -L "${image_list[@]}" -maxdepth 1 -type f \
        \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.icon" -o -name "*logo*" \) \
        2>/dev/null | shuf -n 1
}

main() {
    case "$1" in
        logo)
            logo_command "$@"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            # Default behavior – show fastfetch with kitty logo support
            clear
            exec fastfetch --logo-type kitty
            ;;
    esac
}

main "$@"
