# nursery

Small tools in various stages of growth. When something here matures enough to stand on its own, it graduates to its own repository.

## Install

Each tool keeps its own `install.sh` (copying it into `~/bin`). To set up a box in one pass:

```bash
git pull && ./install-most.sh
```

That installs the quick tools. The heavy ones — `meeting` (builds whisper.cpp) and `diarize` (downloads models) — are opt-in, so a sync never triggers a long compile: `./install-most.sh meeting`. `naked-gnome` and `select` manage their own setup and are left alone.

## Current

| Tool | Description |
|---|---|
| **install-most.sh** | One-pass installer — runs each tool's `install.sh`, holding back the heavy builds (`meeting`, `diarize`) unless named |
| **ask** | One-shot terminal questions for Claude — a terse, fast-model `claude -p` wrapper with no follow-up |
| **boxes-remote** | View one machine's Gnome Boxes VMs from another over SSH — host setup, client setup, and per-VM desktop launchers |
| **csv-splitter** | Split a large CSV into upload-sized chunks (~25 MB each), header repeated per chunk |
| **docx-diff** | Diff tool for `.docx` files |
| **office-convert** | Convert Markdown/CSV ↔ Word/Excel/PowerPoint (md→docx/pptx, csv↔xlsx) via pandoc + openpyxl |
| **naked-gnome** | Audit and trim a fat Debian + GNOME install — packages, autostart, services, firmware, gsettings, disk junk |
| **pdf-extract** | Extract text/content from PDFs |
| **meeting** | Record a meeting (mic + system audio, separate channels) and transcribe it locally with whisper.cpp |
| **diarize** | _Experimental._ Speaker-diarization test harness (whisper + sherpa-onnx); proving ground before it joins `meeting` |
| **screen-ocr** | OCR on a screen region |
| **select** | Database viewer — URL paths as SQL, returns HTML/CSV/JSON |

## Graduated

| Tool | Description | Repo |
|---|---|---|
| **ved** | The verbose ed — a drop-in ed clone in pure-stdlib Rust | [excelano/ved](https://github.com/excelano/ved) |
