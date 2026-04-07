# pdf-extract

Batch-extracts text from PDF files. Uses `pdftotext` for native PDFs, automatically falls back to Tesseract OCR for scanned documents.

## Usage

```
pdf-extract file.pdf
pdf-extract /path/to/directory/
pdf-extract /path/to/directory/ --output /path/to/output/
```

Skips files that already have a newer `.txt` output, so re-running is safe and fast.

## Output

Text files are created alongside the originals (same directory, `.txt` extension) unless `--output` specifies a different directory.

## Dependencies

- `pdftotext` (part of `poppler-utils`)
- `pdftoppm` (part of `poppler-utils`, used for OCR fallback)
- `tesseract` (OCR engine, only needed for scanned PDFs)

### Install dependencies (Debian/Ubuntu)

```
sudo apt install -y poppler-utils tesseract-ocr tesseract-ocr-eng
```

## Install

```
./install.sh
```

Copies `pdf-extract` to `~/bin/`.
