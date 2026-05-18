#!/usr/bin/env bash
# review-autostart.sh
# Lists .desktop files in autostart locations with their effective status,
# display name, comment, and Exec line. Read-only — makes no changes.
#
# Autostart entries are how programs get launched at login outside of
# systemd user services. Packages don't tell you what runs at login;
# this script does.
#
# Locations scanned:
#   /etc/xdg/autostart/        (system-wide)
#   ~/.config/autostart/       (per-user; overrides system entries)
#
# Author: David Anderson (with AI assistance from Claude)

set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            echo "Usage: $0"
            echo "  Lists autostart .desktop entries with effective status."
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0" >&2
            exit 1
            ;;
    esac
done

LOCATIONS=(
    "/etc/xdg/autostart"
    "$HOME/.config/autostart"
)

CURRENT_DE="${XDG_CURRENT_DESKTOP:-}"

# Extract a key's value from the [Desktop Entry] section of a .desktop file.
# Returns the first match; ignores localized variants like Name[de]=.
get_key() {
    local file="$1" key="$2"
    awk -F= -v key="$key" '
        /^\[Desktop Entry\]/ { in_section=1; next }
        /^\[/                { in_section=0; next }
        in_section && $1 == key {
            sub(/^[^=]*=/, "")
            print
            exit
        }
    ' "$file"
}

# Decide whether a .desktop entry will actually autostart given the current DE.
# Returns one of: ENABLED, HIDDEN, GNOME-OFF, NOT-IN-DE, EXCLUDED.
status_of() {
    local file="$1"
    local hidden gnome_enabled only_show not_show

    hidden=$(get_key "$file" Hidden)
    gnome_enabled=$(get_key "$file" X-GNOME-Autostart-enabled)
    only_show=$(get_key "$file" OnlyShowIn)
    not_show=$(get_key "$file" NotShowIn)

    if [[ "$hidden" == "true" ]]; then
        echo "HIDDEN"
        return
    fi
    if [[ "$CURRENT_DE" == *GNOME* && "$gnome_enabled" == "false" ]]; then
        echo "GNOME-OFF"
        return
    fi
    if [[ -n "$only_show" ]]; then
        # OnlyShowIn is a ;-separated list; normalize for substring match.
        case ";${only_show%;};" in
            *";$CURRENT_DE;"*) : ;;
            *) echo "NOT-IN-DE"; return ;;
        esac
    fi
    if [[ -n "$not_show" ]]; then
        case ";${not_show%;};" in
            *";$CURRENT_DE;"*) echo "EXCLUDED"; return ;;
        esac
    fi
    echo "ENABLED"
}

echo "=== Autostart audit ==="
echo "Current DE: ${CURRENT_DE:-(none detected)}"

total=0
enabled=0

for dir in "${LOCATIONS[@]}"; do
    echo ""
    if [[ ! -d "$dir" ]]; then
        echo "--- $dir (not present) ---"
        continue
    fi

    shopt -s nullglob
    files=("$dir"/*.desktop)
    shopt -u nullglob

    if [[ ${#files[@]} -eq 0 ]]; then
        echo "--- $dir (empty) ---"
        continue
    fi

    echo "--- $dir ---"
    for f in "${files[@]}"; do
        name=$(get_key "$f" Name)
        comment=$(get_key "$f" Comment)
        exec_line=$(get_key "$f" Exec)
        status=$(status_of "$f")
        bn=$(basename "$f")

        total=$((total + 1))
        [[ "$status" == "ENABLED" ]] && enabled=$((enabled + 1))

        printf "[%-9s] %s\n" "$status" "$bn"
        [[ -n "$name" ]]      && printf "  Name:    %s\n" "$name"
        [[ -n "$comment" ]]   && printf "  Comment: %s\n" "$comment"
        [[ -n "$exec_line" ]] && printf "  Exec:    %s\n" "$exec_line"
        echo ""
    done
done

echo "=== Summary ==="
echo "Total entries: $total   Enabled: $enabled   Disabled: $((total - enabled))"
echo ""
echo "To disable a system entry, copy it to ~/.config/autostart/ and add:"
echo "  Hidden=true"
echo "To re-enable a system entry you previously hid, rm the user-level copy."
