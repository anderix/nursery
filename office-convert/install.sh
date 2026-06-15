#!/bin/bash
# install.sh - Install the office-convert commands into ~/bin.
#
# Copies each converter to ~/bin without its extension, so you invoke them as
# md2docx, docx2md, csv2xlsx, xlsx2csv, and md2pptx.
#
# Requires: pandoc (md <-> docx, md -> pptx) and python3-openpyxl (csv <-> xlsx).
#   sudo apt install pandoc python3-openpyxl

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$HOME/bin"

install_one() {
    local src="$1" name="$2"
    cp "$SCRIPT_DIR/$src" "$HOME/bin/$name"
    chmod +x "$HOME/bin/$name"
    echo "Installed: ~/bin/$name"
}

install_one md2docx.sh  md2docx
install_one docx2md.sh  docx2md
install_one csv2xlsx.py csv2xlsx
install_one xlsx2csv.py xlsx2csv
install_one md2pptx.sh  md2pptx

if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    echo "Added ~/bin to PATH in .bashrc (restart shell or: source ~/.bashrc)"
fi

command -v pandoc >/dev/null || echo "Warning: pandoc not found (needed for md/docx/pptx)."
python3 -c "import openpyxl" 2>/dev/null || echo "Warning: python3-openpyxl not found (needed for csv/xlsx)."
