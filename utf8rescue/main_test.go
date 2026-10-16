// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

package main

import "testing"

func TestRescue(t *testing.T) {
	cases := []struct {
		name   string
		input  string
		want   string
		legacy int
		kept   int
	}{
		{"ascii", "a,b\n1,2\n", "a,b\n1,2\n", 0, 0},
		{"windows-1252", "City\x92s (\x93Effective Date\x94) \xa73.6 \x97 end", "City’s (“Effective Date”) §3.6 — end", 5, 0},
		{"utf-8", "Oracle Database – Enterprise", "Oracle Database – Enterprise", 0, 1},
		{"mixed", "\x93quoted\x94, Database – Enterprise", "“quoted”, Database – Enterprise", 2, 1},
		{"latin-1 range", "caf\xe9 \xff", "café ÿ", 2, 0},
		{"encoded replacement character", "\xef\xbf\xbd", "�", 0, 1},
		{"truncated sequence at end", "ab\xe2\x80", "abâ€", 2, 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			r, err := rescue([]byte(c.input))
			if err != nil {
				t.Fatal(err)
			}
			if string(r.text) != c.want || r.legacy != c.legacy || r.kept != c.kept {
				t.Errorf("got %q (legacy %d, kept %d), want %q (legacy %d, kept %d)",
					r.text, r.legacy, r.kept, c.want, c.legacy, c.kept)
			}
		})
	}
}

func TestRescueRejectsUndefinedBytes(t *testing.T) {
	for _, b := range []byte{0x81, 0x8D, 0x8F, 0x90, 0x9D} {
		if _, err := rescue([]byte{'a', b}); err == nil {
			t.Errorf("byte 0x%02X: want error, got none", b)
		}
	}
}
