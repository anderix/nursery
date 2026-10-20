// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

package main

import (
	"bytes"
	"context"
	"flag"
	"slices"
	"strings"
	"testing"
	"time"
)

// Invocation errors exit 2 before any sign-in is attempted; help exits 0 on
// stdout.
func TestRunInvocationContract(t *testing.T) {
	cases := []struct {
		args []string
		code int
	}{
		{nil, 2},
		{[]string{"bogus"}, 2},
		{[]string{"--help"}, 0},
		{[]string{"show"}, 2},
		{[]string{"show", "a", "b"}, 2},
		{[]string{"add", "plan"}, 2},
		{[]string{"add", "plan", ""}, 2},
		{[]string{"set", "id"}, 2},
		{[]string{"tasks", "--status", "later"}, 2},
		{[]string{"tasks", "--bucket", "Doing"}, 2},
		{[]string{"tasks", "--nope"}, 2},
		{[]string{"set", "-h"}, 0},
		{[]string{"set", "id", "--due", "11/02/2026"}, 2},
		{[]string{"set", "id", "--progress", "50"}, 2},
		{[]string{"add", "plan", "title", "--priority", "high"}, 2},
		{[]string{"set", "id", "--title", ""}, 2},
		{[]string{"set", "id", "--start", "soon"}, 2},
		{[]string{"tasks", "--priority", "high"}, 2},
		{[]string{"tasks", "--due-before", "later"}, 2},
		{[]string{"bucket"}, 2},
		{[]string{"bucket", "-h"}, 0},
		{[]string{"bucket", "move"}, 2},
		{[]string{"bucket", "add", "plan"}, 2},
		{[]string{"label", "name", "plan", "26", "x"}, 2},
		{[]string{"check", "done", "id", "0"}, 2},
		{[]string{"check", "add", "id", ""}, 2},
		{[]string{"plan", "rename", "plan", ""}, 2},
	}
	for _, c := range cases {
		var out, errOut bytes.Buffer
		if got := run(context.Background(), c.args, &out, &errOut); got != c.code {
			t.Errorf("xplan %v exited %d, want %d (stderr %q)", c.args, got, c.code, errOut.String())
		}
	}
	var out, errOut bytes.Buffer
	run(context.Background(), []string{"set", "-h"}, &out, &errOut)
	if !strings.HasPrefix(out.String(), "Usage: xplan set") || errOut.Len() != 0 {
		t.Errorf("set -h wrote %q to stdout and %q to stderr; want usage on stdout only", out.String(), errOut.String())
	}
}

func TestReorderHoistsFlagsAfterOperands(t *testing.T) {
	fs := flag.NewFlagSet("t", flag.ContinueOnError)
	fs.Bool("json", false, "")
	fs.String("bucket", "", "")
	got := reorder([]string{"Plan", "--bucket", "Doing", "--json", "--", "-dash"}, fs)
	want := []string{"--bucket", "Doing", "--json", "Plan", "--", "-dash"}
	if !slices.Equal(got, want) {
		t.Errorf("reorder = %q, want %q", got, want)
	}
}

func TestParseDate(t *testing.T) {
	now := time.Date(2026, 10, 21, 15, 4, 0, 0, time.Local) // a Wednesday
	cases := map[string]string{
		"2026-11-02": "2026-11-02",
		"today":      "2026-10-21",
		"Tomorrow":   "2026-10-22",
		"fri":        "2026-10-23",
		"wednesday":  "2026-10-28",
		"+3d":        "2026-10-24",
		"+2w":        "2026-11-04",
	}
	for in, want := range cases {
		got, err := parseDate(in, now)
		if err != nil || got.Format(time.DateOnly) != want || got.Hour() != 0 {
			t.Errorf("parseDate(%q) = %v, %v; want local midnight on %s", in, got, err, want)
		}
	}
	for _, bad := range []string{"11/02/2026", "fr", "+3", "+xd", "+-1d", "someday"} {
		if _, err := parseDate(bad, now); err == nil {
			t.Errorf("parseDate(%q) succeeded; want an error", bad)
		}
	}
	if v, err := dateField("due", "none", now); err != nil || v != nil {
		t.Errorf("dateField(none) = %v, %v; want nil to clear the date", v, err)
	}
	v, err := dateField("due", "2026-11-02", now)
	if err != nil {
		t.Fatal(err)
	}
	back, err := time.Parse(time.RFC3339, v.(string))
	if err != nil || back.Local().Format(time.DateOnly) != "2026-11-02" {
		t.Errorf("dateField(2026-11-02) = %v, which reads back as %s locally", v, back.Local())
	}
}

func TestProgressAndPriorityRoundTrip(t *testing.T) {
	for _, name := range []string{"not-started", "in-progress", "done"} {
		pc, err := parseProgress(name)
		if err != nil || progressName(pc) != name {
			t.Errorf("progress %s -> %d -> %s, %v", name, pc, progressName(pc), err)
		}
	}
	for _, name := range []string{"urgent", "important", "medium", "low"} {
		pr, err := parsePriority(name)
		if err != nil || priorityName(pr) != name {
			t.Errorf("priority %s -> %d -> %s, %v", name, pr, priorityName(pr), err)
		}
	}
	if _, err := parseProgress("50"); err == nil {
		t.Error("parseProgress accepted a number")
	}
}

func TestSortViewsPutsUndatedLast(t *testing.T) {
	views := []taskView{{Title: "b"}, {Title: "x", Due: "2026-12-01"}, {Title: "a"}, {Title: "y", Due: "2026-11-01"}}
	sortViews(views)
	var got []string
	for _, v := range views {
		got = append(got, v.Title)
	}
	if want := []string{"y", "x", "a", "b"}; !slices.Equal(got, want) {
		t.Errorf("order = %v, want %v", got, want)
	}
}
