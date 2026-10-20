#!/bin/bash
# install.sh - Build `xplan` into ~/bin.
#
# Author: David M. Anderson
# Built with AI assistance (Claude, Anthropic)
#
# Usage: ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if ! command -v go >/dev/null; then
    echo "xplan needs Go to build: sudo apt install golang-go" >&2
    exit 1
fi

mkdir -p "$HOME/bin"
(cd "$SCRIPT_DIR" && go build -o "$HOME/bin/xplan" .)

if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    echo "Added ~/bin to PATH in .bashrc (restart shell or: source ~/.bashrc)"
fi

echo "Installed: ~/bin/xplan"
