#!/bin/bash
# docx-diff - Compare two DOCX files via markdown conversion
#
# Usage: docx-diff old.docx new.docx [--output file.md]
#
# Converts both files to markdown with pandoc, then diffs them.
# Terminal output is colored by default. Use --output for a markdown diff file.

set -euo pipefail

usage() {
    echo "Usage: docx-diff <old.docx> <new.docx> [--output <file.md>]"
    exit 1
}

if [ $# -lt 2 ]; then
    usage
fi

OLD_DOCX="$1"
NEW_DOCX="$2"
shift 2

OUTPUT_FILE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

for f in "$OLD_DOCX" "$NEW_DOCX"; do
    if [ ! -f "$f" ]; then
        echo "Error: File not found: $f"
        exit 1
    fi
done

TMP_OLD="$(mktemp /tmp/docx-diff_old_XXXXXX.md)"
TMP_NEW="$(mktemp /tmp/docx-diff_new_XXXXXX.md)"

cleanup() {
    rm -f "$TMP_OLD" "$TMP_NEW"
}
trap cleanup EXIT

# Convert DOCX to markdown
pandoc -t markdown --wrap=none "$OLD_DOCX" -o "$TMP_OLD"
pandoc -t markdown --wrap=none "$NEW_DOCX" -o "$TMP_NEW"

OLD_LABEL="$(basename "$OLD_DOCX")"
NEW_LABEL="$(basename "$NEW_DOCX")"

if [ -n "$OUTPUT_FILE" ]; then
    # Unified diff to markdown file
    {
        echo "# Diff: $OLD_LABEL vs $NEW_LABEL"
        echo ""
        echo '```diff'
        diff -u --label "$OLD_LABEL" --label "$NEW_LABEL" "$TMP_OLD" "$TMP_NEW" || true
        echo '```'
    } > "$OUTPUT_FILE"
    echo "Diff written to: $OUTPUT_FILE"
else
    # Colored terminal diff
    if command -v colordiff &>/dev/null; then
        diff -u --label "$OLD_LABEL" --label "$NEW_LABEL" "$TMP_OLD" "$TMP_NEW" | colordiff || true
    else
        diff -u --label "$OLD_LABEL" --label "$NEW_LABEL" "$TMP_OLD" "$TMP_NEW" \
            --color=always || true
    fi
fi
