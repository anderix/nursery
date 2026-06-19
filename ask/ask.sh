#!/bin/bash
# ask - One-shot terminal questions for Claude, no follow-up.
#
# A thin wrapper around `claude -p` tuned for "how do I do X in the shell"
# lookups: a fast model, a terse answer, and a neutral working directory so a
# terminal question doesn't drag in the current project's CLAUDE.md or memory.
#
# Usage:
#   ask how do I find files modified in the last day
#   ask "tar: extract a .tar.zst into ./out"
#   somecommand --help | ask what does the --depth flag do
#
# Override the model for a harder question:
#   ASK_MODEL=sonnet ask explain this awk one-liner: ...

set -euo pipefail

MODEL="${ASK_MODEL:-haiku}"

SYSTEM_PROMPT="You answer quick terminal and command-line questions for an \
expert user. Lead with the exact command. Keep it to a few lines. No preamble, \
no 'Here is', no closing summary. Assume Debian Linux and bash unless told \
otherwise. This is a one-shot tool with no follow-up: if the question is \
ambiguous, give the single most likely answer instead of asking."

usage() {
    cat <<'EOF'
ask - one-shot terminal questions for Claude (no follow-up)

Usage:
  ask <question>                 ask in plain words, no quotes needed
  ask "question with: symbols"   quote if it contains shell metacharacters
  command | ask <question>       pipe context in on stdin

Environment:
  ASK_MODEL   model to use (default: haiku; try sonnet for harder questions)

For a conversation, use `claude` instead.
EOF
}

case "${1:-}" in
    -h|--help)
        usage
        exit 0
        ;;
esac

# Question comes from the arguments; if none, read it from stdin.
question="$*"
piped=""
if [ ! -t 0 ]; then
    piped="$(cat)"
fi

if [ -z "$question" ] && [ -z "$piped" ]; then
    usage
    exit 1
fi

# Combine piped context (if any) with the typed question.
if [ -n "$piped" ]; then
    prompt="$piped"
    [ -n "$question" ] && prompt="$question"$'\n\n'"$piped"
else
    prompt="$question"
fi

# Run from a throwaway directory outside $HOME so claude doesn't walk up the
# tree and load this machine's CLAUDE.md / project context.
workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

cd "$workdir"
claude -p --model "$MODEL" --append-system-prompt "$SYSTEM_PROMPT" "$prompt"
