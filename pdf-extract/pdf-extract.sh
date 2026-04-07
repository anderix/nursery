#!/bin/bash
# pdf-extract - Extract text from PDFs, with OCR fallback for scanned documents
#
# Usage: pdf-extract <file.pdf|directory> [--output <dir>]
#
# For single files: produces file.txt alongside the PDF (or in output dir)
# For directories: processes all PDFs, skips already-extracted files

set -euo pipefail

usage() {
    echo "Usage: pdf-extract <file.pdf|directory> [--output <dir>]"
    exit 1
}

if [ $# -eq 0 ]; then
    usage
fi

INPUT="$1"
shift

OUTPUT_DIR=""
while [ $# -gt 0 ]; do
    case "$1" in
        --output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Minimum character count to consider pdftotext output valid
# Scanned PDFs often produce 0-50 chars of garbage
MIN_CHARS=100

PROCESSED=0
OCR_COUNT=0
SKIPPED=0
FAILED=0

ocr_images() {
    # OCR a directory of images, write concatenated text to output file
    local img_dir="$1"
    local txt_out="$2"
    local basename="$3"

    local page_text=""
    local count=0
    for img in "$img_dir"/*; do
        [ -f "$img" ] || continue
        case "$img" in
            *.png|*.jpg|*.jpeg|*.tiff|*.tif|*.bmp) ;;
            *) continue ;;
        esac
        count=$(( count + 1 ))
        local page_out="${img%.*}_ocr"
        tesseract "$img" "$page_out" -l eng --psm 6 2>/dev/null
        if [ -f "${page_out}.txt" ]; then
            page_text+="$(cat "${page_out}.txt")"
            page_text+=$'\n\n'
        fi
    done

    if [ -n "$page_text" ]; then
        echo "$page_text" > "$txt_out"
        PROCESSED=$(( PROCESSED + 1 ))
        OCR_COUNT=$(( OCR_COUNT + 1 ))
        echo "  $basename (OCR, ${count} pages)"
        return 0
    else
        echo "    Warning: OCR produced no text for $basename"
        FAILED=$(( FAILED + 1 ))
        return 1
    fi
}

extract_one() {
    local pdf="$1"
    local txt_out="$2"

    # Skip if output exists and is newer than input
    if [ -f "$txt_out" ] && [ "$txt_out" -nt "$pdf" ]; then
        SKIPPED=$(( SKIPPED + 1 ))
        return
    fi

    local basename
    basename="$(basename "$pdf")"

    # Detect file type: some .pdf files are actually zip archives of page images
    local filetype
    filetype="$(file -b "$pdf")"

    if [[ "$filetype" == Zip* ]]; then
        echo "  $basename (image archive, not a real PDF)..."
        local tmp_dir
        tmp_dir="$(mktemp -d /tmp/pdf-ocr_XXXXXX)"

        unzip -q -j "$pdf" -d "$tmp_dir" 2>/dev/null

        # Check that it actually contains images
        local has_images=0
        for f in "$tmp_dir"/*; do
            case "$f" in
                *.png|*.jpg|*.jpeg|*.tiff|*.tif|*.bmp) has_images=1; break ;;
            esac
        done

        if [ "$has_images" -eq 0 ]; then
            echo "    Warning: Archive contains no recognizable images"
            rm -rf "$tmp_dir"
            FAILED=$(( FAILED + 1 ))
            return
        fi

        ocr_images "$tmp_dir" "$txt_out" "$basename"
        rm -rf "$tmp_dir"
        return
    fi

    # Real PDF: try pdftotext first
    local tmp_txt
    tmp_txt="$(mktemp /tmp/pdf-extract_XXXXXX.txt)"

    if pdftotext "$pdf" "$tmp_txt" 2>/dev/null; then
        local char_count
        char_count=$(wc -c < "$tmp_txt")

        if [ "$char_count" -ge "$MIN_CHARS" ]; then
            mv "$tmp_txt" "$txt_out"
            echo "  $basename (text)"
            PROCESSED=$(( PROCESSED + 1 ))
            return
        fi
    fi
    rm -f "$tmp_txt"

    # Fallback: OCR via tesseract (convert PDF pages to images first)
    echo "  $basename (OCR, scanned document)..."
    local tmp_dir
    tmp_dir="$(mktemp -d /tmp/pdf-ocr_XXXXXX)"

    if ! command -v pdftoppm &>/dev/null; then
        echo "    Warning: pdftoppm not available, cannot OCR $basename"
        rm -rf "$tmp_dir"
        FAILED=$(( FAILED + 1 ))
        return
    fi

    # Convert PDF pages to PNGs
    pdftoppm -png -r 300 "$pdf" "$tmp_dir/page" 2>/dev/null

    ocr_images "$tmp_dir" "$txt_out" "$basename"
    rm -rf "$tmp_dir"
}

process_pdf() {
    local pdf="$1"
    local txt_out

    if [ -n "$OUTPUT_DIR" ]; then
        mkdir -p "$OUTPUT_DIR"
        txt_out="$OUTPUT_DIR/$(basename "${pdf%.pdf}.txt")"
    else
        txt_out="${pdf%.pdf}.txt"
    fi

    extract_one "$pdf" "$txt_out"
}

if [ -f "$INPUT" ]; then
    # Single file
    if [[ "$INPUT" != *.pdf && "$INPUT" != *.PDF ]]; then
        echo "Error: Not a PDF file: $INPUT"
        exit 1
    fi
    echo "Processing:"
    process_pdf "$(realpath "$INPUT")"
elif [ -d "$INPUT" ]; then
    # Directory batch mode
    echo "Processing PDFs in: $INPUT"
    found=0
    while IFS= read -r -d '' pdf; do
        found=1
        process_pdf "$pdf"
    done < <(find "$(realpath "$INPUT")" -maxdepth 1 -iname '*.pdf' -print0 | sort -z)

    if [ "$found" -eq 0 ]; then
        echo "No PDF files found in $INPUT"
        exit 1
    fi
else
    echo "Error: $INPUT is not a file or directory"
    exit 1
fi

echo ""
echo "Summary: $PROCESSED processed ($OCR_COUNT via OCR), $SKIPPED skipped, $FAILED failed"
