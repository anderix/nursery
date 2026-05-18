#!/bin/bash
# strip-gnome.sh
# Strips a fresh Debian 13 + GNOME install down to a clean dev environment.
# Keeps: GNOME desktop, Tweaks, Firefox, terminal, file manager, settings.
# Run as root or with sudo.
#
# Each section describes what it removes and asks before doing anything.
# Press Enter (or y) to remove, n to skip. Pass -y to remove everything
# without prompting.
#
# Author: David Anderson (with AI assistance from Claude)

set -euo pipefail

YES_TO_ALL=0
for arg in "$@"; do
    case "$arg" in
        -y|--yes) YES_TO_ALL=1 ;;
        -h|--help)
            echo "Usage: $0 [-y|--yes]"
            echo "  -y, --yes   Remove every section without prompting."
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

# Ask the user a yes/no question. Default = yes (Enter applies it).
# With -y, auto-confirms and prints a marker.
confirm() {
    if [[ $YES_TO_ALL -eq 1 ]]; then
        echo "  Remove? [Y/n] y  (-y)"
        return 0
    fi
    local reply
    read -rp "  Remove? [Y/n] " reply
    case "${reply,,}" in
        n|no) return 1 ;;
        *)    return 0 ;;
    esac
}

echo "=== Stripping Debian GNOME to essentials ==="
echo ""
echo "Each section will describe what it removes and ask before applying."
echo "Press Enter or 'y' to remove, 'n' to skip."

# ---------------------------------------------------------------------------
echo ""
echo "--- GNOME bloat apps ---"
echo "  baobab, gnome-backgrounds, gnome-bluetooth-sendto, gnome-calendar,"
echo "  gnome-characters, gnome-clocks, gnome-connections, gnome-console,"
echo "  gnome-contacts, gnome-font-viewer, gnome-logs, gnome-maps,"
echo "  gnome-music, gnome-photos, gnome-remote-desktop, gnome-snapshot,"
echo "  gnome-software, gnome-sound-recorder, gnome-tour, gnome-user-docs,"
echo "  gnome-user-share, gnome-weather, papers, ptyxis, showtime, tecla,"
echo "  totem, yelp, yelp-xsl"
if confirm; then
    apt remove -y \
        baobab \
        gnome-backgrounds \
        gnome-bluetooth-sendto \
        gnome-calendar \
        gnome-characters \
        gnome-clocks \
        gnome-connections \
        gnome-console \
        gnome-contacts \
        gnome-font-viewer \
        gnome-logs \
        gnome-maps \
        gnome-music \
        gnome-photos \
        gnome-remote-desktop \
        gnome-snapshot \
        gnome-software \
        gnome-sound-recorder \
        gnome-tour \
        gnome-user-docs \
        gnome-user-share \
        gnome-weather \
        papers \
        ptyxis \
        showtime \
        tecla \
        totem \
        yelp yelp-xsl \
        2>/dev/null || true
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Bundled applications ---"
echo "  evolution + evolution-data-server + evolution-plugins,"
echo "  libreoffice (all), seahorse, shotwell, simple-scan"
if confirm; then
    apt remove -y \
        evolution evolution-data-server evolution-plugins \
        libreoffice* \
        seahorse \
        shotwell \
        simple-scan \
        2>/dev/null || true
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Print system ---"
echo "  cups, cups-pk-helper, system-config-printer-common,"
echo "  system-config-printer-udev"
echo "  (Skip if you actually use a printer on this machine.)"
if confirm; then
    apt remove -y \
        cups cups-pk-helper \
        system-config-printer-common system-config-printer-udev \
        2>/dev/null || true
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Accessibility stack ---"
echo "  orca, speech-dispatcher (+ espeak-ng + audio plugins),"
echo "  espeak-ng-data, pocketsphinx-en-us"
echo "  (Skip if anyone using this machine needs screen reader / TTS.)"
if confirm; then
    apt remove -y \
        orca \
        speech-dispatcher speech-dispatcher-espeak-ng speech-dispatcher-audio-plugins \
        espeak-ng-data \
        pocketsphinx-en-us \
        2>/dev/null || true
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Network services not needed on a dev VM ---"
echo "  avahi-daemon (mDNS), samba-libs, rygel-playbin + rygel-tracker (DLNA),"
echo "  inetutils-telnet"
if confirm; then
    apt remove -y \
        avahi-daemon \
        samba-libs \
        rygel-playbin rygel-tracker \
        inetutils-telnet \
        2>/dev/null || true
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Docs and language bloat ---"
echo "  debian-faq, doc-debian, installation-report,"
echo "  hunspell-en-us, hyphen-en-us, mythes-en-us, locales-all"
if confirm; then
    apt remove -y \
        debian-faq doc-debian installation-report \
        hunspell-en-us hyphen-en-us mythes-en-us \
        locales-all \
        2>/dev/null || true
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Scanner support ---"
echo "  sane-utils, libsane1"
echo "  (Skip if you have a scanner.)"
if confirm; then
    apt remove -y \
        sane-utils libsane1 \
        2>/dev/null || true
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Misc ---"
echo "  nm-connection-editor (use Settings instead), malcontent (parental"
echo "  controls), ghostscript"
if confirm; then
    apt remove -y \
        nm-connection-editor \
        malcontent \
        ghostscript \
        2>/dev/null || true
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Clean up orphaned packages and apt cache ---"
echo "  Runs 'apt autoremove' (sweeps unused dependencies) and 'apt clean'"
echo "  (empties /var/cache/apt/archives)."
if confirm; then
    apt autoremove -y
    apt clean
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Leftover .desktop entries ---"
echo "  yelp, gnome-tour, nm-connection-editor, malcontent-control,"
echo "  ibus setup/panels, im-config"
echo "  (Removes them from the Activities/Apps menu.)"
if confirm; then
    for f in \
        yelp.desktop \
        org.gnome.Tour.desktop \
        nm-connection-editor.desktop \
        org.freedesktop.MalcontentControl.desktop \
        org.freedesktop.IBus.Setup.desktop \
        org.freedesktop.IBus.Panel.Extension.Gtk3.desktop \
        org.freedesktop.IBus.Panel.Wayland.Gtk3.desktop \
        org.freedesktop.IBus.Panel.Emojier.desktop \
        im-config.desktop \
    ; do
        rm -f "/usr/share/applications/$f"
    done
fi

# ---------------------------------------------------------------------------
echo ""
echo "--- Verifying essentials ---"
echo "  Checks that core desktop packages are still installed; reinstalls"
echo "  any that got accidentally swept up. (Always safe to run.)"
ESSENTIALS="gdm3 gnome-shell gnome-session gnome-settings-daemon gnome-control-center gnome-keyring gnome-terminal nautilus firefox-esr gnome-tweaks gnome-sushi gnome-calculator file-roller evince loupe gnome-text-editor gnome-system-monitor gnome-disk-utility network-manager"
MISSING=""
UNAVAILABLE=""
for pkg in $ESSENTIALS; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            MISSING="$MISSING $pkg"
        else
            UNAVAILABLE="$UNAVAILABLE $pkg"
        fi
    fi
done

if [[ -n "$UNAVAILABLE" ]]; then
    echo "  Skipping packages not in this Debian's repos:$UNAVAILABLE"
fi

if [[ -n "$MISSING" ]]; then
    echo "  Reinstalling packages that were accidentally removed:$MISSING"
    apt install -y $MISSING
else
    echo "  All essentials intact."
fi

echo ""
echo "=== Done! ==="
echo ""
df -h /
echo ""
echo "Reboot recommended to clear out any lingering processes."
