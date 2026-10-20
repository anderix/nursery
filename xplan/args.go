// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

package main

import (
	"flag"
	"strings"
)

// boolFlags reports which of fs's flags take no value, so an argument walk can
// tell `--bucket Doing` (flag plus value) from `--json Doing` (flag, then a
// positional).
func boolFlags(fs *flag.FlagSet) map[string]bool {
	out := map[string]bool{}
	fs.VisitAll(func(f *flag.Flag) {
		if bf, ok := f.Value.(interface{ IsBoolFlag() bool }); ok && bf.IsBoolFlag() {
			out[f.Name] = true
		}
	})
	return out
}

// reorder moves flags ahead of positional arguments so a flag written after
// an operand is still read as a flag; Go's flag package stops at the first
// positional. Everything after a `--` terminator is passed through untouched,
// which is how a title beginning with a dash is spelled.
func reorder(args []string, fs *flag.FlagSet) []string {
	isBool := boolFlags(fs)

	var flags, positional []string
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == "--" {
			positional = append(positional, args[i:]...)
			break
		}
		if !strings.HasPrefix(a, "-") || a == "-" {
			positional = append(positional, a)
			continue
		}
		flags = append(flags, a)
		name := strings.TrimLeft(a, "-")
		if strings.ContainsRune(name, '=') {
			continue
		}
		if !isBool[name] && i+1 < len(args) {
			flags = append(flags, args[i+1])
			i++
		}
	}
	return append(flags, positional...)
}

// helpRequested reports whether args asks for help in flag position, so the
// usage can go to stdout at exit 0 instead of being a parse error on stderr.
func helpRequested(args []string, fs *flag.FlagSet) bool {
	isBool := boolFlags(fs)
	for i := 0; i < len(args); i++ {
		a := args[i]
		if a == "--" {
			return false
		}
		if !strings.HasPrefix(a, "-") || a == "-" {
			continue
		}
		name := strings.TrimLeft(a, "-")
		attached := false
		if eq := strings.IndexByte(name, '='); eq >= 0 {
			name, attached = name[:eq], true
		}
		if name == "h" || name == "help" {
			return true
		}
		if attached {
			continue
		}
		if !isBool[name] && i+1 < len(args) {
			i++
		}
	}
	return false
}
