// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"strconv"

	"github.com/google/uuid"
)

func cmdCheck(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	return dispatch(ctx, "check", map[string]command{
		"add":  cmdCheckAdd,
		"done": checkSetter("done", true),
		"undo": checkSetter("undo", false),
		"rm":   cmdCheckRm,
	}, args, stdout, stderr)
}

func cmdCheckAdd(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("check add", flag.ContinueOnError)
	operands, code := parse(fs, "check add <task-id> <text>", args, 2, 2, stdout, stderr)
	if code != 0 {
		return exit(code)
	}
	if operands[1] == "" {
		fmt.Fprintln(stderr, "xplan check add: the item text cannot be empty")
		return 2
	}
	p, ok := connect(ctx, stderr)
	if !ok {
		return 1
	}
	d, err := p.getDetails(ctx, operands[0])
	if err != nil {
		return fail(stderr, "check add", taskNotFound(operands[0], err))
	}
	items := d.items()
	if len(items) >= maxChecklist {
		return fail(stderr, "check add", fmt.Errorf("the checklist already holds %d items, Planner's limit", maxChecklist))
	}
	err = p.patchChecklist(ctx, operands[0], d.ETag, map[string]any{
		uuid.NewString(): map[string]any{
			"@odata.type": "#microsoft.graph.plannerChecklistItem",
			"title":       operands[1],
			"orderHint":   afterLast(items, func(c checklistItem) string { return c.OrderHint }),
		},
	})
	if err != nil {
		return fail(stderr, "check add", err)
	}
	return 0
}

// checkSetter is `check done` and `check undo`, which differ only in the state
// they write.
func checkSetter(verb string, checked bool) command {
	return func(ctx context.Context, args []string, stdout, stderr io.Writer) int {
		name := "check " + verb
		item, p, etag, code := checklistTarget(ctx, name, args, stdout, stderr)
		if code >= 0 {
			return code
		}
		err := p.patchChecklist(ctx, args[0], etag, map[string]any{
			item.ID: map[string]any{"@odata.type": "#microsoft.graph.plannerChecklistItem", "isChecked": checked},
		})
		if err != nil {
			return fail(stderr, name, err)
		}
		return 0
	}
}

func cmdCheckRm(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	item, p, etag, code := checklistTarget(ctx, "check rm", args, stdout, stderr)
	if code >= 0 {
		return code
	}
	if err := p.patchChecklist(ctx, args[0], etag, map[string]any{item.ID: nil}); err != nil {
		return fail(stderr, "check rm", err)
	}
	fmt.Fprintf(stdout, "Removed %q\n", item.Title)
	return 0
}

// checklistTarget parses `<task-id> <n>`, signs in, and finds item n as
// `xplan show` numbers it. A code of -1 means carry on; anything else is the
// exit code to return.
func checklistTarget(ctx context.Context, name string, args []string, stdout, stderr io.Writer) (checklistItem, *planner, string, int) {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	operands, code := parse(fs, name+" <task-id> <n>   (n is the item's number in `xplan show`)", args, 2, 2, stdout, stderr)
	if code != 0 {
		return checklistItem{}, nil, "", exit(code)
	}
	n, err := strconv.Atoi(operands[1])
	if err != nil || n < 1 {
		fmt.Fprintf(stderr, "xplan %s: %q is not an item number; `xplan show` numbers them from 1\n", name, operands[1])
		return checklistItem{}, nil, "", 2
	}
	p, ok := connect(ctx, stderr)
	if !ok {
		return checklistItem{}, nil, "", 1
	}
	d, err := p.getDetails(ctx, operands[0])
	if err != nil {
		return checklistItem{}, nil, "", fail(stderr, name, taskNotFound(operands[0], err))
	}
	items := d.items()
	if n > len(items) {
		return checklistItem{}, nil, "", fail(stderr, name, fmt.Errorf("the checklist has %d items, so there is no item %d", len(items), n))
	}
	return items[n-1], p, d.ETag, -1
}
