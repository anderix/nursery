#!/bin/bash
# install.sh - Build whisper.cpp, download a model + the VAD model, and install
#              the `meeting` command to ~/bin.
#
# Usage: ./install.sh [model_size]
# Models: tiny, base, small, medium (default), large
#
# Prerequisites: git, cmake, a C++ compiler (g++ or clang++), ffmpeg.
# Recording also needs pw-record (pipewire-utils) at runtime.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WHISPER_DIR="$SCRIPT_DIR/whisper.cpp"
MODEL_SIZE="${1:-medium}"
VAD_MODEL="silero-v5.1.2"

echo "=== meeting setup ==="

# Check prerequisites.
for cmd in git cmake ffmpeg; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not installed." >&2
        exit 1
    fi
done
if ! command -v g++ &>/dev/null && ! command -v clang++ &>/dev/null; then
    echo "Error: C++ compiler (g++ or clang++) is required." >&2
    exit 1
fi

# Clone or update whisper.cpp.
if [ -d "$WHISPER_DIR" ]; then
    echo "whisper.cpp already cloned, pulling latest..."
    git -C "$WHISPER_DIR" pull
else
    echo "Cloning whisper.cpp..."
    git clone https://github.com/ggerganov/whisper.cpp "$WHISPER_DIR"
fi

# Build with cmake (produces build/bin/whisper-cli).
echo "Building..."
cmake -B "$WHISPER_DIR/build" -S "$WHISPER_DIR"
cmake --build "$WHISPER_DIR/build" -j"$(nproc)" --config Release

# Download the transcription model.
echo "Downloading ${MODEL_SIZE} model..."
bash "$WHISPER_DIR/models/download-ggml-model.sh" "$MODEL_SIZE"

# Download the VAD model (strips non-speech before decoding; without it whisper
# hallucinates filler on the quiet stretches of an open mic).
echo "Downloading VAD model (${VAD_MODEL})..."
bash "$WHISPER_DIR/models/download-vad-model.sh" "$VAD_MODEL"

# Install `meeting` to ~/bin with WHISPER_DIR baked in.
mkdir -p "$HOME/bin"
sed "s|^WHISPER_DIR=.*|WHISPER_DIR=\"$WHISPER_DIR\"|" "$SCRIPT_DIR/meeting.sh" \
    > "$HOME/bin/meeting"
chmod +x "$HOME/bin/meeting"

# Ensure ~/bin is on PATH.
if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    echo "Added ~/bin to PATH in .bashrc (restart shell or: source ~/.bashrc)"
fi

echo ""
echo "=== Setup complete ==="
echo "Transcription model: ggml-${MODEL_SIZE}.bin"
echo "VAD model:           ggml-${VAD_MODEL}.bin"
echo "Run: meeting record   (or: meeting transcribe --split <file>)"
