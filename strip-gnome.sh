#!/bin/bash
# strip-gnome.sh
# Strips a fresh Debian 13 + GNOME install down to a clean dev environment.
# Keeps: GNOME desktop, Tweaks, Firefox, terminal, file manager, settings.
# Run as root or with sudo.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (use sudo)."
    exit 1
fi

echo "=== Stripping Debian GNOME to essentials ==="
echo ""

# Step 1: Remove bloat apps first, while meta-packages still protect the desktop.
# This avoids the problem where removing meta-packages first causes autoremove
# to sweep up essential desktop components.
echo "--- Removing GNOME bloat apps ---"
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

# Step 2: Remove bundled applications
echo ""
echo "--- Removing bundled applications ---"
apt remove -y \
    evolution evolution-data-server evolution-plugins \
    libreoffice* \
    seahorse \
    shotwell \
    simple-scan \
    2>/dev/null || true

# Step 3: Remove printing
echo ""
echo "--- Removing print system ---"
apt remove -y \
    cups cups-pk-helper \
    system-config-printer-common system-config-printer-udev \
    2>/dev/null || true

# Step 4: Remove accessibility stack
echo ""
echo "--- Removing accessibility stack ---"
apt remove -y \
    orca \
    speech-dispatcher speech-dispatcher-espeak-ng speech-dispatcher-audio-plugins \
    espeak-ng-data \
    pocketsphinx-en-us \
    2>/dev/null || true

# Step 5: Remove network services not needed on a dev VM
echo ""
echo "--- Removing unnecessary network services ---"
apt remove -y \
    avahi-daemon \
    samba-libs \
    rygel-playbin rygel-tracker \
    inetutils-telnet \
    2>/dev/null || true

# Step 6: Remove unnecessary docs and language data
echo ""
echo "--- Removing docs and language bloat ---"
apt remove -y \
    debian-faq doc-debian installation-report \
    hunspell-en-us hyphen-en-us mythes-en-us \
    locales-all \
    2>/dev/null || true

# Step 7: Remove scanner libs
echo ""
echo "--- Removing scanner support ---"
apt remove -y \
    sane-utils libsane1 \
    2>/dev/null || true

# Step 8: Remove misc
echo ""
echo "--- Removing misc ---"
apt remove -y \
    nm-connection-editor \
    malcontent \
    ghostscript \
    2>/dev/null || true

# Step 9: Clean up orphaned packages and apt cache
echo ""
echo "--- Cleaning up orphaned packages and apt cache ---"
apt autoremove -y
apt clean

# Step 12: Remove leftover .desktop files that linger in the dash
echo ""
echo "--- Removing leftover .desktop entries ---"
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

# Step 13: Verify essentials are still installed, reinstall if needed
echo ""
echo "--- Verifying essentials ---"
ESSENTIALS="gdm3 gnome-shell gnome-session gnome-settings-daemon gnome-control-center gnome-keyring gnome-terminal nautilus firefox-esr gnome-tweaks gnome-sushi gnome-calculator file-roller evince loupe gnome-text-editor gnome-system-monitor gnome-disk-utility network-manager"
MISSING=""
for pkg in $ESSENTIALS; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        MISSING="$MISSING $pkg"
    fi
done

if [[ -n "$MISSING" ]]; then
    echo "Reinstalling packages that were accidentally removed:$MISSING"
    apt install -y $MISSING
else
    echo "All essentials intact."
fi

echo ""
echo "=== Done! ==="
echo ""
df -h /
echo ""
echo "Reboot recommended to clear out any lingering processes."
