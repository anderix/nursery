# office-convert

Small command-line converters between plain-text source formats and their
Microsoft Office counterparts. The plain-text side (Markdown, CSV) is the one
you author and version; the Office side is the export you hand to people who
live in Word, Excel, and PowerPoint.

| Command | Direction | Engine |
|---|---|---|
| `md2docx`  | Markdown → Word `.docx` | pandoc |
| `docx2md`  | Word `.docx` → Markdown | pandoc |
| `csv2xlsx` | CSV → Excel `.xlsx`     | openpyxl |
| `xlsx2csv` | Excel `.xlsx` → CSV     | openpyxl |
| `md2pptx`  | Markdown → PowerPoint `.pptx` | pandoc |

PowerPoint is export-only: pandoc writes `.pptx` but cannot read it, so there
is no `pptx2md`.

## Install

```bash
sudo apt install pandoc python3-openpyxl
./install.sh
```

`install.sh` copies each script to `~/bin` under its short name. Uninstall with
`./uninstall.sh`.

## Usage

Every command takes an input file and an optional output path; the output
defaults to the input name with the new extension.

```bash
md2docx report.md                 # -> report.docx
md2docx report.md final.docx      # explicit output
docx2md proposal.docx             # -> proposal.md (images to ./media/)
csv2xlsx data.csv                 # -> data.xlsx (styled, typed)
xlsx2csv workbook.xlsx --sheet Q3 # -> workbook.csv from the Q3 sheet
md2pptx deck.md                   # -> deck.pptx
```

### Branding the Office output

`md2docx` and `md2pptx` accept a pandoc reference document as a style template.
Set `REFERENCE_DOC`, or drop a `reference.docx` / `reference.pptx` next to the
input and it is picked up automatically.

```bash
REFERENCE_DOC=~/templates/excelano.docx md2docx report.md
```

### CSV typing

`csv2xlsx` conservatively types cells so Excel treats numbers as numbers and
dates as dates, but only when the conversion is lossless. Values Excel famously
mangles are kept as text: leading-zero codes (`007`, zip codes), phone-style
strings (`+1 555...`), and digit runs longer than 15. Pass `--text` to disable
inference entirely and write every cell verbatim.

### Slide division (md2pptx)

Slides break on a heading at the slide level or a horizontal rule (`---`), the
same rule the Axe Markdown slide viewer uses — so one `.md` both presents in the
browser and exports to PowerPoint here.
