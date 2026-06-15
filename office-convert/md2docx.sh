#!/bin/bash
# md2docx - Convert a Markdown file to a Word .docx via pandoc.
#
# Usage: md2docx <input.md> [output.docx]
#
# Output defaults to the input name with a .docx extension. To brand the
# document, set REFERENCE_DOC to a styled .docx, or drop a reference.docx
# next to the input; pandoc uses it as the style template.

set -euo pipefail

usage() {
    echo "Usage: md2docx <input.md> [output.docx]"
    echo "  Set REFERENCE_DOC=<file.docx> to apply a style template."
    exit "${1:-1}"
}

case "${1:-}" in
    -h|--help) usage 0 ;;
    "") usage ;;
esac

IN="$1"
[ -f "$IN" ] || { echo "Error: file not found: $IN" >&2; exit 1; }
OUT="${2:-${IN%.*}.docx}"

ref_args=()
if [ -n "${REFERENCE_DOC:-}" ]; then
    ref_args=(--reference-doc "$REFERENCE_DOC")
elif [ -f "$(dirname "$IN")/reference.docx" ]; then
    ref_args=(--reference-doc "$(dirname "$IN")/reference.docx")
fi

pandoc "$IN" --from=markdown --to=docx "${ref_args[@]}" -o "$OUT"
echo "Wrote: $OUT"
