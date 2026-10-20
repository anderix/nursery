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
  xplan plans                              list the plans shared with you
  xplan plan rename <plan> <title>         rename a plan
  xplan buckets <plan>                     list a plan's buckets in board order
  xplan bucket add <plan> <name>           add a bucket at the end of the board
  xplan bucket rename <plan> <bucket> <n>  rename a bucket
  xplan bucket rm <plan> <bucket>          delete an empty bucket
  xplan labels <plan>                      list a plan's label slots and names
  xplan label name <plan> <slot> <name>    name a label slot
  xplan tasks [<plan>] [flags]             list a plan's tasks, or yours across plans
  xplan show <task-id>                     show one task with notes and checklist
  xplan add <plan> <title> [flags]         create a task and print its ID
  xplan set <task-id> [flags]              change a task
  xplan rm <task-id>                       delete a task
  xplan check add <task-id> <text>         add a checklist item
  xplan check done|undo|rm <task-id> <n>   change checklist item n
  xplan auth                               report the sign-in state

A plan, bucket or label is named by its title or its ID (a label also by its
slot); a task by its ID, which ` + "`xplan tasks`" + ` prints. Listings take --json.
Run ` + "`xplan <command> -h`" + ` for its flags.

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
		"plan":    cmdPlan,
		"buckets": cmdBuckets,
		"bucket":  cmdBucket,
		"labels":  cmdLabels,
		"label":   cmdLabel,
		"check":   cmdCheck,
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

// dispatch runs the action named by args[0] among a noun's verbs, such as
// `bucket add`.
func dispatch(ctx context.Context, noun string, verbs map[string]command, args []string, stdout, stderr io.Writer) int {
	names := make([]string, 0, len(verbs))
	for v := range verbs {
		names = append(names, v)
	}
	sort.Strings(names)
	synopsis := fmt.Sprintf("Usage: xplan %s %s ...\nRun `xplan %s <action> -h` for an action's arguments.", noun, strings.Join(names, "|"), noun)
	if len(args) == 0 {
		fmt.Fprintln(stderr, synopsis)
		return 2
	}
	if args[0] == "-h" || args[0] == "--help" {
		fmt.Fprintln(stdout, synopsis)
		return 0
	}
	verb, ok := verbs[args[0]]
	if !ok {
		fmt.Fprintf(stderr, "xplan %s: unknown action %q\n%s\n", noun, args[0], synopsis)
		return 2
	}
	return verb(ctx, args[1:], stdout, stderr)
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

type listFlag []string

func (l *listFlag) String() string     { return strings.Join(*l, ",") }
func (l *listFlag) Set(v string) error { *l = append(*l, v); return nil }

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

func plural(n int, noun string) string {
	if n == 1 {
		return "1 " + noun
	}
	return fmt.Sprintf("%d %ss", n, noun)
}
