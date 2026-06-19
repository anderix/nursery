#!/usr/bin/env bash
# boxes-remote-setup — one-shot client setup for viewing a remote host's VMs.
#
# Run this on a CLIENT machine (one you sit at). It installs the viewer tools,
# sets up passwordless SSH to the VM host, verifies the connection, and
# generates a desktop launcher per VM. Re-runnable: each step is a no-op if
# already done.
#
# Usage: boxes-remote-setup [USER@HOST]
#   With no argument it uses $BOXES_REMOTE_HOST; pass USER@HOST to override.

set -euo pipefail

conn_host="${1:-${BOXES_REMOTE_HOST:-}}"
[ -n "$conn_host" ] || { echo "usage: boxes-remote-setup USER@HOST  (or set BOXES_REMOTE_HOST)" >&2; exit 1; }
uri="qemu+ssh://${conn_host}/session"
gen="$HOME/bin/gen-vm-launchers"

[ -x "$gen" ] || { echo "missing or non-executable: $gen (install the boxes-remote tools first)" >&2; exit 1; }

echo "==> Installing client tools (may prompt for sudo)"
if ! command -v virsh >/dev/null || ! command -v virt-viewer >/dev/null; then
    sudo apt update
    sudo apt install -y virt-viewer libvirt-clients virt-manager
else
    echo "    already present, skipping"
fi

echo "==> Ensuring an SSH key exists"
if [ ! -f "$HOME/.ssh/id_ed25519" ] && [ ! -f "$HOME/.ssh/id_rsa" ]; then
    ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
else
    echo "    found existing key, skipping"
fi

echo "==> Authorizing this machine on $conn_host (may prompt for the host password once)"
if ssh -o BatchMode=yes -o ConnectTimeout=5 "$conn_host" true 2>/dev/null; then
    echo "    passwordless SSH already works, skipping"
else
    ssh-copy-id "$conn_host"
fi

echo "==> Verifying libvirt connection"
if ! virsh -c "$uri" list --all >/dev/null 2>&1; then
    echo "    FAILED to reach $uri" >&2
    echo "    On the host, run boxes-host-setup (fixes VM displays and enables" >&2
    echo "    lingering) and make sure the VMs are the distro package, not Flatpak." >&2
    exit 1
fi
echo "    OK — $(virsh -c "$uri" list --all --name | sed '/^$/d' | wc -l) VM(s) visible"

echo "==> Generating launchers"
"$gen" "$conn_host"

echo
echo "Done. Search your app grid for the VM names (tagged with the host)."
