#!/bin/bash
# uninstall.sh - Remove the ask command from ~/bin.
#
# Usage: ./uninstall.sh

set -euo pipefail

target="$HOME/bin/ask"
if [ -e "$target" ]; then
    rm -f "$target"
    echo "Removed: $target"
else
    echo "Not installed: $target (nothing to remove)"
fi

# The ~/bin PATH entry in .bashrc is shared by the other nursery tools and is
# left alone on purpose.
