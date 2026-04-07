# screen-ocr

Takes a screenshot of a selected screen region, OCRs the image, and copies the extracted text to the clipboard. Designed for Debian + GNOME on Wayland.

## Usage

```
screen-ocr
screen-ocr --file output.txt
```

Running the command opens GNOME's region selector. Draw a box around the text you want to capture. The OCR result is immediately copied to the clipboard. Use `--file` to also save the text to a file.

## Dependencies

- `gnome-screenshot` (GNOME region screenshot tool)
- `wl-copy` (part of `wl-clipboard`, Wayland clipboard utility)
- `tesseract` (OCR engine)

### Install dependencies (Debian)

```
sudo apt install -y gnome-screenshot wl-clipboard tesseract-ocr tesseract-ocr-eng
```

## Install

```
./install.sh
```

Copies `screen-ocr` to `~/bin/`.
