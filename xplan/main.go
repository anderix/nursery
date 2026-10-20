// xplan — Create, read, update and delete Microsoft Planner tasks from the command line.
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)
//
// Usage:
//
//	xplan plans
//	xplan tasks "Website relaunch" --bucket Doing
//	xplan add "Website relaunch" "Draft the launch post" --due 2026-11-02 --assign me
//	xplan set <task-id> --progress done
//
// Planner is reached through Microsoft Graph with delegated permissions, so
// xplan sees and changes only what the signed-in user can in Planner itself.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"sort"
	"strings"
	"text/tabwriter"
	"time"

	"github.com/excelano/graphauth"
)

var app = graphauth.App{
	Name:     "xplan",
	ClientID: "12adc5cf-de78-42ee-9c6f-f69bb8eb5921",
	Scopes: []string{
		"https://graph.microsoft.com/Tasks.ReadWrite",
		"https://graph.microsoft.com/User.ReadBasic.All",
	},
	Cache: "planner-token",
	Tools: []string{"xplan"},
}

const usage = `xplan - Microsoft Planner from the command line

Usage:
  xplan plans                        list the plans shared with you
  xplan buckets <plan>               list a plan's buckets in board order
  xplan tasks [<plan>]               list a plan's tasks, or yours across plans
  xplan show <task-id>               show one task with its notes and checklist
  xplan add <plan> <title> [flags]   create a task and print its ID
  xplan set <task-id> [flags]        change a task
  xplan rm <task-id>                 delete a task
  xplan auth [--json]                report the sign-in state

A plan or bucket is named by its title or its ID; a task by its ID, which
` + "`xplan tasks`" + ` prints. Every command takes --json. Run ` + "`xplan <command> -h`" + ` for
its flags.

Signing in is device code, once, from an interactive terminal; the session is
cached at ` + "`~/.config/excelano/planner-token.json`" + ` and renews silently.

Exit codes:
  0  success, including a listing with nothing in it
  1  bad input: an unknown plan, bucket, task or user, a sign-in that could not
     be completed, a request Graph refused
  2  bad invocation: unknown command or flag, missing or extra argument`

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
	code := run(ctx, os.Args[1:], os.Stdout, os.Stderr)
	stop()
	os.Exit(code)
}

type command func(ctx context.Context, args []string, stdout, stderr io.Writer) int

func run(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	if len(args) == 0 {
		fmt.Fprintln(stderr, usage)
		return 2
	}
	commands := map[string]command{
		"plans":   cmdPlans,
		"buckets": cmdBuckets,
		"tasks":   cmdTasks,
		"show":    cmdShow,
		"add":     cmdAdd,
		"set":     cmdSet,
		"rm":      cmdRm,
		"auth": func(ctx context.Context, args []string, stdout, stderr io.Writer) int {
			return app.AuthCommand(ctx, "xplan", "", args, stdout, stderr)
		},
	}
	switch args[0] {
	case "-h", "--help", "help":
		fmt.Fprintln(stdout, usage)
		return 0
	}
	cmd, ok := commands[args[0]]
	if !ok {
		fmt.Fprintf(stderr, "xplan: unknown command %q\n\n%s\n", args[0], usage)
		return 2
	}
	return cmd(ctx, args[1:], stdout, stderr)
}

// parse reads a command's flags wherever they sit on the line and checks the
// operand count. It returns the operands and an exit code; a nonzero code
// means the caller returns it at once.
func parse(fs *flag.FlagSet, synopsis string, args []string, minArgs, maxArgs int, stdout, stderr io.Writer) ([]string, int) {
	fs.SetOutput(stderr)
	printUsage := func(w io.Writer) {
		fmt.Fprintf(w, "Usage: xplan %s\n", synopsis)
		if hasFlags(fs) {
			fmt.Fprintln(w, "\nFlags:")
			fs.SetOutput(w)
			fs.PrintDefaults()
			fs.SetOutput(stderr)
		}
	}
	if helpRequested(args, fs) {
		printUsage(stdout)
		return nil, -1
	}
	fs.Usage = func() { printUsage(stderr) }
	if err := fs.Parse(reorder(args, fs)); err != nil {
		return nil, 2
	}
	if n := fs.NArg(); n < minArgs || n > maxArgs {
		fmt.Fprintf(stderr, "xplan %s: wrong number of arguments\n", fs.Name())
		printUsage(stderr)
		return nil, 2
	}
	return fs.Args(), 0
}

func hasFlags(fs *flag.FlagSet) bool {
	any := false
	fs.VisitAll(func(*flag.Flag) { any = true })
	return any
}

// exit turns a parse result into the code the command returns: help is a
// success, anything else nonzero is passed through.
func exit(code int) int {
	if code < 0 {
		return 0
	}
	return code
}

// connect signs in and returns the Planner client. Commands call it only
// after their arguments parse, so a mistyped command never starts a sign-in.
func connect(ctx context.Context, stderr io.Writer) (*planner, bool) {
	client, err := app.NewPublicClient(app.CachePath(), "")
	if err != nil {
		fmt.Fprintf(stderr, "xplan: %v\n", err)
		return nil, false
	}
	result, err := app.Authenticate(ctx, client)
	if err != nil {
		fmt.Fprintf(stderr, "xplan: %v%s\n", err, graphauth.HintForAuthError(err))
		return nil, false
	}
	return newPlanner(app.NewGraphClient(client, result.Account, graphauth.WithTimeout(time.Minute))), true
}

func fail(stderr io.Writer, name string, err error) int {
	if errors.Is(err, context.Canceled) {
		fmt.Fprintf(stderr, "xplan %s: interrupted\n", name)
	} else {
		fmt.Fprintf(stderr, "xplan %s: %v\n", name, err)
	}
	return 1
}

func writeJSON(w io.Writer, v any) int {
	enc := json.NewEncoder(w)
	enc.SetIndent("", "  ")
	if err := enc.Encode(v); err != nil {
		return 1
	}
	return 0
}

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

func cmdBuckets(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("buckets", flag.ContinueOnError)
	asJSON := fs.Bool("json", false, "print the buckets as a JSON array")
	operands, code := parse(fs, "buckets <plan> [--json]", args, 1, 1, stdout, stderr)
	if code != 0 {
		return exit(code)
	}
	p, ok := connect(ctx, stderr)
	if !ok {
		return 1
	}
	pl, err := p.resolvePlan(ctx, operands[0])
	if err != nil {
		return fail(stderr, "buckets", err)
	}
	buckets, err := p.planBuckets(ctx, pl.ID)
	if err != nil {
		return fail(stderr, "buckets", err)
	}
	if *asJSON {
		return writeJSON(stdout, buckets)
	}
	tw := tabwriter.NewWriter(stdout, 0, 0, 2, ' ', 0)
	for _, b := range buckets {
		fmt.Fprintf(tw, "%s\t%s\n", b.ID, b.Name)
	}
	tw.Flush()
	return 0
}

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
	Due             string          `json:"due,omitempty"`
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
		Assignees:       p.assignees(ctx, t),
	}
	if t.BucketID != "" {
		v.Bucket = p.bucketName(ctx, t.PlanID, t.BucketID)
	}
	if t.DueDateTime != nil {
		v.Due = t.DueDateTime.Local().Format(time.DateOnly)
	}
	return v
}

func cmdTasks(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("tasks", flag.ContinueOnError)
	asJSON := fs.Bool("json", false, "print the tasks as a JSON array")
	bucketRef := fs.String("bucket", "", "only tasks in this `bucket` (needs a plan)")
	assignee := fs.String("assignee", "", "only tasks assigned to this `user` (UPN, email, or me)")
	status := fs.String("status", "open", "which tasks: open, done, or all")
	operands, code := parse(fs, "tasks [<plan>] [--bucket name] [--assignee user] [--status open|done|all] [--json]", args, 0, 1, stdout, stderr)
	if code != 0 {
		return exit(code)
	}
	if *status != "open" && *status != "done" && *status != "all" {
		fmt.Fprintf(stderr, "xplan tasks: --status must be open, done or all, not %q\n", *status)
		return 2
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
		views = append(views, p.view(ctx, t))
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
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\t%s\n", v.ID, progressMark(v.PercentComplete), dash(v.Due), where, v.Title, names(v.Assignees))
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
	v.Checklist = make([]checklistItem, 0, len(d.Checklist))
	for _, item := range d.Checklist {
		v.Checklist = append(v.Checklist, item)
	}
	sortByHint(v.Checklist, func(c checklistItem) string { return c.OrderHint })

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
	fmt.Fprintf(tw, "Due\t%s\n", dash(v.Due))
	fmt.Fprintf(tw, "Assigned\t%s\n", dash(names(v.Assignees)))
	tw.Flush()
	if d.Description != "" {
		fmt.Fprintf(stdout, "\n%s\n", strings.TrimRight(d.Description, "\n"))
	}
	if len(v.Checklist) > 0 {
		fmt.Fprintln(stdout)
		for _, item := range v.Checklist {
			mark := "[ ]"
			if item.IsChecked {
				mark = "[x]"
			}
			fmt.Fprintf(stdout, "%s %s\n", mark, item.Title)
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
	due      *string
	progress *string
	priority *string
	notes    *string
	assign   listFlag
	unassign listFlag
}

func newTaskFlags(name string, withTitle, withUnassign bool) *taskFlags {
	tf := &taskFlags{fs: flag.NewFlagSet(name, flag.ContinueOnError)}
	if withTitle {
		tf.title = tf.fs.String("title", "", "new `title`")
	}
	tf.bucket = tf.fs.String("bucket", "", "put the task in this `bucket` (add defaults to the plan's first)")
	tf.due = tf.fs.String("due", "", "due `date` as YYYY-MM-DD, or none to clear it")
	tf.progress = tf.fs.String("progress", "", "`state`: not-started, in-progress or done")
	tf.priority = tf.fs.String("priority", "", "`level`: urgent, important, medium or low")
	tf.notes = tf.fs.String("notes", "", "the task's notes `text`, or - to read them from stdin")
	tf.fs.Var(&tf.assign, "assign", "assign a `user` (UPN, email, or me); repeatable")
	if withUnassign {
		tf.fs.Var(&tf.unassign, "unassign", "remove a `user` from the task; repeatable")
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
	if tf.set("due") {
		due, err := parseDue(*tf.due)
		if err != nil {
			return nil, err
		}
		out["dueDateTime"] = due
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
	if err := tf.resolve(ctx, p, t.PlanID, patch); err != nil {
		return fail(stderr, "set", err)
	}
	if len(patch) > 0 {
		if err := p.updateTask(ctx, t, patch); err != nil {
			return fail(stderr, "set", err)
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

type listFlag []string

func (l *listFlag) String() string     { return strings.Join(*l, ",") }
func (l *listFlag) Set(v string) error { *l = append(*l, v); return nil }

// parseDue reads a due date as local midnight, which Planner shows as that
// date; "none" clears it.
func parseDue(s string) (any, error) {
	if strings.EqualFold(s, "none") {
		return nil, nil
	}
	d, err := time.ParseInLocation(time.DateOnly, s, time.Local)
	if err != nil {
		return nil, fmt.Errorf("--due %q is not a date; write YYYY-MM-DD, or none to clear it", s)
	}
	return d.UTC().Format(time.RFC3339), nil
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

func names(users []user) string {
	n := make([]string, len(users))
	for i, u := range users {
		n[i] = u.DisplayName
	}
	return strings.Join(n, ", ")
}

func dash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}
