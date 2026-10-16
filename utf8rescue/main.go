// utf8rescue — Convert a Windows-1252 or mixed Windows-1252/UTF-8 text file to UTF-8.
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)
//
// Usage:
//
//	utf8rescue in.csv > out.csv
//	utf8rescue -o out.csv in.csv
//	utf8rescue < in.csv > out.csv
//
// Every valid UTF-8 sequence is kept as it is, and every remaining byte is
// decoded as Windows-1252. A file that is entirely one or the other comes out
// the same as iconv would make it; a file that mixes the two, which iconv
// corrupts, comes out whole.
package main

import (
	"flag"
	"fmt"
	"io"
	"os"
	"unicode/utf8"

	"github.com/excelano/encsniff-go"
)

// windows1252 maps 0x80–0x9F to Unicode. Zero marks the five bytes the
// encoding leaves undefined; 0xA0–0xFF match their Unicode code points.
var windows1252 = [32]rune{
	0x20AC, 0, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
	0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0, 0x017D, 0,
	0, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
	0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0, 0x017E, 0x0178,
}

type rescued struct {
	text   []byte
	legacy int
	kept   int
}

func rescue(b []byte) (rescued, error) {
	r := rescued{text: make([]byte, 0, len(b)+len(b)/8)}
	for i := 0; i < len(b); {
		if b[i] < utf8.RuneSelf {
			r.text = append(r.text, b[i])
			i++
			continue
		}
		if char, size := utf8.DecodeRune(b[i:]); char != utf8.RuneError || size != 1 {
			r.text = append(r.text, b[i:i+size]...)
			r.kept++
			i += size
			continue
		}
		char := rune(b[i])
		if char < 0xA0 {
			char = windows1252[b[i]-0x80]
			if char == 0 {
				return rescued{}, fmt.Errorf("byte 0x%02X at offset %d is undefined in Windows-1252, so this file is in some other encoding", b[i], i)
			}
		}
		r.text = utf8.AppendRune(r.text, char)
		r.legacy++
		i++
	}
	return r, nil
}

func main() {
	output := flag.String("o", "", "write to `file` instead of standard output")
	flag.Usage = func() {
		fmt.Fprintln(os.Stderr, "usage: utf8rescue [-o file] [input]")
		flag.PrintDefaults()
	}
	flag.Parse()
	if flag.NArg() > 1 {
		flag.Usage()
		os.Exit(2)
	}

	name := "standard input"
	var input []byte
	var err error
	if flag.NArg() == 1 {
		name = flag.Arg(0)
		input, err = os.ReadFile(name)
	} else {
		input, err = io.ReadAll(os.Stdin)
	}
	if err != nil {
		fail(err)
	}

	sniff := encsniff.SniffBytes(input)
	if sniff.Action == encsniff.Warn {
		fail(fmt.Errorf("%s is %s, not Windows-1252; convert it with: %s",
			name, sniff.Encoding, encsniff.IconvCommand(sniff.Encoding, name)))
	}

	r, err := rescue(input[sniff.BomLen:])
	if err != nil {
		fail(fmt.Errorf("%s: %w", name, err))
	}
	text := append(input[:sniff.BomLen:sniff.BomLen], r.text...)

	if *output == "" {
		_, err = os.Stdout.Write(text)
	} else {
		err = os.WriteFile(*output, text, 0o644)
	}
	if err != nil {
		fail(err)
	}

	if r.legacy == 0 {
		fmt.Fprintf(os.Stderr, "utf8rescue: %s is already UTF-8; written unchanged\n", name)
	} else {
		fmt.Fprintf(os.Stderr, "utf8rescue: Windows-1252 bytes decoded: %d, UTF-8 sequences kept: %d\n", r.legacy, r.kept)
	}
}

func fail(err error) {
	fmt.Fprintln(os.Stderr, "utf8rescue:", err)
	os.Exit(1)
}
