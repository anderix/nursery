#!/bin/bash
# install.sh - Install the ask command into ~/bin.
#
# Copies ask.sh to ~/bin/ask. Requires the Claude Code CLI (`claude`) on PATH.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/bin"
cp "$SCRIPT_DIR/ask.sh" "$HOME/bin/ask"
chmod +x "$HOME/bin/ask"
echo "Installed: ~/bin/ask"

if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    echo "Added ~/bin to PATH in .bashrc (restart shell or: source ~/.bashrc)"
fi

command -v claude >/dev/null || echo "Warning: claude not found on PATH (ask needs the Claude Code CLI)."
