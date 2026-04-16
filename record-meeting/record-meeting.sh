#!/bin/bash
# record-meeting - Capture both microphone and system audio for transcription
#
# Usage: record-meeting
#        Press Ctrl-C to stop recording.
#
# Output: ~/Documents/recordings/YYYY-MM-DD_HHMM_meeting.wav (16kHz mono)
# Records mic (your voice) and system audio (remote participants) in parallel,
# then merges them into a single file ready for whisper transcription.

set -uo pipefail

TIMESTAMP="$(date +%Y-%m-%d_%H%M)"
OUTPUT="${TIMESTAMP}_meeting.wav"

TMP_MIC="$(mktemp /tmp/meeting_mic_XXXXXX.wav)"
TMP_SYS="$(mktemp /tmp/meeting_sys_XXXXXX.wav)"

# Find the default audio sink name via WirePlumber
SINK=$(wpctl inspect @DEFAULT_AUDIO_SINK@ 2>/dev/null \
    | grep 'node.name' \
    | head -1 \
    | sed 's/.*= "\(.*\)"/\1/')

if [ -z "$SINK" ]; then
    echo "Error: Could not find default audio sink. Is PipeWire running?"
    echo "Try: wpctl status"
    exit 1
fi

PID_MIC=""
PID_SYS=""
START_TIME=$SECONDS
STOPPING=0
STEREO=0

stop_recording() {
    [ "$STOPPING" -eq 1 ] && return
    STOPPING=1

    [ -n "$PID_MIC" ] && kill "$PID_MIC" 2>/dev/null
    [ -n "$PID_SYS" ] && kill "$PID_SYS" 2>/dev/null
    wait 2>/dev/null

    DURATION=$(( SECONDS - START_TIME ))
    MINS=$(( DURATION / 60 ))
    SECS=$(( DURATION % 60 ))
    echo ""
    echo "Stopped. Duration: ${MINS}m ${SECS}s"

    # Pack the two streams into a stereo file: mic=left, system=right.
    # transcribe --split will demux and label the channels at transcription
    # time. If only one stream has audio, fall back to mono.
    if [ -s "$TMP_MIC" ] && [ -s "$TMP_SYS" ]; then
        echo "Packing mic + system audio (stereo: L=mic, R=sys)..."
        ffmpeg -y -i "$TMP_MIC" -i "$TMP_SYS" \
            -filter_complex "[0:a][1:a]amerge=inputs=2[out]" \
            -map "[out]" -ar 16000 -ac 2 "$OUTPUT" 2>/dev/null
        STEREO=1
    elif [ -s "$TMP_MIC" ]; then
        ffmpeg -y -i "$TMP_MIC" -ar 16000 -ac 1 "$OUTPUT" 2>/dev/null
        STEREO=0
    elif [ -s "$TMP_SYS" ]; then
        ffmpeg -y -i "$TMP_SYS" -ar 16000 -ac 1 "$OUTPUT" 2>/dev/null
        STEREO=0
    fi

    rm -f "$TMP_MIC" "$TMP_SYS"

    if [ -f "$OUTPUT" ] && [ -s "$OUTPUT" ]; then
        echo "Saved: $OUTPUT"
        echo ""
        read -rp "Run transcribe $OUTPUT now? [Y/n] " answer
        if [[ ! "$answer" =~ ^[Nn]$ ]]; then
            if [ "$STEREO" -eq 1 ]; then
                transcribe --split "$OUTPUT"
            else
                transcribe "$OUTPUT"
            fi
        fi
    else
        echo "Warning: Output file is empty or missing."
    fi
}
trap stop_recording INT TERM EXIT

echo "Recording meeting audio to: $OUTPUT"
echo "  Mic: default source"
echo "  System: ${SINK} (monitor)"
echo "Press Ctrl-C to stop."
echo ""

# Record microphone (default source)
pw-record --rate 16000 --channels 1 "$TMP_MIC" &
PID_MIC=$!

# Record system audio (sink monitor)
pw-record --target "${SINK}" \
    -P '{ stream.capture.sink=true }' \
    --rate 16000 --channels 1 "$TMP_SYS" &
PID_SYS=$!

# Wait until interrupted
wait
