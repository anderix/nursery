#!/usr/bin/env bash
# slim-gsettings.sh
# Applies opinionated GNOME runtime settings for a snappier, leaner desktop.
# Targets Debian 13 + GNOME; defensive against older releases.
# Run as your normal user, NOT root — gsettings is per-user.
#
# Reversible: every change is a gsettings write, undone by `gsettings reset`
# or by re-running with different values.
#
# Each section asks before doing anything. Press Enter (or y) to apply,
# n to skip. Pass -y to apply everything without prompting.
#
# Author: David Anderson (with AI assistance from Claude)

set -euo pipefail

YES_TO_ALL=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) YES_TO_ALL=1 ;;
        -h|--help)
            echo "Usage: $0 [-y|--yes]"
            echo "  -y, --yes   Apply every section without prompting."
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [-y|--yes]" >&2
            exit 1
            ;;
    esac
done

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not root."
    echo "gsettings writes to your per-user dconf database."
    exit 1
fi

# Ask the user a yes/no question. Default = yes (Enter applies it).
# With -y, auto-confirms and prints a marker.
confirm() {
    if [[ $YES_TO_ALL -eq 1 ]]; then
        echo "  Apply? [Y/n] y  (-y)"
        return 0
    fi
    local reply
    read -rp "  Apply? [Y/n] " reply
    case "${reply,,}" in
        n|no) return 1 ;;
        *)    return 0 ;;
    esac
}

# Set a gsettings key only if the schema and key exist on this system.
# Avoids errors on older Debian where some schemas/keys don't exist yet.
set_if_writable() {
    local schema="$1" key="$2" value="$3"
    if gsettings writable "$schema" "$key" >/dev/null 2>&1; then
        gsettings set "$schema" "$key" "$value"
        echo "    set $schema $key = $value"
    else
        echo "    skip $schema $key (not on this system)"
    fi
}

echo "=== Slimming GNOME runtime settings ==="
echo ""
echo "Each section will describe what it does and ask before applying."
echo "Press Enter or 'y' to apply, 'n' to skip."

# ---------------------------------------------------------------------------
echo ""
echo "--- Disable animations ---"
echo "  Single biggest perceived-speed win, especially on slow hardware."
echo "  Keys: org.gnome.desktop.interface enable-animations"
if confirm; then
    set_if_writable org.gnome.desktop.interface enable-animations false
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Disable recent-files history ---"
echo "  Stops GNOME from tracking which files/apps you've used."
echo "  Privacy win + minor I/O reduction."
echo "  Keys: org.gnome.desktop.privacy remember-recent-files,"
echo "        remember-app-usage, recent-files-max-age"
if confirm; then
    set_if_writable org.gnome.desktop.privacy remember-recent-files false
    set_if_writable org.gnome.desktop.privacy remember-app-usage false
    set_if_writable org.gnome.desktop.privacy recent-files-max-age 0
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Disable auto-mount of removable media ---"
echo "  USB sticks won't auto-mount in nautilus; you'd mount manually"
echo "  via the sidebar or 'udisksctl mount'. Less convenience, less surface."
echo "  Keys: org.gnome.desktop.media-handling automount, automount-open,"
echo "        autorun-never"
if confirm; then
    set_if_writable org.gnome.desktop.media-handling automount false
    set_if_writable org.gnome.desktop.media-handling automount-open false
    set_if_writable org.gnome.desktop.media-handling autorun-never true
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Tame tracker indexer ---"
echo "  Tracker is the #1 background CPU eater on default GNOME."
echo "  Empties the index list (Tracker 2.x and 3.x) AND masks the user"
echo "  services so it doesn't spin back up. Only nautilus full-text search"
echo "  uses it; everything else still works fine."
if confirm; then
    set_if_writable org.freedesktop.Tracker3.Miner.Files index-recursive-directories "@as []"
    set_if_writable org.freedesktop.Tracker3.Miner.Files index-single-directories "@as []"
    set_if_writable org.freedesktop.Tracker.Miner.Files index-recursive-directories "@as []"
    set_if_writable org.freedesktop.Tracker.Miner.Files index-single-directories "@as []"

    for unit in \
        tracker-miner-fs-3.service \
        tracker-miner-fs-control-3.service \
        tracker-extract-3.service \
        tracker-writeback-3.service \
        tracker-store.service \
        tracker-miner-fs.service \
        tracker-extract.service \
    ; do
        if systemctl --user list-unit-files "$unit" >/dev/null 2>&1; then
            systemctl --user mask "$unit" 2>/dev/null && echo "    masked $unit" || true
        fi
    done

    tracker3 daemon --terminate >/dev/null 2>&1 || true
    tracker daemon --terminate >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Quiet gnome-software notifications ---"
echo "  Stops the 'updates available' nags and background download checks."
echo "  Harmless to apply even if gnome-software is uninstalled."
echo "  Keys: org.gnome.software download-updates, download-updates-notify,"
echo "        show-upgrade-notifications"
if confirm; then
    set_if_writable org.gnome.software download-updates false
    set_if_writable org.gnome.software download-updates-notify false
    set_if_writable org.gnome.software show-upgrade-notifications false
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Disable hot corner ---"
echo "  Stops the top-left hot corner from triggering activities overview."
echo "  Helps when you bump it accidentally; activities still works via Super."
echo "  Keys: org.gnome.desktop.interface enable-hot-corners"
if confirm; then
    set_if_writable org.gnome.desktop.interface enable-hot-corners false
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Detach modal dialogs from parent windows ---"
echo "  Modal dialogs become free-floating instead of attached to the parent."
echo "  Faster to render, easier to move out of the way."
echo "  Keys: org.gnome.mutter attach-modal-dialogs"
if confirm; then
    set_if_writable org.gnome.mutter attach-modal-dialogs false
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Switch to fixed workspaces (4 by default) ---"
echo "  Default GNOME uses elastic 'add a workspace when needed' behavior."
echo "  Some users prefer a fixed count for predictability."
echo "  (Skip this if you like the elastic add-on-demand behavior.)"
echo "  Keys: org.gnome.mutter dynamic-workspaces"
if confirm; then
    set_if_writable org.gnome.mutter dynamic-workspaces false
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Cap thumbnail cache ---"
echo "  Limits ~/.cache/thumbnails to 30 days / 64 MB instead of unbounded."
echo "  Keys: org.gnome.desktop.thumbnail-cache maximum-age, maximum-size"
if confirm; then
    set_if_writable org.gnome.desktop.thumbnail-cache maximum-age 30
    set_if_writable org.gnome.desktop.thumbnail-cache maximum-size 64
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Trim nautilus thumbnail behavior ---"
echo "  Local-only thumbnails (skip remote mounts) + 10 MB per-file limit."
echo "  Speeds up nautilus over WebDAV/SMB/SSHFS dramatically."
echo "  Keys: org.gnome.nautilus.preferences show-image-thumbnails,"
echo "        thumbnail-limit"
if confirm; then
    set_if_writable org.gnome.nautilus.preferences show-image-thumbnails "'local-only'"
    set_if_writable org.gnome.nautilus.preferences thumbnail-limit 10
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Done! ==="
echo ""
echo "Most changes apply immediately. A few (animations, mutter) need a"
echo "shell restart: Alt+F2, type 'r', press Enter (Xorg only) — or log out"
echo "and back in (Wayland)."
echo ""
echo "To undo any single change: gsettings reset <schema> <key>"
echo "To undo everything in a schema: gsettings reset-recursively <schema>"
