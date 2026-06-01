#!/bin/bash
# meeting - Record a meeting from both mic and system audio, then transcribe it.
#
# Usage:
#   meeting record                       Record until Ctrl-C, then offer to transcribe.
#   meeting transcribe [--split] <file> [model]
#                                        Transcribe an existing recording.
#   meeting help                         Show this help.
#
# Recording captures two sources in parallel and packs them into one stereo
# WAV: your microphone on the left channel, system audio (remote participants)
# on the right. Transcription with --split demuxes the two channels, runs each
# through whisper separately, and interleaves the result into one chronological
# transcript with [MIC] / [SYS] labels.
#
# Most of the time MIC is you and SYS is everyone else. When you join from
# another device (e.g. your phone), one channel is silent and the transcript
# falls back to unlabeled output for the channel that has audio.
#
# Output: <basename>.txt in the current working directory.
# Models: tiny, base, small, medium (default), large.

set -uo pipefail

# --- Configuration -----------------------------------------------------------
# WHISPER_DIR is filled in by install.sh at install time.
WHISPER_DIR="UNSET"

# Silence threshold in dB. A channel whose max_volume is below this is treated
# as empty and skipped (whisper hallucinates badly on silence).
SILENCE_THRESHOLD_DB=-40

# VAD model used to strip non-speech regions before decoding. Without it,
# whisper invents filler ("Okay. Okay.") on the long quiet stretches of an
# open-but-idle mic. Downloaded by install.sh.
VAD_MODEL_NAME="ggml-silero-v5.1.2.bin"

# --- Shared helpers ----------------------------------------------------------

usage() {
    sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
}

require_whisper() {
    if [ "$WHISPER_DIR" = "UNSET" ]; then
        echo "Error: WHISPER_DIR not configured. Run install.sh to install." >&2
        exit 1
    fi
    MAIN="$WHISPER_DIR/build/bin/whisper-cli"
    VAD_MODEL="$WHISPER_DIR/models/$VAD_MODEL_NAME"
    if [ ! -f "$MAIN" ]; then
        echo "Error: whisper.cpp not built. Run ./install.sh first." >&2
        exit 1
    fi
}

# Build the common whisper flag set once. VAD is added only if the model is
# present, so the tool still runs (with a warning) before install.sh fetches it.
#   -mc 0  : no prior-text conditioning -> stops repetition loops
#   -sns   : suppress non-speech tokens -> drops [ Silence ] / [ Inaudible ]
#   --vad  : strip non-speech before decoding -> stops silence hallucinations
build_whisper_flags() {
    WHISPER_FLAGS=(-mc 0 -sns)
    if [ -f "$VAD_MODEL" ]; then
        WHISPER_FLAGS+=(--vad --vad-model "$VAD_MODEL")
    else
        echo "Note: VAD model not found ($VAD_MODEL)." >&2
        echo "      Transcribing without VAD; expect filler on quiet stretches." >&2
        echo "      Run install.sh to download it for clean results." >&2
    fi
}

# Returns 0 if the file's max_volume is at or above SILENCE_THRESHOLD_DB.
has_audio() {
    local file="$1" max_db
    max_db=$(ffmpeg -nostats -i "$file" -af volumedetect -f null - 2>&1 \
        | sed -nE 's/.*max_volume: (-?[0-9.]+) dB.*/\1/p' \
        | head -1)
    [ -z "$max_db" ] && return 1
    awk -v v="$max_db" -v t="$SILENCE_THRESHOLD_DB" \
        'BEGIN { exit (v + 0 >= t + 0) ? 0 : 1 }'
}

# --- Recording ---------------------------------------------------------------

cmd_record() {
    local timestamp output tmp_mic tmp_sys sink
    timestamp="$(date +%Y-%m-%d_%H%M)"
    output="${timestamp}_meeting.wav"
    tmp_mic="$(mktemp /tmp/meeting_mic_XXXXXX.wav)"
    tmp_sys="$(mktemp /tmp/meeting_sys_XXXXXX.wav)"

    # Find the default audio sink name via WirePlumber.
    sink=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null \
        | grep 'node.name' | head -1 | sed 's/.*= "\(.*\)"/\1/')
    if [ -z "$sink" ]; then
        echo "Error: Could not find default audio sink. Is PipeWire running?" >&2
        echo "Try: wpctl status" >&2
        rm -f "$tmp_mic" "$tmp_sys"
        exit 1
    fi

    local pid_mic="" pid_sys="" start_time=$SECONDS stopping=0 stereo=0

    stop_recording() {
        [ "$stopping" -eq 1 ] && return
        stopping=1

        [ -n "$pid_mic" ] && kill "$pid_mic" 2>/dev/null
        [ -n "$pid_sys" ] && kill "$pid_sys" 2>/dev/null
        wait 2>/dev/null

        local duration=$(( SECONDS - start_time ))
        echo ""
        echo "Stopped. Duration: $(( duration / 60 ))m $(( duration % 60 ))s"

        # Pack the two streams into stereo: mic=left, system=right.
        # transcribe --split demuxes and labels them. If only one stream has
        # audio, fall back to mono.
        if [ -s "$tmp_mic" ] && [ -s "$tmp_sys" ]; then
            echo "Packing mic + system audio (stereo: L=mic, R=sys)..."
            ffmpeg -y -i "$tmp_mic" -i "$tmp_sys" \
                -filter_complex "[0:a][1:a]amerge=inputs=2[out]" \
                -map "[out]" -ar 16000 -ac 2 "$output" 2>/dev/null
            stereo=1
        elif [ -s "$tmp_mic" ]; then
            ffmpeg -y -i "$tmp_mic" -ar 16000 -ac 1 "$output" 2>/dev/null
        elif [ -s "$tmp_sys" ]; then
            ffmpeg -y -i "$tmp_sys" -ar 16000 -ac 1 "$output" 2>/dev/null
        fi

        rm -f "$tmp_mic" "$tmp_sys"

        if [ -f "$output" ] && [ -s "$output" ]; then
            echo "Saved: $output"
            echo ""
            read -rp "Transcribe $output now? [Y/n] " answer
            if [[ ! "$answer" =~ ^[Nn]$ ]]; then
                if [ "$stereo" -eq 1 ]; then
                    cmd_transcribe --split "$output"
                else
                    cmd_transcribe "$output"
                fi
            fi
        else
            echo "Warning: Output file is empty or missing." >&2
        fi
    }
    trap stop_recording INT TERM EXIT

    echo "Recording meeting audio to: $output"
    echo "  Mic: default source"
    echo "  System: ${sink} (monitor)"
    echo "Press Ctrl-C to stop."
    echo ""

    pw-record --rate 16000 --channels 1 "$tmp_mic" &
    pid_mic=$!
    pw-record --target "${sink}" -P '{ stream.capture.sink=true }' \
        --rate 16000 --channels 1 "$tmp_sys" &
    pid_sys=$!

    wait
}

# --- Transcription -----------------------------------------------------------

# Run whisper on a mono 16kHz WAV, producing <out_base>.srt
run_whisper_srt() {
    local wav="$1" out_base="$2"
    "$MAIN" -m "$MODEL" -f "$wav" "${WHISPER_FLAGS[@]}" \
        --output-srt --output-file "$out_base" >/dev/null 2>&1
}

# Read an SRT file, emit "<start_seconds>\t<label>\t<text>" lines.
# Multi-line text within an entry is joined with spaces.
srt_to_labeled() {
    local srt="$1" label="$2"
    awk -v label="$label" '
        function ts(t,   p) {
            gsub(",", ".", t)
            split(t, p, "[:.]")
            return p[1]*3600 + p[2]*60 + p[3] + p[4]/1000
        }
        BEGIN { state = 0; text = "" }
        state == 0 && /^[0-9]+$/ { state = 1; next }
        state == 1 && /-->/ { start = ts($1); text = ""; state = 2; next }
        state == 2 && /^[[:space:]]*$/ {
            if (text != "") printf "%013.3f\t%s\t%s\n", start, label, text
            state = 0; text = ""; next
        }
        state == 2 { text = (text == "" ? $0 : text " " $0) }
        END {
            if (state == 2 && text != "")
                printf "%013.3f\t%s\t%s\n", start, label, text
        }
    ' "$srt"
}

transcribe_single() {
    local input="$1" out="$2" tmp_wav
    tmp_wav="$(mktemp /tmp/whisper_XXXXXX.wav)"
    echo "Converting to WAV..."
    ffmpeg -y -i "$input" -ar 16000 -ac 1 "$tmp_wav" 2>/dev/null
    echo "Transcribing with ${MODEL_SIZE} model ($(basename "$input"))..."
    "$MAIN" -m "$MODEL" -f "$tmp_wav" "${WHISPER_FLAGS[@]}" \
        --output-txt --output-file "$out" >/dev/null 2>&1
    rm -f "$tmp_wav"
}

transcribe_split() {
    local input="$1" out_base="$2" tmp_mic tmp_sys
    tmp_mic="$(mktemp /tmp/whisper_mic_XXXXXX.wav)"
    tmp_sys="$(mktemp /tmp/whisper_sys_XXXXXX.wav)"

    echo "Splitting channels..."
    ffmpeg -y -i "$input" \
        -filter_complex "[0:a]channelsplit=channel_layout=stereo[L][R]" \
        -map "[L]" -ar 16000 -ac 1 "$tmp_mic" \
        -map "[R]" -ar 16000 -ac 1 "$tmp_sys" 2>/dev/null

    local mic_has=0 sys_has=0
    has_audio "$tmp_mic" && mic_has=1
    has_audio "$tmp_sys" && sys_has=1

    if [ "$mic_has" -eq 0 ] && [ "$sys_has" -eq 0 ]; then
        echo "Both channels are silent. Nothing to transcribe." >&2
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
    run_whisper_srt "$tmp_mic" "${out_base}.mic"
    echo "Transcribing SYS channel..."
    run_whisper_srt "$tmp_sys" "${out_base}.sys"

    echo "Merging labeled transcript..."
    {
        srt_to_labeled "${out_base}.mic.srt" MIC
        srt_to_labeled "${out_base}.sys.srt" SYS
    } | sort -k1,1 \
      | awk -F'\t' '{ printf "[%s] %s\n", $2, $3 }' \
      > "${out_base}.txt"

    rm -f "$tmp_mic" "$tmp_sys" "${out_base}.mic.srt" "${out_base}.sys.srt"
}

cmd_transcribe() {
    require_whisper

    local split=0 posargs=()
    for arg in "$@"; do
        case "$arg" in
            --split) split=1 ;;
            *) posargs+=("$arg") ;;
        esac
    done
    set -- "${posargs[@]:-}"

    if [ $# -eq 0 ] || [ -z "${1:-}" ]; then
        echo "Usage: meeting transcribe [--split] <audio_file> [model_size]" >&2
        echo "Models: tiny, base, small, medium (default), large" >&2
        exit 1
    fi

    local input model_basename
    input="$(realpath "$1")"
    MODEL_SIZE="${2:-medium}"
    MODEL="$WHISPER_DIR/models/ggml-${MODEL_SIZE}.bin"
    model_basename="$(basename "${input%.*}")"

    if [ ! -f "$input" ]; then
        echo "Error: File not found: $input" >&2
        exit 1
    fi
    if [ ! -f "$MODEL" ]; then
        echo "Error: Model not found: $MODEL" >&2
        echo "Run: ./install.sh $MODEL_SIZE" >&2
        exit 1
    fi

    build_whisper_flags

    if [ "$split" -eq 1 ]; then
        transcribe_split "$input" "$model_basename"
    else
        transcribe_single "$input" "$model_basename"
    fi

    echo "Done: ${model_basename}.txt"
}

# --- Dispatch ----------------------------------------------------------------

cmd="${1:-}"
case "$cmd" in
    record)     shift; cmd_record "$@" ;;
    transcribe) shift; cmd_transcribe "$@" ;;
    -h|--help|help|"") usage ;;
    *)
        echo "Unknown command: $cmd" >&2
        echo "" >&2
        usage >&2
        exit 1
        ;;
esac
