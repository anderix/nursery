// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"text/tabwriter"
)

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

func cmdBucket(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	return dispatch(ctx, "bucket", map[string]command{
		"add":    cmdBucketAdd,
		"rename": cmdBucketRename,
		"rm":     cmdBucketRm,
	}, args, stdout, stderr)
}

func cmdBucketAdd(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("bucket add", flag.ContinueOnError)
	operands, code := parse(fs, "bucket add <plan> <name>   (prints the new bucket's ID)", args, 2, 2, stdout, stderr)
	if code != 0 {
		return exit(code)
	}
	if operands[1] == "" {
		fmt.Fprintln(stderr, "xplan bucket add: the name cannot be empty")
		return 2
	}
	p, ok := connect(ctx, stderr)
	if !ok {
		return 1
	}
	pl, err := p.resolvePlan(ctx, operands[0])
	if err != nil {
		return fail(stderr, "bucket add", err)
	}
	b, err := p.createBucket(ctx, pl.ID, operands[1])
	if err != nil {
		return fail(stderr, "bucket add", err)
	}
	fmt.Fprintln(stdout, b.ID)
	return 0
}

func cmdBucketRename(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("bucket rename", flag.ContinueOnError)
	operands, code := parse(fs, "bucket rename <plan> <bucket> <new-name>", args, 3, 3, stdout, stderr)
	if code != 0 {
		return exit(code)
	}
	if operands[2] == "" {
		fmt.Fprintln(stderr, "xplan bucket rename: the name cannot be empty")
		return 2
	}
	p, ok := connect(ctx, stderr)
	if !ok {
		return 1
	}
	pl, err := p.resolvePlan(ctx, operands[0])
	if err != nil {
		return fail(stderr, "bucket rename", err)
	}
	b, err := p.resolveBucket(ctx, pl.ID, operands[1])
	if err != nil {
		return fail(stderr, "bucket rename", err)
	}
	if err := p.renameBucket(ctx, b, operands[2]); err != nil {
		return fail(stderr, "bucket rename", err)
	}
	return 0
}

func cmdBucketRm(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("bucket rm", flag.ContinueOnError)
	force := fs.Bool("force", false, "delete the bucket's tasks along with it")
	operands, code := parse(fs, "bucket rm <plan> <bucket> [--force]", args, 2, 2, stdout, stderr)
	if code != 0 {
		return exit(code)
	}
	p, ok := connect(ctx, stderr)
	if !ok {
		return 1
	}
	pl, err := p.resolvePlan(ctx, operands[0])
	if err != nil {
		return fail(stderr, "bucket rm", err)
	}
	b, err := p.resolveBucket(ctx, pl.ID, operands[1])
	if err != nil {
		return fail(stderr, "bucket rm", err)
	}
	// Graph deletes a bucket without its tasks, leaving them pointing at a
	// bucket that no longer exists, so xplan deletes them itself first.
	tasks, err := p.planTasks(ctx, pl.ID)
	if err != nil {
		return fail(stderr, "bucket rm", err)
	}
	var held []task
	for _, t := range tasks {
		if t.BucketID == b.ID {
			held = append(held, t)
		}
	}
	if len(held) > 0 && !*force {
		return fail(stderr, "bucket rm", fmt.Errorf("bucket %q holds %s; move them first, or pass --force to delete them with it", b.Name, plural(len(held), "task")))
	}
	for _, t := range held {
		if err := p.deleteTask(ctx, t); err != nil {
			return fail(stderr, "bucket rm", fmt.Errorf("deleting task %s (%s): %w", t.ID, t.Title, err))
		}
	}
	if err := p.deleteBucket(ctx, b); err != nil {
		return fail(stderr, "bucket rm", err)
	}
	if len(held) > 0 {
		fmt.Fprintf(stdout, "Deleted bucket %s (%s) and %s\n", b.ID, b.Name, plural(len(held), "task"))
	} else {
		fmt.Fprintf(stdout, "Deleted bucket %s (%s)\n", b.ID, b.Name)
	}
	return 0
}
