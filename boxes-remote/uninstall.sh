#!/bin/bash
# uninstall.sh - Remove the boxes-remote commands from ~/bin.
#
# Usage: ./uninstall.sh

set -euo pipefail

for name in boxes-host-setup boxes-remote-setup gen-vm-launchers run-remote-vm; do
    target="$HOME/bin/$name"
    if [ -e "$target" ]; then
        rm -f "$target"
        echo "Removed: $target"
    else
        echo "Not installed: $target (nothing to remove)"
    fi
done

# The ~/bin PATH entry in .bashrc is shared by the other nursery tools and is
# left alone on purpose.
