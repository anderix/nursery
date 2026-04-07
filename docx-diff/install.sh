#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/bin"
cp "$SCRIPT_DIR/docx-diff.sh" "$HOME/bin/docx-diff"
chmod +x "$HOME/bin/docx-diff"

if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    echo "Added ~/bin to PATH in .bashrc (restart shell or: source ~/.bashrc)"
fi

echo "Installed: ~/bin/docx-diff"
