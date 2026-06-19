# ask

One-shot terminal questions for Claude. You ask, it answers, it exits — no
session, no follow-up. Reach for it when you just need to remember how to do
something in the shell; for anything you want to talk through, run `claude`.

```
$ ask how do I find files modified in the last day
find . -type f -mtime -1
```

## What it adds over `claude -p`

`ask` is a thin wrapper around `claude -p`. The bare command already answers and
exits; the wrapper changes three defaults that turn a full session into a quick
lookup:

- **Fast model.** Defaults to Haiku instead of your session model, so a "what's
  the flag again" question doesn't spin up Opus. Override with `ASK_MODEL`.
- **Terse answers.** A tuned system prompt drops the preamble and the closing
  summary, leaving the command and a line of context.
- **No project context.** Runs from a throwaway directory outside `$HOME`, so a
  terminal question never drags in the current repo's `CLAUDE.md` or memory.

If you don't want those defaults, `alias ask='claude -p'` is the whole tool.

## Install

```bash
./install.sh      # copies ask.sh to ~/bin/ask
```

Requires the Claude Code CLI (`claude`) on PATH. Uninstall with `./uninstall.sh`.

## Usage

```bash
ask how do I find files modified in the last day   # no quotes needed
ask "tar: extract a .tar.zst into ./out"           # quote if it has shell metacharacters
somecommand --help | ask what does --depth do      # pipe context in on stdin
ASK_MODEL=sonnet ask explain this awk: ...          # bump the model for a harder one
```
