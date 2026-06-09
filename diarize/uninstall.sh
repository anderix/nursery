#!/bin/bash
# uninstall.sh - Remove the `diarize` command from ~/bin. Optionally remove the
#                downloaded sherpa-onnx binary and diarization models.
#
# Usage: ./uninstall.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHERPA_DIR="$SCRIPT_DIR/sherpa-onnx"
MODELS_DIR="$SCRIPT_DIR/models"
TARGET="$HOME/bin/diarize"

if [ -e "$TARGET" ]; then
    rm -f "$TARGET"
    echo "Removed: $TARGET"
else
    echo "Not installed: $TARGET (nothing to remove)"
fi

# The reused whisper build belongs to the sibling meeting tool and is NOT
# touched here. Only the sherpa binary + models this tool downloaded are offered.
if [ -d "$SHERPA_DIR" ] || [ -d "$MODELS_DIR" ]; then
    size="$(du -sch "$SHERPA_DIR" "$MODELS_DIR" 2>/dev/null | tail -1 | cut -f1)"
    read -rp "Also remove downloaded sherpa-onnx + models (${size:-?})? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
        rm -rf "$SHERPA_DIR" "$MODELS_DIR"
        echo "Removed: $SHERPA_DIR, $MODELS_DIR"
    else
        echo "Kept: $SHERPA_DIR, $MODELS_DIR"
    fi
fi

# The ~/bin PATH entry in .bashrc is shared by the other nursery tools and is
# left alone on purpose.
echo "Done."
