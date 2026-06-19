#!/usr/bin/env bash
# boxes-host-setup — make this machine's Gnome Boxes / libvirt VMs reachable
# for remote viewing over SSH. Run it ON THE HOST (the machine that owns the
# VMs), once.
#
# Gnome Boxes creates each VM with its SPICE display bound to listen='none',
# which can't be reached over qemu+ssh. This rewrites each VM to listen on
# loopback (127.0.0.1) with autoport, and enables user lingering so the
# session libvirt answers over SSH even when you're not logged in locally.
#
# Usage:
#   boxes-host-setup            fix every defined VM
#   boxes-host-setup vm1 vm2    fix only the named VMs
#
# Re-runnable: the display rewrite is a no-op once applied. Restart any VM
# that was running for the change to take effect.

set -euo pipefail

URI="qemu:///session"

command -v virsh >/dev/null || { echo "virsh missing — sudo apt install libvirt-clients" >&2; exit 1; }

if [ "$#" -gt 0 ]; then
    vms=("$@")
else
    mapfile -t vms < <(virsh -c "$URI" list --all --name | sed '/^$/d')
fi
[ "${#vms[@]}" -gt 0 ] || { echo "no VMs found in $URI" >&2; exit 1; }

for vm in "${vms[@]}"; do
    xml="$(mktemp)"
    if ! virsh -c "$URI" dumpxml --inactive "$vm" > "$xml" 2>/dev/null; then
        echo "  ! no such VM: $vm — skipping" >&2
        rm -f "$xml"
        continue
    fi
    sed -i \
        -e "s|<graphics type='spice'>|<graphics type='spice' autoport='yes'>|" \
        -e "s|<listen type='none'/>|<listen type='address' address='127.0.0.1'/>|" \
        "$xml"
    virsh -c "$URI" define "$xml" >/dev/null
    rm -f "$xml"
    echo "fixed display: $vm"
done

# Keep the user-session libvirt reachable over SSH when not logged in locally.
if [ "$(loginctl show-user "$USER" -p Linger --value 2>/dev/null)" != "yes" ]; then
    echo "==> Enabling lingering (may prompt for sudo)"
    sudo loginctl enable-linger "$USER"
fi

echo
echo "Done. Restart any VM that was running for the new display to take effect."
