# csv-splitter

Splits a large CSV file into smaller chunks suitable for upload, repeating the
header row on every chunk. Defaults to ~25 MB per chunk, which is safe for most
upload limits.

## Usage

```
csv-splitter <input.csv> [target_size_mb]
```

Writes `<input>_part1.csv`, `<input>_part2.csv`, … into the current directory.
The size is per chunk and defaults to 25 MB.

```
csv-splitter contacts.csv        # ~25 MB chunks
csv-splitter contacts.csv 10     # ~10 MB chunks
```

## Dependencies

Python 3 (standard library only).

## Install

```
./install.sh
```

Copies `csv-splitter` to `~/bin/`.

## Uninstall

```
./uninstall.sh
```

Removes `~/bin/csv-splitter`. The shared `~/bin` PATH entry in `.bashrc` is left
alone.
