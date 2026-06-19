#!/bin/bash
# install.sh - Install the boxes-remote commands into ~/bin.
#
# Copies each script to ~/bin under its short name: boxes-host-setup,
# boxes-remote-setup, gen-vm-launchers, run-remote-vm.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/bin"

install_one() {
    local src="$1" name="$2"
    cp "$SCRIPT_DIR/$src" "$HOME/bin/$name"
    chmod +x "$HOME/bin/$name"
    echo "Installed: ~/bin/$name"
}

install_one boxes-host-setup.sh   boxes-host-setup
install_one boxes-remote-setup.sh boxes-remote-setup
install_one gen-vm-launchers.sh   gen-vm-launchers
install_one run-remote-vm.sh      run-remote-vm

if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    echo "Added ~/bin to PATH in .bashrc (restart shell or: source ~/.bashrc)"
fi

command -v virsh >/dev/null || echo "Note: libvirt-clients not found (needed at runtime; the setup scripts install it)."
