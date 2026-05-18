#!/usr/bin/env bash
# review-services.sh
# Lists enabled systemd units (services + timers) for both system and user
# scope, annotated with each unit's Description=. Read-only — no changes.
#
# Use to spot background work you don't need: apt-daily, fwupd-refresh,
# plocate, man-db, gsd-* per-subsystem daemons, etc.
#
# Author: David Anderson (with AI assistance from Claude)

set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            echo "Usage: $0"
            echo "  Lists enabled systemd services and timers (system + user)."
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0" >&2
            exit 1
            ;;
    esac
done

# Print enabled units of a given type within a given scope.
# Usage: list_enabled system service
#        list_enabled user   timer
list_enabled() {
    local scope="$1" type="$2"
    local scope_arg=""
    [[ "$scope" == "user" ]] && scope_arg="--user"

    local units
    # systemctl exits 1 when no units match the filter; with pipefail that
    # kills the script. The `|| true` swallows the empty-result exit.
    units=$( (systemctl $scope_arg list-unit-files --type="$type" \
                --state=enabled --no-legend 2>/dev/null || true) \
              | awk '{print $1}')

    if [[ -z "$units" ]]; then
        echo "  (none enabled)"
        return
    fi

    local count=0
    while IFS= read -r unit; do
        [[ -z "$unit" ]] && continue
        local desc
        # Template units (foo@.service) can't be queried without an instance;
        # systemctl show returns non-zero. Label them and skip the call.
        if [[ "$unit" == *@.service || "$unit" == *@.timer ]]; then
            desc="(template — instances vary)"
        else
            desc=$(systemctl $scope_arg show "$unit" -p Description --value 2>/dev/null || true)
        fi
        printf "  %-55s %s\n" "$unit" "${desc:--}"
        count=$((count + 1))
    done <<< "$units"

    echo ""
    echo "  ($count enabled)"
}

echo "=== systemd enabled units ==="
echo ""

echo "--- System services ---"
list_enabled system service
echo ""

echo "--- System timers ---"
list_enabled system timer
echo ""

if systemctl --user list-unit-files --no-legend >/dev/null 2>&1; then
    echo "--- User services ---"
    list_enabled user service
    echo ""

    echo "--- User timers ---"
    list_enabled user timer
    echo ""
else
    echo "--- User scope ---"
    echo "  (systemd --user not available; skipping)"
    echo ""
fi

echo "=== Hints ==="
echo "  Disable system unit:  sudo systemctl disable <unit>"
echo "  Mask system unit:     sudo systemctl mask <unit>"
echo "  Disable user unit:    systemctl --user disable <unit>"
echo "  Mask user unit:       systemctl --user mask <unit>"
echo "  See next timer runs:  systemctl list-timers --all"
