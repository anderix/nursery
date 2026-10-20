#!/bin/bash
# uninstall.sh - Remove the `xplan` command from ~/bin.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)
#
# Usage: ./uninstall.sh

set -euo pipefail

TARGET="$HOME/bin/xplan"

if [ -e "$TARGET" ]; then
    rm -f "$TARGET"
    echo "Removed: $TARGET"
else
    echo "Not installed: $TARGET (nothing to remove)"
fi

# The ~/bin PATH entry in .bashrc is shared by the other nursery tools and is
# left alone on purpose.
