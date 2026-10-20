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

func TestParseDue(t *testing.T) {
	if v, err := parseDue("none"); err != nil || v != nil {
		t.Errorf("parseDue(none) = %v, %v; want nil to clear the date", v, err)
	}
	v, err := parseDue("2026-11-02")
	if err != nil {
		t.Fatal(err)
	}
	back, err := time.Parse(time.RFC3339, v.(string))
	if err != nil || back.Local().Format(time.DateOnly) != "2026-11-02" {
		t.Errorf("parseDue(2026-11-02) = %v, which reads back as %s locally", v, back.Local())
	}
	if _, err := parseDue("11/02/2026"); err == nil {
		t.Error("parseDue accepted a non-ISO date")
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
