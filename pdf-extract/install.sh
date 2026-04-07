#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/bin"
cp "$SCRIPT_DIR/pdf-extract.sh" "$HOME/bin/pdf-extract"
chmod +x "$HOME/bin/pdf-extract"

if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    echo "Added ~/bin to PATH in .bashrc (restart shell or: source ~/.bashrc)"
fi

echo "Installed: ~/bin/pdf-extract"
