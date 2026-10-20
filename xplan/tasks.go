// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"sort"
	"strings"
	"text/tabwriter"
	"time"
)

// taskView is a task as xplan presents it: names resolved, Planner's numeric
// codes turned into words.
type taskView struct {
	ID              string          `json:"id"`
	Title           string          `json:"title"`
	Plan            string          `json:"plan"`
	PlanID          string          `json:"plan_id"`
	Bucket          string          `json:"bucket,omitempty"`
	BucketID        string          `json:"bucket_id,omitempty"`
	Progress        string          `json:"progress"`
	PercentComplete int             `json:"percent_complete"`
	Priority        string          `json:"priority"`
	Start           string          `json:"start,omitempty"`
	Due             string          `json:"due,omitempty"`
	Labels          []string        `json:"labels"`
	Assignees       []user          `json:"assignees"`
	Notes           *string         `json:"notes,omitempty"`
	Checklist       []checklistItem `json:"checklist,omitempty"`
}

func (p *planner) view(ctx context.Context, t task) taskView {
	v := taskView{
		ID:              t.ID,
		Title:           t.Title,
		Plan:            p.planTitle(ctx, t.PlanID),
		PlanID:          t.PlanID,
		BucketID:        t.BucketID,
		Progress:        progressName(t.PercentComplete),
		PercentComplete: t.PercentComplete,
		Priority:        priorityName(t.Priority),
		Labels:          p.labelNames(ctx, t),
		Assignees:       p.assignees(ctx, t),
	}
	if t.BucketID != "" {
		v.Bucket = p.bucketName(ctx, t.PlanID, t.BucketID)
	}
	v.Start = localDate(t.StartDateTime)
	v.Due = localDate(t.DueDateTime)
	return v
}

func localDate(t *time.Time) string {
	if t == nil {
		return ""
	}
	return t.Local().Format(time.DateOnly)
}

func cmdTasks(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("tasks", flag.ContinueOnError)
	asJSON := fs.Bool("json", false, "print the tasks as a JSON array")
	bucketRef := fs.String("bucket", "", "only tasks in this `bucket` (needs a plan)")
	assignee := fs.String("assignee", "", "only tasks assigned to this `user` (UPN, email, or me)")
	status := fs.String("status", "open", "which tasks: open, done, or all")
	label := fs.String("label", "", "only tasks carrying this `label` (name or slot 1-25)")
	priority := fs.String("priority", "", "only tasks at this `level`: urgent, important, medium or low")
	overdue := fs.Bool("overdue", false, "only tasks whose due date has passed")
	dueBefore := fs.String("due-before", "", "only tasks due before this `date`")
	operands, code := parse(fs, "tasks [<plan>] [flags]", args, 0, 1, stdout, stderr)
	if code != 0 {
		return exit(code)
	}
	if *status != "open" && *status != "done" && *status != "all" {
		fmt.Fprintf(stderr, "xplan tasks: --status must be open, done or all, not %q\n", *status)
		return 2
	}
	if *priority != "" {
		if _, err := parsePriority(*priority); err != nil {
			fmt.Fprintf(stderr, "xplan tasks: %v\n", err)
			return 2
		}
	}
	now := time.Now()
	var cutoff string
	if *dueBefore != "" {
		d, err := parseDate(*dueBefore, now)
		if err != nil {
			fmt.Fprintf(stderr, "xplan tasks: --due-before: %v\n", err)
			return 2
		}
		cutoff = d.Format(time.DateOnly)
	}
	if *overdue {
		if today := now.Format(time.DateOnly); cutoff == "" || today < cutoff {
			cutoff = today
		}
	}
	if *bucketRef != "" && len(operands) == 0 {
		fmt.Fprintln(stderr, "xplan tasks: --bucket needs a plan to look the bucket up in")
		return 2
	}
	p, ok := connect(ctx, stderr)
	if !ok {
		return 1
	}

	var tasks []task
	var planID string
	var err error
	if len(operands) == 1 {
		var pl plan
		if pl, err = p.resolvePlan(ctx, operands[0]); err != nil {
			return fail(stderr, "tasks", err)
		}
		planID = pl.ID
		tasks, err = p.planTasks(ctx, planID)
	} else {
		tasks, err = p.myTasks(ctx)
	}
	if err != nil {
		return fail(stderr, "tasks", err)
	}

	var bucketID, assigneeID string
	if *bucketRef != "" {
		b, err := p.resolveBucket(ctx, planID, *bucketRef)
		if err != nil {
			return fail(stderr, "tasks", err)
		}
		bucketID = b.ID
	}
	if *assignee != "" {
		u, err := p.lookupUser(ctx, *assignee)
		if err != nil {
			return fail(stderr, "tasks", err)
		}
		assigneeID = u.ID
	}

	views := []taskView{}
	for _, t := range tasks {
		if !statusMatches(*status, t.PercentComplete) || (bucketID != "" && t.BucketID != bucketID) {
			continue
		}
		if _, ok := t.Assignments[assigneeID]; assigneeID != "" && !ok {
			continue
		}
		if *priority != "" && priorityName(t.Priority) != *priority {
			continue
		}
		v := p.view(ctx, t)
		if cutoff != "" && (v.Due == "" || v.Due >= cutoff) {
			continue
		}
		if *label != "" && !hasLabel(t, v, *label) {
			continue
		}
		views = append(views, v)
	}
	sortViews(views)

	if *asJSON {
		return writeJSON(stdout, views)
	}
	tw := tabwriter.NewWriter(stdout, 0, 0, 2, ' ', 0)
	for _, v := range views {
		where := v.Bucket
		if len(operands) == 0 {
			where = v.Plan + " / " + v.Bucket
		}
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\t%s\t%s\n", v.ID, progressMark(v.PercentComplete), dash(v.Due), where, v.Title, names(v.Assignees), strings.Join(v.Labels, ", "))
	}
	tw.Flush()
	return 0
}

func statusMatches(status string, percent int) bool {
	switch status {
	case "open":
		return percent < 100
	case "done":
		return percent == 100
	}
	return true
}

// sortViews orders tasks by due date, undated last, then by title.
func sortViews(views []taskView) {
	sort.SliceStable(views, func(i, j int) bool {
		a, b := views[i], views[j]
		if (a.Due == "") != (b.Due == "") {
			return b.Due == ""
		}
		if a.Due != b.Due {
			return a.Due < b.Due
		}
		return strings.ToLower(a.Title) < strings.ToLower(b.Title)
	})
}

func cmdShow(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("show", flag.ContinueOnError)
	asJSON := fs.Bool("json", false, "print the task as a JSON object")
	operands, code := parse(fs, "show <task-id> [--json]", args, 1, 1, stdout, stderr)
	if code != 0 {
		return exit(code)
	}
	p, ok := connect(ctx, stderr)
	if !ok {
		return 1
	}
	t, err := p.getTask(ctx, operands[0])
	if err != nil {
		return fail(stderr, "show", err)
	}
	d, err := p.getDetails(ctx, t.ID)
	if err != nil {
		return fail(stderr, "show", err)
	}
	v := p.view(ctx, t)
	v.Notes = &d.Description
	v.Checklist = d.items()

	if *asJSON {
		return writeJSON(stdout, v)
	}
	tw := tabwriter.NewWriter(stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintf(tw, "Title\t%s\n", v.Title)
	fmt.Fprintf(tw, "ID\t%s\n", v.ID)
	fmt.Fprintf(tw, "Plan\t%s\n", v.Plan)
	fmt.Fprintf(tw, "Bucket\t%s\n", dash(v.Bucket))
	fmt.Fprintf(tw, "Progress\t%s\n", v.Progress)
	fmt.Fprintf(tw, "Priority\t%s\n", v.Priority)
	fmt.Fprintf(tw, "Start\t%s\n", dash(v.Start))
	fmt.Fprintf(tw, "Due\t%s\n", dash(v.Due))
	fmt.Fprintf(tw, "Labels\t%s\n", dash(strings.Join(v.Labels, ", ")))
	fmt.Fprintf(tw, "Assigned\t%s\n", dash(names(v.Assignees)))
	tw.Flush()
	if d.Description != "" {
		fmt.Fprintf(stdout, "\n%s\n", strings.TrimRight(d.Description, "\n"))
	}
	if len(v.Checklist) > 0 {
		fmt.Fprintln(stdout)
		for i, item := range v.Checklist {
			mark := "[ ]"
			if item.IsChecked {
				mark = "[x]"
			}
			fmt.Fprintf(stdout, "%2d. %s %s\n", i+1, mark, item.Title)
		}
	}
	return 0
}

// taskFlags are the fields add and set share. Each is read only when the
// caller named it, so set changes what was asked and nothing else.
type taskFlags struct {
	fs       *flag.FlagSet
	title    *string
	bucket   *string
	start    *string
	due      *string
	progress *string
	priority *string
	notes    *string
	assign   listFlag
	unassign listFlag
	label    listFlag
	unlabel  listFlag
}

func newTaskFlags(name string, withTitle, withUnassign bool) *taskFlags {
	tf := &taskFlags{fs: flag.NewFlagSet(name, flag.ContinueOnError)}
	if withTitle {
		tf.title = tf.fs.String("title", "", "new `title`")
	}
	tf.bucket = tf.fs.String("bucket", "", "put the task in this `bucket` (add defaults to the plan's first)")
	tf.start = tf.fs.String("start", "", "start `date`: "+dateForms+", or none to clear it")
	tf.due = tf.fs.String("due", "", "due `date`: "+dateForms+", or none to clear it")
	tf.progress = tf.fs.String("progress", "", "`state`: not-started, in-progress or done")
	tf.priority = tf.fs.String("priority", "", "`level`: urgent, important, medium or low")
	tf.notes = tf.fs.String("notes", "", "the task's notes `text`, or - to read them from stdin")
	tf.fs.Var(&tf.assign, "assign", "assign a `user` (UPN, email, or me); repeatable")
	if withUnassign {
		tf.fs.Var(&tf.unassign, "unassign", "remove a `user` from the task; repeatable")
	}
	tf.fs.Var(&tf.label, "label", "apply a `label` (name or slot 1-25); repeatable")
	if withUnassign {
		tf.fs.Var(&tf.unlabel, "unlabel", "remove a `label` from the task; repeatable")
	}
	return tf
}

func (tf *taskFlags) set(name string) bool {
	found := false
	tf.fs.Visit(func(f *flag.Flag) { found = found || f.Name == name })
	return found
}

// fields turns the flags that need no lookup into the task properties Graph
// takes. A bad value here is a mistake in the command, caught before sign-in.
// Notes are not a task property; they live on the task's details and are
// written separately.
func (tf *taskFlags) fields() (map[string]any, error) {
	out := map[string]any{}
	if tf.title != nil && tf.set("title") {
		if *tf.title == "" {
			return nil, errors.New("--title cannot be empty")
		}
		out["title"] = *tf.title
	}
	now := time.Now()
	for _, date := range []struct {
		flag, field string
		value       *string
	}{{"start", "startDateTime", tf.start}, {"due", "dueDateTime", tf.due}} {
		if !tf.set(date.flag) {
			continue
		}
		d, err := dateField(date.flag, *date.value, now)
		if err != nil {
			return nil, err
		}
		out[date.field] = d
	}
	if tf.set("progress") {
		pc, err := parseProgress(*tf.progress)
		if err != nil {
			return nil, err
		}
		out["percentComplete"] = pc
	}
	if tf.set("priority") {
		pr, err := parsePriority(*tf.priority)
		if err != nil {
			return nil, err
		}
		out["priority"] = pr
	}
	return out, nil
}

// resolve adds the properties that name a bucket or a person, looked up
// against planID.
func (tf *taskFlags) resolve(ctx context.Context, p *planner, planID string, out map[string]any) error {
	if tf.set("bucket") {
		b, err := p.resolveBucket(ctx, planID, *tf.bucket)
		if err != nil {
			return err
		}
		out["bucketId"] = b.ID
	}
	assignments := map[string]any{}
	for _, ref := range tf.assign {
		u, err := p.lookupUser(ctx, ref)
		if err != nil {
			return err
		}
		assignments[u.ID] = map[string]any{"@odata.type": "#microsoft.graph.plannerAssignment", "orderHint": " !"}
	}
	for _, ref := range tf.unassign {
		u, err := p.lookupUser(ctx, ref)
		if err != nil {
			return err
		}
		assignments[u.ID] = nil
	}
	if len(assignments) > 0 {
		out["assignments"] = assignments
	}
	categories := map[string]any{}
	for _, refs := range []struct {
		list  listFlag
		apply bool
	}{{tf.label, true}, {tf.unlabel, false}} {
		for _, ref := range refs.list {
			slot, err := p.resolveLabel(ctx, planID, ref)
			if err != nil {
				return err
			}
			categories[categoryKey(slot)] = refs.apply
		}
	}
	if len(categories) > 0 {
		out["appliedCategories"] = categories
	}
	return nil
}

// readNotes returns the --notes text, reading stdin for "-".
func (tf *taskFlags) readNotes(stdin io.Reader) (string, error) {
	if *tf.notes != "-" {
		return *tf.notes, nil
	}
	b, err := io.ReadAll(stdin)
	if err != nil {
		return "", fmt.Errorf("reading notes from stdin: %w", err)
	}
	return strings.TrimRight(string(b), "\n"), nil
}

func cmdAdd(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	tf := newTaskFlags("add", false, false)
	asJSON := tf.fs.Bool("json", false, "print the created task as a JSON object instead of its ID")
	operands, code := parse(tf.fs, "add <plan> <title> [flags]", args, 2, 2, stdout, stderr)
	if code != 0 {
		return exit(code)
	}
	if operands[1] == "" {
		fmt.Fprintln(stderr, "xplan add: the title cannot be empty")
		return 2
	}
	body, err := tf.fields()
	if err != nil {
		fmt.Fprintf(stderr, "xplan add: %v\n", err)
		return 2
	}
	p, ok := connect(ctx, stderr)
	if !ok {
		return 1
	}
	pl, err := p.resolvePlan(ctx, operands[0])
	if err != nil {
		return fail(stderr, "add", err)
	}
	if err := tf.resolve(ctx, p, pl.ID, body); err != nil {
		return fail(stderr, "add", err)
	}
	if _, ok := body["bucketId"]; !ok {
		buckets, err := p.planBuckets(ctx, pl.ID)
		if err != nil {
			return fail(stderr, "add", err)
		}
		if len(buckets) > 0 {
			body["bucketId"] = buckets[0].ID
		}
	}
	body["planId"] = pl.ID
	body["title"] = operands[1]
	notes := ""
	if tf.set("notes") {
		if notes, err = tf.readNotes(os.Stdin); err != nil {
			return fail(stderr, "add", err)
		}
	}

	t, err := p.createTask(ctx, body)
	if err != nil {
		return fail(stderr, "add", err)
	}
	if notes != "" {
		if err := p.setDescription(ctx, t.ID, notes); err != nil {
			return fail(stderr, "add", fmt.Errorf("created task %s, but setting its notes failed: %w", t.ID, err))
		}
	}
	if *asJSON {
		return writeJSON(stdout, p.view(ctx, t))
	}
	fmt.Fprintln(stdout, t.ID)
	return 0
}

func cmdSet(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	tf := newTaskFlags("set", true, true)
	planRef := tf.fs.String("plan", "", "move the task to this `plan`; --bucket then names a bucket there (default its first)")
	operands, code := parse(tf.fs, "set <task-id> [flags]", args, 1, 1, stdout, stderr)
	if code != 0 {
		return exit(code)
	}
	changes := 0
	tf.fs.Visit(func(*flag.Flag) { changes++ })
	if changes == 0 {
		fmt.Fprintln(stderr, "xplan set: nothing to change; name at least one flag (xplan set -h lists them)")
		return 2
	}
	patch, err := tf.fields()
	if err != nil {
		fmt.Fprintf(stderr, "xplan set: %v\n", err)
		return 2
	}
	p, ok := connect(ctx, stderr)
	if !ok {
		return 1
	}
	t, err := p.getTask(ctx, operands[0])
	if err != nil {
		return fail(stderr, "set", err)
	}
	planID := t.PlanID
	if tf.set("plan") {
		pl, err := p.resolvePlan(ctx, *planRef)
		if err != nil {
			return fail(stderr, "set", err)
		}
		planID = pl.ID
		if !tf.set("bucket") && pl.ID != t.PlanID {
			buckets, err := p.planBuckets(ctx, pl.ID)
			if err != nil {
				return fail(stderr, "set", err)
			}
			if len(buckets) == 0 {
				return fail(stderr, "set", fmt.Errorf("plan %q has no buckets, and Planner moves a task only into one; add one with `xplan bucket add`", pl.Title))
			}
			patch["bucketId"] = buckets[0].ID
		}
	}
	if err := tf.resolve(ctx, p, planID, patch); err != nil {
		return fail(stderr, "set", err)
	}
	moving := planID != t.PlanID
	var labels any
	if moving {
		labels = patch["appliedCategories"]
		delete(patch, "appliedCategories")
		patch["planId"] = planID
	}
	if len(patch) > 0 {
		if err := p.updateTask(ctx, t, patch); err != nil {
			return fail(stderr, "set", err)
		}
	}
	if moving {
		if dropped := p.labelNames(ctx, t); len(dropped) > 0 {
			fmt.Fprintf(stderr, "xplan set: labels belong to a plan, so the move removed %s\n", strings.Join(dropped, ", "))
		}
		// Planner ignores labels sent with the move itself.
		if labels != nil {
			moved, err := p.getTask(ctx, t.ID)
			if err == nil {
				err = p.updateTask(ctx, moved, map[string]any{"appliedCategories": labels})
			}
			if err != nil {
				return fail(stderr, "set", fmt.Errorf("moved the task, but labelling it failed: %w", err))
			}
		}
	}
	if tf.set("notes") {
		notes, err := tf.readNotes(os.Stdin)
		if err != nil {
			return fail(stderr, "set", err)
		}
		if err := p.setDescription(ctx, t.ID, notes); err != nil {
			return fail(stderr, "set", err)
		}
	}
	return 0
}

func cmdRm(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("rm", flag.ContinueOnError)
	operands, code := parse(fs, "rm <task-id>", args, 1, 1, stdout, stderr)
	if code != 0 {
		return exit(code)
	}
	p, ok := connect(ctx, stderr)
	if !ok {
		return 1
	}
	t, err := p.getTask(ctx, operands[0])
	if err != nil {
		return fail(stderr, "rm", err)
	}
	if err := p.deleteTask(ctx, t); err != nil {
		return fail(stderr, "rm", err)
	}
	fmt.Fprintf(stdout, "Deleted %s (%s)\n", t.ID, t.Title)
	return 0
}

func parseProgress(s string) (int, error) {
	switch s {
	case "not-started":
		return 0, nil
	case "in-progress":
		return 50, nil
	case "done":
		return 100, nil
	}
	return 0, fmt.Errorf("--progress %q is not a state; use not-started, in-progress or done", s)
}

func progressName(percent int) string {
	switch {
	case percent >= 100:
		return "done"
	case percent > 0:
		return "in-progress"
	}
	return "not-started"
}

func progressMark(percent int) string {
	switch {
	case percent >= 100:
		return "[x]"
	case percent > 0:
		return "[~]"
	}
	return "[ ]"
}

// Planner stores priority as 0–10 and its UI shows four levels; these are the
// values the UI writes for each.
func parsePriority(s string) (int, error) {
	switch s {
	case "urgent":
		return 1, nil
	case "important":
		return 3, nil
	case "medium":
		return 5, nil
	case "low":
		return 9, nil
	}
	return 0, fmt.Errorf("--priority %q is not a level; use urgent, important, medium or low", s)
}

func priorityName(p int) string {
	switch {
	case p <= 1:
		return "urgent"
	case p <= 4:
		return "important"
	case p <= 7:
		return "medium"
	}
	return "low"
}
