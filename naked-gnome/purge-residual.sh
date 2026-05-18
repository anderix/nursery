#!/usr/bin/env bash
# purge-residual.sh
# Purges packages in dpkg state 'rc' (removed but config files still around).
# Tiny disk impact — this is for tidiness, not space recovery.
#
# Lists the candidates first, then asks before purging. Pass -y to skip
# the prompt and purge everything.
#
# Author: David Anderson (with AI assistance from Claude)

set -euo pipefail

YES_TO_ALL=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) YES_TO_ALL=1 ;;
        -h|--help)
            echo "Usage: $0 [-y|--yes]"
            echo "  Purges packages left in state 'rc' (config files only)."
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [-y|--yes]" >&2
            exit 1
            ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)."
    exit 1
fi

confirm() {
    if [[ $YES_TO_ALL -eq 1 ]]; then
        echo "  Purge? [Y/n] y  (-y)"
        return 0
    fi
    local reply
    read -rp "  Purge? [Y/n] " reply
    case "${reply,,}" in
        n|no) return 1 ;;
        *)    return 0 ;;
    esac
}

echo "=== Residual config purge ==="
echo ""

# Find packages in state 'rc' (removed, config still installed).
RC_PKGS=$(dpkg -l 2>/dev/null | awk '/^rc/ {print $2}' | sort)

if [[ -z "$RC_PKGS" ]]; then
    echo "No residual config-only packages found. System is tidy."
    exit 0
fi

count=$(echo "$RC_PKGS" | wc -l)

echo "--- Packages in state 'rc' (config files only) ---"
echo "$RC_PKGS" | sed 's/^/  /'
echo ""
echo "  ($count package(s))"
echo ""
echo "These packages were removed (apt remove) but their config files in"
echo "/etc/ were preserved. Purging deletes those config files."

if confirm; then
    # shellcheck disable=SC2086
    dpkg --purge $RC_PKGS
    echo ""
    echo "Done. Purged $count package(s)."
else
    echo "Skipped."
fi
