#!/bin/bash
# install-most.sh - Install nursery tools into ~/bin in one pass.
#
# Each tool keeps its own install.sh; this runs them together, which is what you
# want when putting the toolkit on a fresh box: `git pull && ./install-most.sh`.
#
# By default it installs only the quick, copy-into-~/bin tools. The heavy ones
# (meeting builds whisper.cpp from source; diarize downloads model tarballs and
# is shelved) are opt-in, so a fleet sync never kicks off a multi-minute compile
# or a large download you didn't ask for. Install those deliberately by name.
#
# Usage:
#   ./install-most.sh            install every quick tool
#   ./install-most.sh meeting    install only the named tools, heavy or not
#   ./install-most.sh --all      install everything, heavy included
#
# Tools without an install.sh (naked-gnome runs in place, select is a Go build)
# manage their own setup; they are reported but not touched.

set -uo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

# Tools whose install.sh compiles or downloads — skipped unless asked for.
HEAVY=(meeting diarize)

is_heavy() {
    local h
    for h in "${HEAVY[@]}"; do [ "$1" = "$h" ] && return 0; done
    return 1
}

usage() {
    cat <<'EOF'
install-most.sh - install nursery tools into ~/bin in one pass

Usage:
  ./install-most.sh            install every quick tool
  ./install-most.sh meeting    install only the named tools, heavy or not
  ./install-most.sh --all      install everything, heavy included

Heavy tools (meeting, diarize) build or download, so they are opt-in.
Tools without an install.sh (naked-gnome, select) manage their own setup.
EOF
}

# Own the ~/bin + PATH concern once, here. By exporting PATH now, each per-tool
# install.sh sees ~/bin already present and skips its own .bashrc append, so we
# never accumulate duplicate PATH lines.
mkdir -p "$HOME/bin"
if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
    export PATH="$HOME/bin:$PATH"
    if ! grep -qsF 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc"; then
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
        echo "Added ~/bin to PATH in .bashrc (restart shell or: source ~/.bashrc)"
    fi
fi

installed=()
failed=()
skipped_heavy=()
no_installer=()

run_one() {
    local name="$1" dir="$ROOT/$1"
    if [ ! -f "$dir/install.sh" ]; then
        no_installer+=("$name")
        return
    fi
    echo "=== $name ==="
    if bash "$dir/install.sh"; then
        installed+=("$name")
    else
        echo "  ! $name/install.sh failed" >&2
        failed+=("$name")
    fi
}

want_all=false
requested=()
for arg in "$@"; do
    case "$arg" in
        --all) want_all=true ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "unknown option: $arg" >&2; usage; exit 2 ;;
        *) requested+=("$arg") ;;
    esac
done

if [ ${#requested[@]} -gt 0 ]; then
    # Explicit names: install exactly those, heavy or not.
    for name in "${requested[@]}"; do
        if [ ! -d "$ROOT/$name" ]; then
            echo "  ! no such tool: $name" >&2
            failed+=("$name")
            continue
        fi
        run_one "$name"
    done
else
    # Default sweep: every tool with an install.sh, heavy ones held back.
    for dir in "$ROOT"/*/; do
        name="$(basename "$dir")"
        [ -f "$dir/install.sh" ] || { no_installer+=("$name"); continue; }
        if ! $want_all && is_heavy "$name"; then
            skipped_heavy+=("$name")
            continue
        fi
        run_one "$name"
    done
fi

echo
echo "Installed: ${installed[*]:-none}"
[ ${#skipped_heavy[@]} -gt 0 ] && {
    echo "Skipped (heavy, opt-in): ${skipped_heavy[*]}"
    echo "  -> to install them: ./install-most.sh ${skipped_heavy[*]}"
}
[ ${#no_installer[@]} -gt 0 ] && echo "No install.sh (manage their own setup): ${no_installer[*]}"
[ ${#failed[@]} -gt 0 ] && { echo "Failed: ${failed[*]}"; exit 1; }
exit 0
