#!/usr/bin/env bash
# audit-disk-junk.sh
# Reports disk space consumed by typical "junk" locations: caches, trash,
# logs, package archives, browser profiles, journal. Read-only — no changes.
#
# Use to find where disk creep is hiding before reaching for a cleaner.
# Each category includes a hint for how to clean it up by hand.
#
# Author: David Anderson (with AI assistance from Claude)

set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            echo "Usage: $0"
            echo "  Reports disk usage of common caches, logs, and temp dirs."
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0" >&2
            exit 1
            ;;
    esac
done

# Print a heading + indented `du -sh` output for one or more paths.
# Skips paths that don't exist. Sorts results by size descending.
audit_paths() {
    local heading="$1"; shift
    local existing=()
    for p in "$@"; do
        [[ -e "$p" ]] && existing+=("$p")
    done

    echo "--- $heading ---"
    if [[ ${#existing[@]} -eq 0 ]]; then
        echo "  (no paths present)"
        echo ""
        return
    fi

    # du can exit non-zero on permission-denied files (e.g. /var/log/private/);
    # under pipefail that would kill the script. Wrap with `|| true`.
    ( du -sh "${existing[@]}" 2>/dev/null || true ) \
        | sort -hr \
        | sed 's/^/  /'
    echo ""
}

echo "=== Disk junk audit ==="
echo ""
echo "Filesystem root:"
df -h / | awk 'NR==2 {printf "  %s used of %s (%s full)\n", $3, $2, $5}'
echo ""

# ---------------------------------------------------------------------------
audit_paths "User caches (~/.cache/*)" "$HOME"/.cache/*
echo "  Clean up:  rm -rf ~/.cache/<dirname>   (per app; safe to delete)"
echo ""

# ---------------------------------------------------------------------------
audit_paths "User trash" "$HOME/.local/share/Trash"
echo "  Clean up:  gio trash --empty           (or via Files app)"
echo ""

# ---------------------------------------------------------------------------
audit_paths "Browser profile caches" \
    "$HOME"/.mozilla/firefox/*/storage \
    "$HOME"/.mozilla/firefox/*/cache2 \
    "$HOME"/.cache/mozilla/firefox \
    "$HOME"/.config/chromium/Default/Cache \
    "$HOME"/.cache/chromium \
    "$HOME"/.cache/google-chrome
echo "  Clean up:  rm -rf the specific cache dir; browser rebuilds it"
echo ""

# ---------------------------------------------------------------------------
audit_paths "System logs (/var/log)" /var/log
echo "  Clean up:  sudo journalctl --vacuum-time=7d"
echo "             sudo find /var/log -type f -name '*.gz' -mtime +30 -delete"
echo ""

# ---------------------------------------------------------------------------
audit_paths "Journal (systemd)" /var/log/journal /run/log/journal
JOURNAL_DISK=$(journalctl --disk-usage 2>/dev/null | head -1)
if [[ -n "$JOURNAL_DISK" ]]; then
    echo "  journalctl: $JOURNAL_DISK"
fi
echo "  Clean up:  sudo journalctl --vacuum-size=200M"
echo ""

# ---------------------------------------------------------------------------
audit_paths "Package archives (/var/cache/apt)" /var/cache/apt/archives
echo "  Clean up:  sudo apt clean              (empties /var/cache/apt/archives)"
echo ""

# ---------------------------------------------------------------------------
audit_paths "Temp dirs" /tmp /var/tmp
echo "  Clean up:  reboot clears /tmp (tmpfs); /var/tmp persists"
echo ""

# ---------------------------------------------------------------------------
audit_paths "Snap (if installed)" /var/lib/snapd /snap
echo "  Clean up:  sudo snap remove --purge <old-snap>"
echo "             (or remove snapd entirely if you don't use it)"
echo ""

# ---------------------------------------------------------------------------
audit_paths "Flatpak (if installed)" /var/lib/flatpak "$HOME/.local/share/flatpak"
echo "  Clean up:  flatpak uninstall --unused"
echo ""

echo "=== Done! ==="
echo ""
echo "This is a snapshot. Re-run after any cleanup to see the impact."
