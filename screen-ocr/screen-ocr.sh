#!/bin/bash
# screen-ocr - Screenshot a region, OCR it, copy text to clipboard
#
# Usage: screen-ocr [--file output.txt]
#
# Uses gnome-screenshot for region selection on GNOME/Wayland.
# OCR result is copied to clipboard. Optionally saved to a file.

set -euo pipefail

usage() {
    echo "Usage: screen-ocr [--file <output.txt>]"
    exit 1
}

OUTPUT_FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --file)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

for cmd in gnome-screenshot tesseract wl-copy; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not installed."
        echo "See README.md for dependency install instructions."
        exit 1
    fi
done

TMP_IMG="$(mktemp /tmp/screen-ocr_XXXXXX.png)"
TMP_TXT="$(mktemp /tmp/screen-ocr_XXXXXX)"

cleanup() {
    rm -f "$TMP_IMG" "$TMP_TXT" "${TMP_TXT}.txt"
}
trap cleanup EXIT

echo "Select a region to OCR..."
gnome-screenshot -a -f "$TMP_IMG" 2>/dev/null

if [ ! -s "$TMP_IMG" ]; then
    echo "Screenshot cancelled."
    exit 0
fi

tesseract "$TMP_IMG" "$TMP_TXT" -l eng --psm 6 2>/dev/null

if [ ! -s "${TMP_TXT}.txt" ]; then
    echo "OCR produced no text."
    exit 1
fi

TEXT="$(cat "${TMP_TXT}.txt")"

echo -n "$TEXT" | wl-copy
echo "Copied to clipboard ($(echo "$TEXT" | wc -l) lines, $(echo -n "$TEXT" | wc -c) chars)"

if [ -n "$OUTPUT_FILE" ]; then
    echo "$TEXT" > "$OUTPUT_FILE"
    echo "Saved to: $OUTPUT_FILE"
fi
