#!/usr/bin/env bash
# PreToolUse(Write|Edit): keep the multi-writer logs append-only.
#
# progress.txt and messages.txt inside a repo-root PLANNING_DOCS/ directory are
# written by several agents at once. Write replaces the whole file and Edit is a
# read-modify-write of the whole file, so either one discards lines another agent
# appended since the read. Appending via the shell (`>> file`, O_APPEND) does not.
#
# Deny only when BOTH hold:
#   - the basename is progress.txt or messages.txt, and
#   - the path is under a PLANNING_DOCS/ whose parent is a git repo root
#     (.git dir in a normal checkout, .git file in a worktree).
# Files of the same name anywhere else are none of this hook's business.
set -uo pipefail

f=$(jq -r '.tool_input.file_path // ""' 2>/dev/null) || exit 0
[ -n "$f" ] || exit 0

case "$f" in
  */PLANNING_DOCS/*) ;;
  *) exit 0 ;;
esac

case "${f##*/}" in
  progress.txt|messages.txt) ;;
  *) exit 0 ;;
esac

# Everything before the first /PLANNING_DOCS/ segment must be a repo root.
repo_root=${f%%/PLANNING_DOCS/*}
[ -e "$repo_root/.git" ] || exit 0

# Built in bash, not inside the jq program: the example command contains single
# quotes and backslashes, which a single-quoted jq program cannot carry intact.
read -r -d '' reason <<EOF
$f is an append-only multi-writer log. Write replaces the file and Edit is a
read-modify-write of it, so either one silently discards lines other agents
appended since your last read. Append through the shell instead, one short line
per invocation:

  printf '%s\\n' "[\$(date -u +%FT%TZ)] <you>: <one line>" >> $f

Use >> and never >. Reading the file with any tool is fine.
See PLANNING_DOCS/README.md, "Appending".
EOF

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
exit 0
