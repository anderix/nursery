#!/bin/bash
# transcribe.sh - Transcribe audio/video files using whisper.cpp
#
# Usage: transcribe.sh <audio_file> [model_size]
# Models: tiny, base, small, medium (default), large
#
# Accepts any format ffmpeg can handle (mp4, m4a, mp3, wav, webm, etc.)
# Output: <input_basename>.txt in the same directory as the input file

set -euo pipefail

WHISPER_DIR="UNSET"

if [ "$WHISPER_DIR" = "UNSET" ]; then
    echo "Error: WHISPER_DIR not configured. Run install.sh to install."
    exit 1
fi

MAIN="$WHISPER_DIR/build/bin/whisper-cli"

if [ $# -eq 0 ]; then
    echo "Usage: transcribe <audio_file> [model_size]"
    echo "Models: tiny, base, small, medium (default), large"
    exit 1
fi

INPUT="$(realpath "$1")"
MODEL_SIZE="${2:-medium}"
MODEL="$WHISPER_DIR/models/ggml-${MODEL_SIZE}.bin"
BASENAME="$(basename "${INPUT%.*}")"
TMP_WAV="$(mktemp /tmp/whisper_XXXXXX.wav)"

# Validate
if [ ! -f "$INPUT" ]; then
    echo "Error: File not found: $INPUT"
    exit 1
fi

if [ ! -f "$MAIN" ]; then
    echo "Error: whisper.cpp not built. Run ./install.sh first."
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    echo "Error: Model not found: $MODEL"
    echo "Run: ./install.sh $MODEL_SIZE"
    exit 1
fi

# Convert to 16kHz mono WAV
echo "Converting to WAV..."
ffmpeg -y -i "$INPUT" -ar 16000 -ac 1 "$TMP_WAV" 2>/dev/null

# Transcribe
echo "Transcribing with ${MODEL_SIZE} model ($(basename "$INPUT"))..."
"$MAIN" -m "$MODEL" -f "$TMP_WAV" --output-txt --output-file "$BASENAME"

# Cleanup
rm -f "$TMP_WAV"

echo "Done: ${BASENAME}.txt"
