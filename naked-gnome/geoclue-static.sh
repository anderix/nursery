#!/usr/bin/env bash
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)

set -euo pipefail

STATIC=/etc/geoclue/static-source
DROPIN=/etc/geoclue/conf.d/90-static-source.conf

usage() {
    cat <<EOF
Usage: $0 [-y|--yes] [<latitude> <longitude> [<accuracy-m>]]

Gives a machine that does not move a fixed location through GeoClue, for every
location-aware app. A wired desktop has no other source: GeoClue's Wi-Fi source
needs a geolocation service URL, and none ships by default.

  no coordinates   print the current GeoClue setup and change nothing
  coordinates      decimal degrees, south and west negative; accuracy in
                   whole metres, default 100
  -y, --yes        apply every section without prompting

Run as your normal user; the steps that write /etc use sudo.
EOF
}

YES_TO_ALL=0
args=()
for arg in "$@"; do
    case "$arg" in
        -y|--yes) YES_TO_ALL=1 ;;
        -h|--help) usage; exit 0 ;;
        *) args+=("$arg") ;;
    esac
done

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user, not root."
    echo "Location Services is a per-user gsettings key; sudo is used where needed."
    exit 1
fi

installed() {
    dpkg-query -W -f='${Status}' geoclue-2.0 2>/dev/null | grep -q 'install ok installed'
}

report() {
    echo "=== GeoClue on $(hostname) ==="
    if installed; then
        echo "  geoclue-2.0:        $(dpkg-query -W -f='${Version}' geoclue-2.0)"
    else
        echo "  geoclue-2.0:        not installed"
    fi
    echo "  Location Services:  $(gsettings get org.gnome.system.location enabled 2>/dev/null || echo unknown)"
    if [[ -f $DROPIN ]]; then
        echo "  static source:      enabled by $DROPIN"
    else
        echo "  static source:      not enabled by this script"
    fi
    if [[ -r $STATIC ]]; then
        grep -v '^[[:space:]]*#' "$STATIC" | sed '/^[[:space:]]*$/d' | paste -sd' ' |
            awk -v f="$STATIC" '{printf "  %s: latitude %s, longitude %s, altitude %s m, accuracy %s m\n", f, $1, $2, $3, $4}'
    else
        echo "  $STATIC: absent"
    fi
}

if [[ ${#args[@]} -eq 0 ]]; then
    report
    exit 0
fi
if [[ ${#args[@]} -lt 2 || ${#args[@]} -gt 3 ]]; then
    usage >&2
    exit 1
fi

lat=${args[0]}
lon=${args[1]}
acc=${args[2]:-100}
number='^-?[0-9]+(\.[0-9]+)?$'
if ! [[ $lat =~ $number && $lon =~ $number && $acc =~ ^[0-9]+$ ]] ||
   ! awk -v a="$lat" -v o="$lon" 'BEGIN { exit !(a >= -90 && a <= 90 && o >= -180 && o <= 180) }'; then
    echo "Latitude must be -90..90, longitude -180..180, accuracy whole metres." >&2
    exit 1
fi

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

echo "=== Fixed GeoClue location: $lat, $lon (within $acc m) ==="

if ! installed; then
    echo ""
    echo "--- Install GeoClue ---"
    echo "  sudo apt install geoclue-2.0"
    if confirm; then
        sudo apt install -y geoclue-2.0
    fi
fi

echo ""
echo "--- Turn on Location Services ---"
echo "  Key: org.gnome.system.location enabled (Settings > Privacy > Location)"
if confirm; then
    gsettings set org.gnome.system.location enabled true
    echo "    set org.gnome.system.location enabled = true"
fi

echo ""
echo "--- Write the static source ---"
echo "  $STATIC: $lat, $lon, altitude 0, accuracy $acc m"
echo "  $DROPIN: [static-source] enable=true"
echo "  Then restarts geoclue."
if confirm; then
    sudo mkdir -p "$(dirname "$DROPIN")"
    printf '[static-source]\nenable=true\n' | sudo tee "$DROPIN" >/dev/null
    printf '%s\n%s\n0\n%s\n' "$lat" "$lon" "$acc" | sudo tee "$STATIC" >/dev/null
    sudo chmod 644 "$DROPIN" "$STATIC"
    sudo systemctl restart geoclue
    echo "    wrote $DROPIN and $STATIC, restarted geoclue"
fi

echo ""
report
echo ""
echo "GNOME Shell's location agent registers with GeoClue at login. If GeoClue"
echo "was installed during this session, log out and back in before apps can"
echo "get a location."
