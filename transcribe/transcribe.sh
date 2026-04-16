#!/bin/bash
# transcribe.sh - Transcribe audio/video files using whisper.cpp
#
# Usage: transcribe.sh [--split] <audio_file> [model_size]
# Models: tiny, base, small, medium (default), large
#
# Accepts any format ffmpeg can handle (mp4, m4a, mp3, wav, webm, etc.)
# Output: <input_basename>.txt in the current working directory.
#
# --split treats the input as a paired stereo recording from record-meeting
# (mic on left channel, system on right). Each channel is silence-checked and
# transcribed separately; output lines are labeled [MIC] / [SYS] and merged
# in chronological order. If only one channel has audio, output is unlabeled.

set -euo pipefail

WHISPER_DIR="UNSET"

if [ "$WHISPER_DIR" = "UNSET" ]; then
    echo "Error: WHISPER_DIR not configured. Run install.sh to install."
    exit 1
fi

MAIN="$WHISPER_DIR/build/bin/whisper-cli"

# Silence threshold in dB. A stream whose max_volume is below this is
# considered empty and skipped (whisper hallucinates badly on silence).
SILENCE_THRESHOLD_DB=-40

# Parse args: pull out --split, leave positional args for input + model.
SPLIT=0
POSARGS=()
for arg in "$@"; do
    case "$arg" in
        --split) SPLIT=1 ;;
        -h|--help)
            sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) POSARGS+=("$arg") ;;
    esac
done
set -- "${POSARGS[@]:-}"

if [ $# -eq 0 ] || [ -z "${1:-}" ]; then
    echo "Usage: transcribe [--split] <audio_file> [model_size]"
    echo "Models: tiny, base, small, medium (default), large"
    exit 1
fi

INPUT="$(realpath "$1")"
MODEL_SIZE="${2:-medium}"
MODEL="$WHISPER_DIR/models/ggml-${MODEL_SIZE}.bin"
BASENAME="$(basename "${INPUT%.*}")"

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

# Returns 0 if the file's max_volume is at or above SILENCE_THRESHOLD_DB.
has_audio() {
    local file="$1"
    local max_db
    max_db=$(ffmpeg -nostats -i "$file" -af volumedetect -f null - 2>&1 \
        | sed -nE 's/.*max_volume: (-?[0-9.]+) dB.*/\1/p' \
        | head -1)
    [ -z "$max_db" ] && return 1
    awk -v v="$max_db" -v t="$SILENCE_THRESHOLD_DB" \
        'BEGIN { exit (v + 0 >= t + 0) ? 0 : 1 }'
}

# Run whisper on a mono 16kHz WAV, producing <out_base>.srt
run_whisper_srt() {
    local wav="$1"
    local out_base="$2"
    "$MAIN" -m "$MODEL" -f "$wav" --output-srt --output-file "$out_base" \
        >/dev/null 2>&1
}

# Read an SRT file, emit "<start_seconds>\t<label>\t<text>" lines.
# Multi-line text within an entry is joined with spaces.
srt_to_labeled() {
    local srt="$1"
    local label="$2"
    awk -v label="$label" '
        function ts(t,   p) {
            gsub(",", ".", t)
            split(t, p, "[:.]")
            return p[1]*3600 + p[2]*60 + p[3] + p[4]/1000
        }
        BEGIN { state = 0; text = "" }
        state == 0 && /^[0-9]+$/ { state = 1; next }
        state == 1 && /-->/ {
            start = ts($1)
            text = ""
            state = 2
            next
        }
        state == 2 && /^[[:space:]]*$/ {
            if (text != "") printf "%013.3f\t%s\t%s\n", start, label, text
            state = 0
            text = ""
            next
        }
        state == 2 {
            text = (text == "" ? $0 : text " " $0)
        }
        END {
            if (state == 2 && text != "")
                printf "%013.3f\t%s\t%s\n", start, label, text
        }
    ' "$srt"
}

transcribe_single() {
    local input="$1"
    local out="$2"
    local tmp_wav
    tmp_wav="$(mktemp /tmp/whisper_XXXXXX.wav)"
    echo "Converting to WAV..."
    ffmpeg -y -i "$input" -ar 16000 -ac 1 "$tmp_wav" 2>/dev/null
    echo "Transcribing with ${MODEL_SIZE} model ($(basename "$input"))..."
    "$MAIN" -m "$MODEL" -f "$tmp_wav" --output-txt --output-file "$out" \
        >/dev/null 2>&1
    rm -f "$tmp_wav"
}

transcribe_split() {
    local input="$1"
    local out_base="$2"

    local tmp_mic tmp_sys
    tmp_mic="$(mktemp /tmp/whisper_mic_XXXXXX.wav)"
    tmp_sys="$(mktemp /tmp/whisper_sys_XXXXXX.wav)"

    echo "Splitting channels..."
    ffmpeg -y -i "$input" \
        -filter_complex "[0:a]channelsplit=channel_layout=stereo[L][R]" \
        -map "[L]" -ar 16000 -ac 1 "$tmp_mic" \
        -map "[R]" -ar 16000 -ac 1 "$tmp_sys" \
        2>/dev/null

    local mic_has=0 sys_has=0
    has_audio "$tmp_mic" && mic_has=1
    has_audio "$tmp_sys" && sys_has=1

    if [ "$mic_has" -eq 0 ] && [ "$sys_has" -eq 0 ]; then
        echo "Both channels are silent. Nothing to transcribe."
        rm -f "$tmp_mic" "$tmp_sys"
        return 1
    fi

    if [ "$mic_has" -eq 1 ] && [ "$sys_has" -eq 0 ]; then
        echo "System channel is silent; transcribing mic only (unlabeled)..."
        transcribe_single "$tmp_mic" "$out_base"
        rm -f "$tmp_mic" "$tmp_sys"
        return 0
    fi

    if [ "$mic_has" -eq 0 ] && [ "$sys_has" -eq 1 ]; then
        echo "Mic channel is silent; transcribing system only (unlabeled)..."
        transcribe_single "$tmp_sys" "$out_base"
        rm -f "$tmp_mic" "$tmp_sys"
        return 0
    fi

    echo "Transcribing MIC channel..."
    local mic_base="${out_base}.mic"
    run_whisper_srt "$tmp_mic" "$mic_base"

    echo "Transcribing SYS channel..."
    local sys_base="${out_base}.sys"
    run_whisper_srt "$tmp_sys" "$sys_base"

    echo "Merging labeled transcript..."
    {
        srt_to_labeled "${mic_base}.srt" MIC
        srt_to_labeled "${sys_base}.srt" SYS
    } | sort -k1,1 \
      | awk -F'\t' '{ printf "[%s] %s\n", $2, $3 }' \
      > "${out_base}.txt"

    rm -f "$tmp_mic" "$tmp_sys" "${mic_base}.srt" "${sys_base}.srt"
}

if [ "$SPLIT" -eq 1 ]; then
    transcribe_split "$INPUT" "$BASENAME"
else
    transcribe_single "$INPUT" "$BASENAME"
fi

echo "Done: ${BASENAME}.txt"
