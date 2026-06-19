#!/usr/bin/env bash
# run-remote-vm — start a libvirt VM on a remote host and open its console.
#
# The VM keeps running on the remote host (the machine that owns it); this only
# opens its display locally over SSH. Gnome Boxes uses the user-session
# libvirt, so the URI is qemu+ssh://USER@HOST/session.
#
# Usage: run-remote-vm USER@HOST "VM Name"

set -euo pipefail

conn_host="${1:?usage: run-remote-vm USER@HOST \"VM Name\"}"
vm="${2:?usage: run-remote-vm USER@HOST \"VM Name\"}"
uri="qemu+ssh://${conn_host}/session"

# Boot the VM only if it isn't already running or paused.
state=$(virsh -c "$uri" domstate "$vm" 2>/dev/null || true)
case "$state" in
    running|paused) ;;
    *) virsh -c "$uri" start "$vm" ;;
esac

# Open the console; --reconnect rides out brief network blips.
exec virt-viewer --connect "$uri" --reconnect "$vm"
