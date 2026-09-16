#!/usr/bin/env bash
# PreToolUse(Write|Edit): reject a compound `block-by:` that isn't `;`-separated.
#
# PLANNING_DOCS/README.md ("Blocked") gives `block-by:` two shapes: a slug name,
# which self-resolves once that slug reaches 4-closed/, or free text, which only a
# human clears. Two blockers are written as `;`-separated clauses, each resolving
# independently.
#
# Join two conditions with a comma or an "and" instead, and the whole value reads as
# one opaque free-text blocker: it never self-resolves, nothing errors, and the slug
# silently drops out of every scan. This hook makes that failure loud.
#
# Deliberately narrow. It only fires when a clause looks like a slug name
# (kebab-case, no spaces), so an ordinary sentence containing a comma -- "waiting on
# infra, which is down" -- is left alone.
set -uo pipefail

input=$(cat)
f=$(jq -r '.tool_input.file_path // ""' <<<"$input" 2>/dev/null) || exit 0
[ -n "$f" ] || exit 0

case "$f" in
  */PLANNING_DOCS/*.md) ;;
  *) exit 0 ;;
esac

repo_root=${f%%/PLANNING_DOCS/*}
[ -e "$repo_root/.git" ] || exit 0

# Write carries the whole file; Edit carries only the replacement text.
body=$(jq -r '.tool_input.content // .tool_input.new_string // ""' <<<"$input" 2>/dev/null) || exit 0
[ -n "$body" ] || exit 0

value=$(grep -m1 -E '^block-by:' <<<"$body" | sed -E 's/^block-by:[[:space:]]*//; s/[[:space:]]+$//')
[ -n "$value" ] || exit 0
case "$value" in *";"*) exit 0 ;; esac

# No separator at all -> a single blocker, whatever its shape. Nothing to say.
printf '%s' "$value" | grep -qE ',| and ' || exit 0

# Only complain when at least one clause is slug-shaped: that is the clause that
# would have self-resolved, had it been written as its own clause.
slug_like=$(printf '%s' "$value" \
  | sed -E 's/ and /,/g' \
  | tr ',' '\n' \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
  | grep -cE '^[a-z0-9][a-z0-9._-]*$')
[ "${slug_like:-0}" -gt 0 ] || exit 0

reason="block-by: ${value}

This joins two blockers with a comma or an \"and\", which makes the whole value one
opaque free-text blocker: it can never self-resolve, nothing errors, and the slug
quietly drops out of every future scan.

Separate the clauses with ';' so each resolves independently:

  block-by: <slug-name>; <the other condition>

If this really is one blocker whose text happens to contain a comma, rephrase it
without one. See PLANNING_DOCS/README.md, \"Blocked\"."

jq -n --arg reason "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
exit 0
