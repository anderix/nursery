#!/bin/bash
# md2pptx - Convert a Markdown file to a PowerPoint .pptx via pandoc.
#
# Usage: md2pptx <input.md> [output.pptx]
#
# Slides are divided the pandoc way: a heading at the slide level starts a
# new slide, and a horizontal rule (---) forces a break. This matches the
# Axe Markdown slide viewer, so the same file presents in the browser and
# exports here. To brand the deck, set REFERENCE_DOC to a styled .pptx, or
# drop a reference.pptx next to the input.
#
# Note: pandoc writes pptx but cannot read it, so this direction is
# export-only -- there is no pptx2md counterpart.

set -euo pipefail

usage() {
    echo "Usage: md2pptx <input.md> [output.pptx]"
    echo "  Set REFERENCE_DOC=<file.pptx> to apply a slide template."
    exit "${1:-1}"
}

case "${1:-}" in
    -h|--help) usage 0 ;;
    "") usage ;;
esac

IN="$1"
[ -f "$IN" ] || { echo "Error: file not found: $IN" >&2; exit 1; }
OUT="${2:-${IN%.*}.pptx}"

ref_args=()
if [ -n "${REFERENCE_DOC:-}" ]; then
    ref_args=(--reference-doc "$REFERENCE_DOC")
elif [ -f "$(dirname "$IN")/reference.pptx" ]; then
    ref_args=(--reference-doc "$(dirname "$IN")/reference.pptx")
fi

pandoc "$IN" --from=markdown-auto_identifiers --to=pptx "${ref_args[@]}" -o "$OUT"
echo "Wrote: $OUT"
