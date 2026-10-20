// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"strconv"
	"strings"
	"text/tabwriter"
)

func cmdPlans(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("plans", flag.ContinueOnError)
	asJSON := fs.Bool("json", false, "print the plans as a JSON array")
	if _, code := parse(fs, "plans [--json]", args, 0, 0, stdout, stderr); code != 0 {
		return exit(code)
	}
	p, ok := connect(ctx, stderr)
	if !ok {
		return 1
	}
	plans, err := p.myPlans(ctx)
	if err != nil {
		return fail(stderr, "plans", err)
	}
	if *asJSON {
		return writeJSON(stdout, plans)
	}
	tw := tabwriter.NewWriter(stdout, 0, 0, 2, ' ', 0)
	for _, pl := range plans {
		fmt.Fprintf(tw, "%s\t%s\n", pl.ID, pl.Title)
	}
	tw.Flush()
	return 0
}

// labelSlots is how many labels a plan offers; Graph names them category1
// through category25.
const labelSlots = 25

func categoryKey(slot int) string {
	return fmt.Sprintf("category%d", slot)
}

// labelName is the plan's name for slot, or "label N" when it has none.
func labelName(d planDetails, slot int) string {
	if name := d.Categories[categoryKey(slot)]; name != "" {
		return name
	}
	return fmt.Sprintf("label %d", slot)
}

// resolveLabel finds a label by slot number or by case-insensitive name.
func (p *planner) resolveLabel(ctx context.Context, planID, ref string) (int, error) {
	if slot, err := strconv.Atoi(ref); err == nil {
		if slot < 1 || slot > labelSlots {
			return 0, fmt.Errorf("label slot %d is out of range; slots run 1-%d", slot, labelSlots)
		}
		return slot, nil
	}
	d, err := p.planDetails(ctx, planID)
	if err != nil {
		return 0, err
	}
	var matches []int
	for slot := 1; slot <= labelSlots; slot++ {
		if strings.EqualFold(d.Categories[categoryKey(slot)], ref) {
			matches = append(matches, slot)
		}
	}
	switch len(matches) {
	case 1:
		return matches[0], nil
	case 0:
		return 0, fmt.Errorf("no label named %q in this plan; `xplan labels <plan>` lists them", ref)
	default:
		return 0, fmt.Errorf("%d labels are named %q; name one by slot: %v", len(matches), ref, matches)
	}
}

// labelNames lists the labels applied to t, in slot order.
func (p *planner) labelNames(ctx context.Context, t task) []string {
	out := []string{}
	if len(t.Categories) == 0 {
		return out
	}
	d, _ := p.planDetails(ctx, t.PlanID)
	for slot := 1; slot <= labelSlots; slot++ {
		if t.Categories[categoryKey(slot)] {
			out = append(out, labelName(d, slot))
		}
	}
	return out
}

// hasLabel reports whether t carries the label ref names, by slot number or
// by name as the view shows it.
func hasLabel(t task, v taskView, ref string) bool {
	if slot, err := strconv.Atoi(ref); err == nil {
		return t.Categories[categoryKey(slot)]
	}
	for _, name := range v.Labels {
		if strings.EqualFold(name, ref) {
			return true
		}
	}
	return false
}

func cmdPlan(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	return dispatch(ctx, "plan", map[string]command{"rename": cmdPlanRename}, args, stdout, stderr)
}

func cmdPlanRename(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("plan rename", flag.ContinueOnError)
	operands, code := parse(fs, "plan rename <plan> <new-title>", args, 2, 2, stdout, stderr)
	if code != 0 {
		return exit(code)
	}
	if operands[1] == "" {
		fmt.Fprintln(stderr, "xplan plan rename: the title cannot be empty")
		return 2
	}
	p, ok := connect(ctx, stderr)
	if !ok {
		return 1
	}
	pl, err := p.resolvePlan(ctx, operands[0])
	if err != nil {
		return fail(stderr, "plan rename", err)
	}
	if err := p.renamePlan(ctx, pl, operands[1]); err != nil {
		return fail(stderr, "plan rename", err)
	}
	return 0
}

type labelView struct {
	Slot int    `json:"slot"`
	Name string `json:"name"`
}

func cmdLabels(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("labels", flag.ContinueOnError)
	asJSON := fs.Bool("json", false, "print the labels as a JSON array")
	operands, code := parse(fs, "labels <plan> [--json]", args, 1, 1, stdout, stderr)
	if code != 0 {
		return exit(code)
	}
	p, ok := connect(ctx, stderr)
	if !ok {
		return 1
	}
	pl, err := p.resolvePlan(ctx, operands[0])
	if err != nil {
		return fail(stderr, "labels", err)
	}
	d, err := p.planDetails(ctx, pl.ID)
	if err != nil {
		return fail(stderr, "labels", err)
	}
	labels := make([]labelView, labelSlots)
	for i := range labels {
		labels[i] = labelView{Slot: i + 1, Name: d.Categories[categoryKey(i+1)]}
	}
	if *asJSON {
		return writeJSON(stdout, labels)
	}
	tw := tabwriter.NewWriter(stdout, 0, 0, 2, ' ', 0)
	for _, l := range labels {
		fmt.Fprintf(tw, "%d\t%s\n", l.Slot, dash(l.Name))
	}
	tw.Flush()
	return 0
}

func cmdLabel(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	return dispatch(ctx, "label", map[string]command{"name": cmdLabelName}, args, stdout, stderr)
}

func cmdLabelName(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("label name", flag.ContinueOnError)
	operands, code := parse(fs, "label name <plan> <slot> <name>   (an empty name clears it)", args, 3, 3, stdout, stderr)
	if code != 0 {
		return exit(code)
	}
	slot, err := strconv.Atoi(operands[1])
	if err != nil || slot < 1 || slot > labelSlots {
		fmt.Fprintf(stderr, "xplan label name: slot %q must be a number from 1 to %d\n", operands[1], labelSlots)
		return 2
	}
	p, ok := connect(ctx, stderr)
	if !ok {
		return 1
	}
	pl, err := p.resolvePlan(ctx, operands[0])
	if err != nil {
		return fail(stderr, "label name", err)
	}
	if err := p.nameLabel(ctx, pl.ID, slot, operands[2]); err != nil {
		return fail(stderr, "label name", err)
	}
	return 0
}
