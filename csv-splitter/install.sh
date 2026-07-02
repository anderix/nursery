#!/bin/bash
# install.sh - Install the csv-splitter command into ~/bin.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/bin"
cp "$SCRIPT_DIR/csv-splitter.py" "$HOME/bin/csv-splitter"
chmod +x "$HOME/bin/csv-splitter"

if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    echo "Added ~/bin to PATH in .bashrc (restart shell or: source ~/.bashrc)"
fi

echo "Installed: ~/bin/csv-splitter"
