#!/bin/bash
# uninstall.sh - Remove the `meeting` command from ~/bin. Optionally remove the
#                built whisper.cpp tree and downloaded models (large; kept by
#                default, since rebuilding/redownloading is slow).
#
# Usage: ./uninstall.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WHISPER_DIR="$SCRIPT_DIR/whisper.cpp"
TARGET="$HOME/bin/meeting"

if [ -e "$TARGET" ]; then
    rm -f "$TARGET"
    echo "Removed: $TARGET"
else
    echo "Not installed: $TARGET (nothing to remove)"
fi

# whisper.cpp build + models are ~2 GB and slow to rebuild/redownload, so they
# are kept unless you ask. Re-running install.sh reuses whatever is left here.
if [ -d "$WHISPER_DIR" ]; then
    size="$(du -sh "$WHISPER_DIR" 2>/dev/null | cut -f1)"
    read -rp "Also remove built whisper.cpp + models at $WHISPER_DIR (${size:-?})? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        rm -rf "$WHISPER_DIR"
        echo "Removed: $WHISPER_DIR"
    else
        echo "Kept: $WHISPER_DIR"
    fi
fi

# The ~/bin PATH entry in .bashrc is shared by the other nursery tools and is
# left alone on purpose.
echo "Done."
