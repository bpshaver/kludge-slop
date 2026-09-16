#!/bin/bash
# Start a named Claude Code session in a new, unfocused Zellij tab.
#
# Usage:
#   spawn.sh --name <name> [--model <model>] [--cwd <dir>] [--add-dir <dir>]... -- <prompt words...>
#
# The tab is named <name>, the Claude session's display name is <name>, and the
# user's focus stays where it is. The tab closes when Claude exits.
#
# The prompt is everything after `--`, joined with single spaces. It is passed to
# `claude` as one argv element, so quotes and shell metacharacters in it need no
# escaping here: zellij hands the argv straight to the new pane's process.

set -euo pipefail

name=""
model=""
cwd="$PWD"
add_dirs=()

while [ $# -gt 0 ]; do
  case "$1" in
    --name)    name="$2"; shift 2 ;;
    --model)   model="$2"; shift 2 ;;
    --cwd)     cwd="$2"; shift 2 ;;
    --add-dir) add_dirs+=("$2"); shift 2 ;;
    --)        shift; break ;;
    *) echo "spawn.sh: unknown option: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$name" ]; then
  echo "spawn.sh: --name is required" >&2; exit 2
fi
if [ $# -eq 0 ]; then
  echo "spawn.sh: a prompt is required after --" >&2; exit 2
fi
if [ -z "${ZELLIJ:-}" ]; then
  echo "spawn.sh: not inside a Zellij session (\$ZELLIJ unset)" >&2; exit 3
fi
if ! [ -d "$cwd" ]; then
  echo "spawn.sh: --cwd is not a directory: $cwd" >&2; exit 2
fi

prompt="$*"

# Order matters: `--add-dir` is variadic and would swallow the prompt as one more
# directory, so it goes first and `--name` (single value) closes the list.
claude_args=(claude)
for d in "${add_dirs[@]:-}"; do
  [ -n "$d" ] && claude_args+=(--add-dir "$d")
done
claude_args+=(--name "$name")
[ -n "$model" ] && claude_args+=(--model "$model")
claude_args+=("$prompt")

if [ "${SPAWN_DRY_RUN:-}" = 1 ]; then
  printf 'argv:'; printf ' [%s]' "${claude_args[@]}"; echo; exit 0
fi

zellij action new-tab \
  --close-on-exit \
  --no-focus \
  --name "$name" \
  --cwd "$cwd" \
  -- "${claude_args[@]}" >/dev/null

echo "spawned tab '$name' (cwd: $cwd${model:+, model: $model}); your focus did not move"
