#!/bin/bash
# diarize - EXPERIMENTAL speaker diarization test harness.
#
# Transcribes a single audio stream and labels each line with an anonymous
# speaker id ([SPEAKER_00], [SPEAKER_01], ...). It runs whisper for the words
# and sherpa-onnx for the speaker turns, then aligns the two timelines.
#
# This is a Phase-A proof of concept, deliberately kept OUT of the `meeting`
# tool until diarization quality earns its way in. It does NOT identify people
# by name and makes no assumption about who is on which channel.
#
# Usage:
#   diarize [--speakers N] [--channel mic|sys|mix] <audio_file> [model_size]
#
#   --speakers N      Tell sherpa exactly how many distinct speakers to expect.
#                     Strongly recommended: blind clustering often miscounts.
#                     Omit to let sherpa guess via a distance threshold.
#   --channel WHICH   Which part of the audio to analyze (default: mix).
#                       mic  = left channel only
#                       sys  = right channel only
#                       mix  = downmix everything to mono
#                     Use sys to test a past call's remote participants.
#   model_size        whisper model: tiny, base, small, medium (default), large.
#                     Reuses whatever the sibling `meeting` tool has built.
#
# Output: <basename>.diarized.txt in the current directory (also printed).

set -uo pipefail

# --- Configuration (paths baked in by install.sh) ----------------------------
WHISPER_DIR="UNSET"   # reused from the sibling meeting/ build
SHERPA_DIR="UNSET"    # extracted prebuilt static sherpa-onnx
MODELS_DIR="UNSET"    # the two diarization ONNX models

VAD_MODEL_NAME="ggml-silero-v5.1.2.bin"
SEG_MODEL_NAME="sherpa-onnx-pyannote-segmentation-3-0.onnx"
EMB_MODEL_NAME="wespeaker_en_voxceleb_CAM++.onnx"

# Clustering distance threshold used only when --speakers is not given.
CLUSTER_THRESHOLD=0.5

usage() {
    cat <<'EOF'
diarize - EXPERIMENTAL speaker diarization test harness.

Usage:
  diarize [--speakers N] [--channel mic|sys|mix] <audio_file> [model_size]

  --speakers N      Number of distinct speakers (recommended; improves accuracy).
  --channel WHICH   mic | sys | mix (default mix). Use sys to test a call's
                    remote participants.
  model_size        whisper model: tiny, base, small, medium (default), large.

Output: <basename>.diarized.txt in the current directory.
EOF
}

die() { echo "Error: $*" >&2; exit 1; }

# --- Preflight ---------------------------------------------------------------
check_install() {
    [ "$WHISPER_DIR" = "UNSET" ] && die "not configured. Run ./install.sh."
    WHISPER_BIN="$WHISPER_DIR/build/bin/whisper-cli"
    VAD_MODEL="$WHISPER_DIR/models/$VAD_MODEL_NAME"
    SHERPA_BIN="$SHERPA_DIR/bin/sherpa-onnx-offline-speaker-diarization"
    SEG_MODEL="$MODELS_DIR/$SEG_MODEL_NAME"
    EMB_MODEL="$MODELS_DIR/$EMB_MODEL_NAME"

    [ -f "$WHISPER_BIN" ] || die "whisper not built. Install the sibling meeting tool first (../meeting/install.sh)."
    [ -f "$SHERPA_BIN" ]  || die "sherpa-onnx binary missing ($SHERPA_BIN). Run ./install.sh."
    [ -f "$SEG_MODEL" ]   || die "segmentation model missing ($SEG_MODEL). Run ./install.sh."
    [ -f "$EMB_MODEL" ]   || die "embedding model missing ($EMB_MODEL). Run ./install.sh."

    # Static tarballs are self-contained; harmless if lib/ is absent.
    export LD_LIBRARY_PATH="$SHERPA_DIR/lib:${LD_LIBRARY_PATH:-}"
}

# Read an SRT, emit "<start_seconds>\t<text>" (one line per cue).
srt_to_lines() {
    awk '
        function ts(t,   p) { gsub(",", ".", t); split(t, p, "[:.]")
            return p[1]*3600 + p[2]*60 + p[3] + p[4]/1000 }
        BEGIN { state = 0; text = "" }
        state == 0 && /^[0-9]+$/ { state = 1; next }
        state == 1 && /-->/ { start = ts($1); text = ""; state = 2; next }
        state == 2 && /^[[:space:]]*$/ {
            if (text != "") printf "%013.3f\t%s\n", start, text
            state = 0; text = ""; next }
        state == 2 { text = (text == "" ? $0 : text " " $0) }
        END { if (state == 2 && text != "") printf "%013.3f\t%s\n", start, text }
    ' "$1"
}

# --- Main --------------------------------------------------------------------
main() {
    local speakers="" channel="mix"
    local posargs=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --speakers) speakers="${2:-}"; shift 2 ;;
            --channel)  channel="${2:-}"; shift 2 ;;
            -h|--help|help) usage; exit 0 ;;
            *) posargs+=("$1"); shift ;;
        esac
    done
    set -- "${posargs[@]:-}"
    [ $# -ge 1 ] && [ -n "${1:-}" ] || { usage; exit 1; }

    check_install

    local input model_size model base
    input="$(realpath "$1")"
    model_size="${2:-medium}"
    model="$WHISPER_DIR/models/ggml-${model_size}.bin"
    base="$(basename "${input%.*}")"

    [ -f "$input" ] || die "file not found: $input"
    [ -f "$model" ] || die "whisper model not found: $model (build it via ../meeting/install.sh $model_size)"
    case "$channel" in mic|sys|mix) ;; *) die "--channel must be mic, sys, or mix" ;; esac

    local tmp_wav srt_base diar_raw diar_tsv whisper_tsv
    tmp_wav="$(mktemp /tmp/diarize_XXXXXX.wav)"
    diar_raw="$(mktemp /tmp/diarize_raw_XXXXXX.txt)"
    diar_tsv="$(mktemp /tmp/diarize_seg_XXXXXX.tsv)"
    whisper_tsv="$(mktemp /tmp/diarize_whisper_XXXXXX.tsv)"
    srt_base="$(mktemp -u /tmp/diarize_srt_XXXXXX)"

    # 1. Prepare a single mono 16kHz stream.
    echo "Preparing audio (${channel}, 16kHz mono)..."
    case "$channel" in
        mic) ffmpeg -y -i "$input" -af "pan=mono|c0=c0" -ar 16000 "$tmp_wav" 2>/dev/null ;;
        sys) ffmpeg -y -i "$input" -af "pan=mono|c0=c1" -ar 16000 "$tmp_wav" 2>/dev/null ;;
        mix) ffmpeg -y -i "$input" -ac 1 -ar 16000 "$tmp_wav" 2>/dev/null ;;
    esac
    [ -s "$tmp_wav" ] || die "audio prep failed (is the file stereo for --channel ${channel}? try --channel mix)"

    # 2. whisper -> SRT -> "start<TAB>text".
    echo "Transcribing with ${model_size} model..."
    local wflags=(-mc 0 -sns)
    [ -f "$VAD_MODEL" ] && wflags+=(--vad --vad-model "$VAD_MODEL")
    "$WHISPER_BIN" -m "$model" -f "$tmp_wav" "${wflags[@]}" \
        --output-srt --output-file "$srt_base" >/dev/null 2>&1
    [ -f "${srt_base}.srt" ] || die "whisper produced no SRT"
    srt_to_lines "${srt_base}.srt" > "$whisper_tsv"

    # 3. sherpa-onnx speaker diarization.
    echo "Diarizing speakers..."
    local cluster_flag
    if [ -n "$speakers" ]; then
        cluster_flag="--clustering.num-clusters=$speakers"
    else
        cluster_flag="--clustering.cluster-threshold=$CLUSTER_THRESHOLD"
        echo "  (no --speakers given; clustering by threshold $CLUSTER_THRESHOLD)"
    fi
    set -x
    "$SHERPA_BIN" \
        --segmentation.pyannote-model="$SEG_MODEL" \
        --embedding.model="$EMB_MODEL" \
        --segmentation.num-threads=4 \
        --embedding.num-threads=4 \
        "$cluster_flag" \
        "$tmp_wav" > "$diar_raw" 2>&1
    set +x

    # sherpa prints segments as: "START -- END speaker_NN".
    awk '$2=="--" { printf "%.3f\t%.3f\t%s\n", $1, $3, $4 }' "$diar_raw" > "$diar_tsv"
    if [ ! -s "$diar_tsv" ]; then
        echo "Warning: could not parse any speaker segments from sherpa output." >&2
        echo "Raw sherpa output follows (the segment format may have changed):" >&2
        cat "$diar_raw" >&2
        die "no diarization segments; see raw output above"
    fi

    # 4. Align: label each whisper line with the speaker active at its start.
    #    whisper_tsv is already in chronological order, so emit it as-is.
    echo "Merging..."
    local out="${base}.diarized.txt"
    awk -F'\t' '
        NR==FNR { ds[FNR]=$1+0; de[FNR]=$2+0; sp[FNR]=$3; n=FNR; next }
        {
            s=$1+0; who="SPEAKER_??";
            for (i=1;i<=n;i++) if (s>=ds[i] && s<de[i]) { who=toupper(sp[i]); break }
            printf "[%s] %s\n", who, $2
        }
    ' "$diar_tsv" "$whisper_tsv" > "$out"

    rm -f "$tmp_wav" "$diar_raw" "$diar_tsv" "$whisper_tsv" "${srt_base}.srt"

    echo "Done: $out"
    echo "----"
    cat "$out"
}

main "$@"
