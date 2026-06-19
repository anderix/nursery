#!/usr/bin/env bash
# gen-vm-launchers — create one desktop launcher per VM on a remote libvirt host.
#
# Run this on a CLIENT machine (one you sit at). It queries the remote host's
# user-session libvirt over SSH and drops a .desktop file per VM into
# ~/.local/share/applications, so every VM shows up in your app grid.
#
# Usage: gen-vm-launchers [USER@HOST]
#   With no argument it uses $BOXES_REMOTE_HOST; pass USER@HOST to override.

set -euo pipefail

conn_host="${1:-${BOXES_REMOTE_HOST:-}}"
[ -n "$conn_host" ] || { echo "usage: gen-vm-launchers USER@HOST  (or set BOXES_REMOTE_HOST)" >&2; exit 1; }
uri="qemu+ssh://${conn_host}/session"
appdir="$HOME/.local/share/applications"
helper="$HOME/bin/run-remote-vm"

command -v virsh       >/dev/null || { echo "virsh missing — sudo apt install libvirt-clients" >&2; exit 1; }
command -v virt-viewer >/dev/null || { echo "virt-viewer missing — sudo apt install virt-viewer" >&2; exit 1; }
[ -x "$helper" ] || { echo "missing or non-executable: $helper" >&2; exit 1; }

mkdir -p "$appdir"

# Every defined VM (running or not), one name per line.
mapfile -t vms < <(virsh -c "$uri" list --all --name | sed '/^$/d')
[ "${#vms[@]}" -gt 0 ] || { echo "no VMs found on $conn_host" >&2; exit 1; }

# Short host label for the launcher name and filename (strip user@ and domain).
host_short="${conn_host##*@}"; host_short="${host_short%%.*}"

for vm in "${vms[@]}"; do
    slug=$(printf '%s' "$vm" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/-*$//')
    file="$appdir/vm-${host_short}-${slug}.desktop"
    cat > "$file" <<EOF
[Desktop Entry]
Type=Application
Name=$vm ($host_short)
Comment=Remote VM on $conn_host
Exec=$helper $conn_host "$vm"
Icon=gnome-boxes
Terminal=false
Categories=System;
EOF
    echo "wrote $file"
done

update-desktop-database "$appdir" 2>/dev/null || true
echo "Done — ${#vms[@]} launcher(s) created. Search your apps for the VM names."
