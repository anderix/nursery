#!/bin/bash
# install.sh - Install the EXPERIMENTAL `diarize` test harness.
#
# Pulls the prebuilt sherpa-onnx binary (no pip, no PyTorch, no compile) and the
# two diarization ONNX models, then installs `diarize` to ~/bin with the sherpa,
# model, and (reused) whisper paths baked in.
#
# Uses the shared-no-tts build (~24 MB): it carries the diarization binary plus
# its shared libs, and is ~14x smaller than the self-contained static build
# (~320 MB). diarize.sh sets LD_LIBRARY_PATH so the shared libs resolve.
#
# Whisper itself is NOT downloaded here: diarize reuses the build from the
# sibling `meeting` tool. Install/build that first.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SHERPA_DIR="$SCRIPT_DIR/sherpa-onnx"
MODELS_DIR="$SCRIPT_DIR/models"
WHISPER_DIR="$(cd "$SCRIPT_DIR/../meeting" 2>/dev/null && pwd || true)/whisper.cpp"

# --- Model sources. If a URL 404s, the release asset was renamed; check
#     https://github.com/k2-fsa/sherpa-onnx/releases and update these. ---------
SEG_TARBALL_URL="${SEG_TARBALL_URL:-https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-segmentation-models/sherpa-onnx-pyannote-segmentation-3-0.tar.bz2}"
EMB_MODEL_URL="${EMB_MODEL_URL:-https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/wespeaker_en_voxceleb_CAM++.onnx}"

SEG_MODEL_NAME="sherpa-onnx-pyannote-segmentation-3-0.onnx"
EMB_MODEL_NAME="wespeaker_en_voxceleb_CAM++.onnx"

for cmd in curl tar ffmpeg; do
    command -v "$cmd" >/dev/null || { echo "Error: '$cmd' not found." >&2; exit 1; }
done

# --- 1. Prebuilt static sherpa-onnx binary -----------------------------------
if [ -x "$SHERPA_DIR/bin/sherpa-onnx-offline-speaker-diarization" ]; then
    echo "sherpa-onnx already present, skipping download."
else
    echo "Resolving latest sherpa-onnx shared-no-tts linux-x64 release..."
    url="${SHERPA_TARBALL_URL:-}"
    if [ -z "$url" ]; then
        url=$(curl -fsSL "https://api.github.com/repos/k2-fsa/sherpa-onnx/releases/latest" \
            | grep -o 'https://[^"]*linux-x64-shared-no-tts\.tar\.bz2' | head -1) || true
    fi
    [ -n "$url" ] || { echo "Error: could not find a linux-x64-shared-no-tts tarball. Set SHERPA_TARBALL_URL=<url> from https://github.com/k2-fsa/sherpa-onnx/releases" >&2; exit 1; }
    echo "  $url"
    tmp="$(mktemp /tmp/sherpa_XXXXXX.tar.bz2)"
    curl -fL "$url" -o "$tmp"
    mkdir -p "$SHERPA_DIR"
    # The tarball has a single versioned top dir; strip it.
    tar xjf "$tmp" -C "$SHERPA_DIR" --strip-components=1
    rm -f "$tmp"
    [ -x "$SHERPA_DIR/bin/sherpa-onnx-offline-speaker-diarization" ] \
        || { echo "Error: diarization binary not found after extract. Tarball layout may have changed." >&2; exit 1; }
fi

# --- 2. Diarization models ---------------------------------------------------
mkdir -p "$MODELS_DIR"

if [ -f "$MODELS_DIR/$SEG_MODEL_NAME" ]; then
    echo "Segmentation model present, skipping."
else
    echo "Downloading segmentation model..."
    tmp="$(mktemp /tmp/seg_XXXXXX.tar.bz2)"; tmpd="$(mktemp -d /tmp/seg_XXXXXX)"
    curl -fL "$SEG_TARBALL_URL" -o "$tmp"
    tar xjf "$tmp" -C "$tmpd"
    onnx="$(find "$tmpd" -name '*.onnx' | head -1)"
    [ -n "$onnx" ] || { echo "Error: no .onnx inside segmentation tarball." >&2; exit 1; }
    cp "$onnx" "$MODELS_DIR/$SEG_MODEL_NAME"
    rm -rf "$tmp" "$tmpd"
fi

if [ -f "$MODELS_DIR/$EMB_MODEL_NAME" ]; then
    echo "Embedding model present, skipping."
else
    echo "Downloading speaker-embedding model..."
    curl -fL "$EMB_MODEL_URL" -o "$MODELS_DIR/$EMB_MODEL_NAME"
fi

# --- 3. Sanity-check the reused whisper build --------------------------------
if [ ! -x "$WHISPER_DIR/build/bin/whisper-cli" ]; then
    echo "Warning: whisper not built at $WHISPER_DIR" >&2
    echo "         diarize reuses the sibling meeting tool's whisper build." >&2
    echo "         Run ../meeting/install.sh before using diarize." >&2
fi

# --- 4. Install the script with paths baked in -------------------------------
mkdir -p "$HOME/bin"
sed -e "s|^WHISPER_DIR=.*|WHISPER_DIR=\"$WHISPER_DIR\"|" \
    -e "s|^SHERPA_DIR=.*|SHERPA_DIR=\"$SHERPA_DIR\"|" \
    -e "s|^MODELS_DIR=.*|MODELS_DIR=\"$MODELS_DIR\"|" \
    "$SCRIPT_DIR/diarize.sh" > "$HOME/bin/diarize"
chmod +x "$HOME/bin/diarize"

if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
    echo "Added ~/bin to PATH in .bashrc (restart shell or: source ~/.bashrc)"
fi

echo "Installed: ~/bin/diarize"
echo "Try: diarize --speakers 3 --channel sys /path/to/a_past_meeting.wav"
