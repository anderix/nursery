#!/bin/bash
# install.sh - Clone, build whisper.cpp and download a model
#
# Usage: ./install.sh [model_size]
# Models: tiny, base, small, medium (default), large
#
# Prerequisites: git, g++ or clang, make

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WHISPER_DIR="$SCRIPT_DIR/whisper.cpp"
MODEL_SIZE="${1:-medium}"

echo "=== whisper.cpp setup ==="

# Check prerequisites
for cmd in git make ffmpeg; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not installed."
        exit 1
    fi
done

if ! command -v g++ &>/dev/null && ! command -v clang++ &>/dev/null; then
    echo "Error: C++ compiler (g++ or clang++) is required."
    exit 1
fi

# Clone
if [ -d "$WHISPER_DIR" ]; then
    echo "whisper.cpp already cloned, pulling latest..."
    git -C "$WHISPER_DIR" pull
else
    echo "Cloning whisper.cpp..."
    git clone https://github.com/ggerganov/whisper.cpp "$WHISPER_DIR"
fi

# Build
echo "Building..."
make -C "$WHISPER_DIR" -j"$(nproc)"

# Download model
echo "Downloading ${MODEL_SIZE} model..."
bash "$WHISPER_DIR/models/download-ggml-model.sh" "$MODEL_SIZE"

# Install transcribe to ~/bin
mkdir -p "$HOME/bin"
sed "s|^WHISPER_DIR=.*|WHISPER_DIR=\"$WHISPER_DIR\"|" "$SCRIPT_DIR/transcribe.sh" > "$HOME/bin/transcribe"
chmod +x "$HOME/bin/transcribe"

# Ensure ~/bin is on PATH
if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    echo "Added ~/bin to PATH in .bashrc (restart shell or run: source ~/.bashrc)"
fi

echo ""
echo "=== Setup complete ==="
echo "Model: ggml-${MODEL_SIZE}.bin"
echo "Run: transcribe <audio_file>"
