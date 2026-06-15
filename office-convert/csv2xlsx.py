#!/usr/bin/env python3
"""csv2xlsx - Convert a CSV file to a styled Excel .xlsx workbook.

Usage: csv2xlsx <input.csv> [output.xlsx] [--text] [--no-header]

Reads RFC 4180 CSV and writes a single-sheet workbook with a bold, frozen
header row, an autofilter, and auto-fitted column widths.

By default cells are conservatively typed so Excel treats numbers as numbers
and dates as dates -- but only when the conversion is lossless. Values that
Excel famously mangles are kept as text: leading-zero codes (007, zip codes),
phone-style strings (+1 555...), and digit runs longer than 15 (Excel loses
precision past that). Use --text to disable all inference and write every
cell verbatim as text.
"""
import argparse
import csv
import re
import sys
from datetime import datetime

from openpyxl import Workbook
from openpyxl.styles import Font
from openpyxl.utils import get_column_letter

# Strings that look numeric but must stay text or Excel corrupts them.
_LEADING_ZERO = re.compile(r"^-?0\d")          # 007, 00123  (but not 0 or 0.5)
_PHONE_ISH = re.compile(r"^\+\d")               # +1 555 1234
_DATE_FORMATS = ("%Y-%m-%d", "%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S")


def infer(value):
    """Return a typed value for an xlsx cell, or the original string as text."""
    if value == "":
        return None
    s = value.strip()
    if _LEADING_ZERO.match(s) or _PHONE_ISH.match(s):
        return value
    # Integer, only if it round-trips exactly and won't overflow Excel's
    # 15-significant-digit precision.
    if re.fullmatch(r"-?\d+", s) and len(s.lstrip("-")) <= 15:
        return int(s)
    # Float, only if it parses and is finite.
    try:
        f = float(s)
        if f == f and f not in (float("inf"), float("-inf")):
            return f
    except ValueError:
        pass
    for fmt in _DATE_FORMATS:
        try:
            return datetime.strptime(s, fmt)
        except ValueError:
            pass
    return value


def main():
    ap = argparse.ArgumentParser(prog="csv2xlsx", description="Convert CSV to a styled .xlsx workbook.")
    ap.add_argument("input", help="input .csv file")
    ap.add_argument("output", nargs="?", help="output .xlsx (default: input name with .xlsx)")
    ap.add_argument("--text", action="store_true", help="write every cell as text; no type inference")
    ap.add_argument("--no-header", action="store_true", help="treat the first row as data, not a header")
    args = ap.parse_args()

    out = args.output or re.sub(r"\.[^.]*$", "", args.input) + ".xlsx"

    wb = Workbook()
    ws = wb.active
    widths = {}

    try:
        f = open(args.input, newline="", encoding="utf-8-sig")
    except OSError as e:
        sys.exit(f"Error: {e}")

    with f:
        reader = csv.reader(f)
        for r, row in enumerate(reader, start=1):
            for c, raw in enumerate(row, start=1):
                cell = ws.cell(row=r, column=c)
                cell.value = raw if args.text else infer(raw)
                widths[c] = max(widths.get(c, 0), len(raw))
            if r == 1 and not args.no_header:
                for cell in ws[1]:
                    cell.font = Font(bold=True)

    if ws.max_row == 0:
        sys.exit("Error: input is empty")

    if not args.no_header:
        ws.freeze_panes = "A2"
        ws.auto_filter.ref = ws.dimensions

    for c, w in widths.items():
        ws.column_dimensions[get_column_letter(c)].width = min(max(w + 2, 8), 60)

    wb.save(out)
    print(f"Wrote: {out}")


if __name__ == "__main__":
    main()
