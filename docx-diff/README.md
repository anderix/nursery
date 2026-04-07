# docx-diff

Compares two DOCX files by converting them to markdown with pandoc and producing a unified diff. Useful for reviewing changes between document versions without opening Word.

## Usage

```
docx-diff old.docx new.docx
docx-diff old.docx new.docx --output changes.md
```

Without `--output`, prints a colored diff to the terminal. With `--output`, writes a markdown file containing the diff in a fenced code block.

## Dependencies

- `pandoc` (document converter)
- `diff` (standard, included in all Linux distributions)
- `colordiff` (optional, for improved terminal colors; falls back to `diff --color`)

### Install dependencies (Debian/Ubuntu)

```
sudo apt install -y pandoc colordiff
```

## Install

```
./install.sh
```

Copies `docx-diff` to `~/bin/`.
