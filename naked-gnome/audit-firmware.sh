#!/usr/bin/env bash
# audit-firmware.sh
# Audits installed firmware-* and microcode packages, cross-referencing each
# package's firmware paths against the currently-loaded kernel modules and
# the CPU vendor. Flags packages whose drivers don't appear to be loaded.
# Read-only — makes no changes.
#
# Heuristic: Each firmware-* package installs blobs under top-level subdirs
# of /usr/lib/firmware/ (or /lib/firmware/ on older Debian) named after the
# driver that consumes them — e.g. firmware-iwlwifi → iwlwifi/. If a matching
# module shows up in `lsmod`, the firmware is being used.
#
# Caveats: drivers can load firmware on demand (e.g. plug in a USB wifi
# adapter mid-session) and won't show in lsmod beforehand. Treat UNUSED
# as "no evidence on this boot", not proof. Verify each candidate by hand
# before removing.
#
# Author: David Anderson (with AI assistance from Claude)

set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        -h|--help)
            echo "Usage: $0"
            echo "  Audits installed firmware/microcode packages against lsmod."
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0" >&2
            exit 1
            ;;
    esac
done

# Build a set of "drivers in use" from both lsmod (loaded modules) and
# `lspci -k` (which catches built-in drivers compiled into the kernel).
LSMOD_NAMES=$(lsmod 2>/dev/null | awk 'NR>1 {print $1}' || true)
LSPCI_NAMES=$(lspci -k 2>/dev/null \
    | awk -F': ' '/Kernel driver in use/ {print $2}' || true)
LOADED_MODULES=$(printf '%s\n%s\n' "$LSMOD_NAMES" "$LSPCI_NAMES" \
    | grep -v '^$' | sort -u)
CPU_VENDOR=$(awk -F: '/vendor_id/ {gsub(/ /, "", $2); print $2; exit}' /proc/cpuinfo)

# Find installed firmware/microcode packages.
PKGS=$(dpkg-query -W -f='${db:Status-Abbrev}\t${Installed-Size}\t${Package}\t${binary:Summary}\n' 2>/dev/null \
    | awk -F'\t' '
        $1 ~ /^ii/ && ($3 ~ /^firmware-/ || $3 ~ /microcode$/ || $3 ~ /-firmware$/) {
            print $2 "\t" $3 "\t" $4
        }' \
    | sort -k1,1 -rn)

echo "=== Firmware audit ==="
echo ""
echo "CPU vendor: ${CPU_VENDOR:-unknown}"
echo "Loaded modules: $(echo "$LOADED_MODULES" | wc -l)"
echo ""

if [[ -z "$PKGS" ]]; then
    echo "--- No firmware/microcode packages installed ---"
    echo ""
    echo "Nothing to audit. This is normal on systems with no proprietary"
    echo "blobs needed (modern Intel iGPU + Ethernet often Just Works)."
    exit 0
fi

# Format a kB value as a human-readable size.
fmt_size() {
    local kb="$1"
    if [[ $kb -ge 10240 ]]; then
        printf "%dM" $((kb / 1024))
    elif [[ $kb -ge 1024 ]]; then
        awk -v kb="$kb" 'BEGIN { printf "%.1fM", kb/1024 }'
    else
        printf "%dK" "$kb"
    fi
}

# Check whether a microcode package is in use, based on CPU vendor.
microcode_status() {
    local pkg="$1"
    case "$pkg" in
        intel-microcode)
            [[ "$CPU_VENDOR" == "GenuineIntel" ]] && echo "LOADED" || echo "UNUSED"
            ;;
        amd64-microcode)
            [[ "$CPU_VENDOR" == "AuthenticAMD" ]] && echo "LOADED" || echo "UNUSED"
            ;;
        *)
            echo "UNKNOWN"
            ;;
    esac
}

echo "--- Installed firmware/microcode packages ---"
echo ""

total_kb=0
unused_count=0
loaded_count=0

while IFS=$'\t' read -r size_kb pkg summary; do
    [[ -z "$pkg" ]] && continue
    total_kb=$((total_kb + size_kb))

    status=""
    matched_modules=""

    if [[ "$pkg" == *microcode* ]]; then
        status=$(microcode_status "$pkg")
    else
        # Extract top-level subdirs under /lib/firmware/ that this package
        # populates. These typically match driver/module names.
        subdirs=$(dpkg -L "$pkg" 2>/dev/null \
            | grep -E '/(usr/)?lib/firmware/[^/]+/?$' \
            | sed -E 's@^/(usr/)?lib/firmware/@@; s@/$@@' \
            | grep -v '^$' \
            | sort -u || true)

        if [[ -z "$subdirs" ]]; then
            status="NO-FILES"
        else
            for sub in $subdirs; do
                # Direct match (e.g. iwlwifi/, amdgpu/)
                if printf '%s\n' "$LOADED_MODULES" | grep -qxF "$sub"; then
                    matched_modules="$matched_modules $sub"
                    continue
                fi
                # Prefix match (e.g. rtw88/ → rtw88_pci module)
                if printf '%s\n' "$LOADED_MODULES" | grep -q "^${sub}_\|^${sub}-"; then
                    matched_modules="$matched_modules ${sub}*"
                    continue
                fi
                # Common suffix stripping (rtl_nic → rtl, ath9k_htc → ath9k)
                stripped="${sub%_nic}"
                stripped="${stripped%-ucode}"
                if [[ "$stripped" != "$sub" ]] \
                    && printf '%s\n' "$LOADED_MODULES" | grep -q "^${stripped}"; then
                    matched_modules="$matched_modules ${stripped}*"
                fi
            done

            if [[ -n "$matched_modules" ]]; then
                status="LOADED"
            else
                status="UNUSED"
            fi
        fi
    fi

    if [[ "$status" == "LOADED" ]]; then
        loaded_count=$((loaded_count + 1))
    else
        unused_count=$((unused_count + 1))
    fi

    printf "[%-8s] %6s  %-30s  %s\n" "$status" "$(fmt_size "$size_kb")" "$pkg" "$summary"
    if [[ -n "$matched_modules" ]]; then
        echo "    drivers loaded:$matched_modules"
    fi
done <<< "$PKGS"

echo ""
echo "--- Summary ---"
echo "  Total: $(fmt_size "$total_kb") across $((loaded_count + unused_count)) packages"
echo "  Loaded:                          $loaded_count"
echo "  Unused / no evidence:            $unused_count"
echo ""
echo "Before removing an UNUSED package, double-check it's not for a device"
echo "that loads firmware on demand (USB wifi, hot-plug GPU, audio DSPs)."
echo "lsmod shows what's loaded right now — driver may load later."
