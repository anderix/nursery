#!/bin/bash
# docx2md - Convert a Word .docx file to Markdown via pandoc.
#
# Usage: docx2md <input.docx> [output.md]
#
# The reverse of md2docx. Output defaults to the input name with a .md
# extension. Lines are not hard-wrapped (matching hand-authored Markdown),
# and any embedded images are extracted to a media/ folder beside the output.

set -euo pipefail

usage() {
    echo "Usage: docx2md <input.docx> [output.md]"
    exit "${1:-1}"
}

case "${1:-}" in
    -h|--help) usage 0 ;;
    "") usage ;;
esac

IN="$1"
[ -f "$IN" ] || { echo "Error: file not found: $IN" >&2; exit 1; }
OUT="${2:-${IN%.*}.md}"

pandoc "$IN" --from=docx --to=markdown --wrap=none \
    --extract-media="$(dirname "$OUT")" -o "$OUT"
echo "Wrote: $OUT"
