#!/bin/bash
# uninstall.sh - Remove the office-convert commands from ~/bin.
#
# Usage: ./uninstall.sh

set -euo pipefail

for name in md2docx docx2md csv2xlsx xlsx2csv md2pptx; do
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
