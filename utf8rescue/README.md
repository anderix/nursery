# utf8rescue

Convert a Windows-1252 text file to UTF-8, including the mixed kind that iconv gets wrong.

Excel's plain "CSV" save writes Windows-1252, and tools that expect UTF-8 refuse it or show curly quotes as garbage. When the file is pure 1252, `iconv -f WINDOWS-1252 -t UTF-8` is enough. When a cell was pasted in from somewhere that already wrote UTF-8, the file is both at once, and iconv turns every UTF-8 character into mojibake (an en dash becomes `â€“`) without an error. utf8rescue keeps each valid UTF-8 sequence as it is and decodes only the remaining bytes as Windows-1252, so it handles pure 1252, pure UTF-8 and the mixture alike. Saving from Excel as "CSV UTF-8" avoids the problem at the source.

## Install

```bash
./install.sh
```

It builds with Go into `~/bin`.

## Usage

```bash
utf8rescue export.csv > export.utf8.csv
utf8rescue -o export.utf8.csv export.csv
```

With no input file it reads standard input. A summary goes to standard error: how many bytes were decoded as Windows-1252 and how many UTF-8 sequences were kept, or that the file was already UTF-8 and passed through unchanged. A UTF-8 byte order mark is kept.

It refuses a file that cannot be Windows-1252 rather than guessing. UTF-16 and UTF-7 input is identified and answered with the iconv command that converts it. A byte that Windows-1252 leaves undefined (0x81, 0x8D, 0x8F, 0x90 or 0x9D) is reported with its offset, since its presence means the file is in some other encoding.

The tool repairs encoding and nothing else. Text that was already garbage in the source, such as a PDF extraction that came out scrambled, comes through unchanged.
