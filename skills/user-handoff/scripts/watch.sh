#!/usr/bin/env bash
# Background watcher for the user-handoff skill.
# Polls the working tree for edits, lints/tests only the files that changed
# since the last tick, and prints short commentary lines to stdout — each
# line becomes a Monitor notification in the conversation.
#
# Written for bash 3.2 (macOS ships this as /bin/bash) — no associative
# arrays, no mapfile. State is kept in plain files under a scratch dir instead.
#
# Requires the working directory to be inside a git work tree — change detection
# is git status/git diff based, with no non-git fallback. Exits immediately if
# not inside a repo.
#
# Config via env vars (all optional):
#   REPO_ROOT       git repo root to scope to        (default: current directory; must be inside a git work tree)
#   WATCH_PATH      path (relative to REPO_ROOT) to restrict polling to  (default: whole repo)
#   INTERVAL        seconds between polls             (default: 5)
#   LINT_CMD        command template, {} = file list, run on files matching LINT_EXTS
#   LINT_EXTS       extended-regex of extensions to lint  (default: '\.py$')
#   TEST_CMD        command template, {} = file list, run on files matching TEST_PATTERN
#   TEST_PATTERN    extended-regex identifying test files (default: '(^|/)(test_[^/]+\.py|[^/]+_test\.py)$')
#   CHECK_TEST_NAMING  1/0 — flag source edits with no matching test file anywhere in the repo (default: 1)
#   TEST_NAME_TEMPLATE how an expected test filename is built from a source basename, {} = stem (default: 'test_{}.py')
#   EXCLUDE_PATTERN extended-regex of paths to ignore even if untracked (default: common cache/build noise)
#   HANDOFF_DOC_PATTERN extended-regex identifying the task doc itself — reported with a diff instead of
#                   lint/test (default: '(^|/)USER_HANDOFF_[^/]*\.md$'), since the human may check off
#                   acceptance criteria or leave questions in it

set -uo pipefail

REPO_ROOT="${REPO_ROOT:-$(pwd)}"
WATCH_PATH="${WATCH_PATH:-.}"
INTERVAL="${INTERVAL:-5}"
LINT_CMD="${LINT_CMD:-}"
LINT_EXTS="${LINT_EXTS:-\.py$}"
TEST_CMD="${TEST_CMD:-}"
TEST_PATTERN="${TEST_PATTERN:-(^|/)(test_[^/]+\.py|[^/]+_test\.py)$}"
CHECK_TEST_NAMING="${CHECK_TEST_NAMING:-1}"
TEST_NAME_TEMPLATE="${TEST_NAME_TEMPLATE:-}"
# bash 3.2 mis-parses a literal `{}` inside a ${VAR:-default} expansion, so the
# default is set out-of-line instead of inline above.
[ -z "$TEST_NAME_TEMPLATE" ] && TEST_NAME_TEMPLATE='test_{}.py'
EXCLUDE_PATTERN="${EXCLUDE_PATTERN:-(^|/)(__pycache__|\.pytest_cache|\.mypy_cache|\.ruff_cache|node_modules|\.venv|venv)(/|$)|\.pyc$}"
HANDOFF_DOC_PATTERN="${HANDOFF_DOC_PATTERN:-(^|/)USER_HANDOFF_[^/]*\.md$}"

cd "$REPO_ROOT" || exit 1

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[error] '$REPO_ROOT' is not a git repository — this watcher requires git for change detection (git status/git diff). Run 'git init' there and restart the watcher."
  exit 1
fi
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT" || exit 1

STATE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/user-handoff-watch.XXXXXX")
trap 'rm -rf "$STATE_DIR"' EXIT

key_for() { shasum -a 256 <<<"$1" | cut -d' ' -f1; }
get_last_hash() { local f="$STATE_DIR/h_$(key_for "$1")"; [ -f "$f" ] && cat "$f" || echo "__unset__"; }
set_last_hash() { printf '%s' "$2" > "$STATE_DIR/h_$(key_for "$1")"; }
is_noted() { [ -f "$STATE_DIR/noted_$(key_for "$1")" ]; }
mark_noted() { touch "$STATE_DIR/noted_$(key_for "$1")"; }
clear_noted() { rm -f "$STATE_DIR/noted_$(key_for "$1")"; }

hash_file() {
  # empty string for files that no longer exist (deleted)
  [ -f "$1" ] && shasum -a 256 "$1" 2>/dev/null | cut -d' ' -f1
}

expected_test_name() {
  local base stem
  base=$(basename "$1")
  stem="${base%.*}"
  echo "${TEST_NAME_TEMPLATE//\{\}/$stem}"
}

echo "[watch] started — polling '$WATCH_PATH' every ${INTERVAL}s"

first_tick=1
while true; do
  # tracked modifications + untracked files, scoped to WATCH_PATH, excluding our own state dir
  files=()
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    path="${line:3}"                      # strip the 2-char XY status + 1 space
    path="${path/* -> /}"                 # rename entries: "old -> new" → "new"
    files+=("$path")
  done < <(git status --porcelain --untracked-files=all -- "$WATCH_PATH" 2>/dev/null)

  for f in "${files[@]:-}"; do
    [ -z "$f" ] && continue
    [ -d "$f" ] && continue  # defensive: git normally lists files, not dirs, with --untracked-files=all
    [[ "$f" =~ $EXCLUDE_PATTERN ]] && continue
    cur_hash=$(hash_file "$f")
    prev_hash=$(get_last_hash "$f")
    [ "$cur_hash" = "$prev_hash" ] && continue
    set_last_hash "$f" "$cur_hash"
    [ "$first_tick" = "1" ] && continue  # don't report whatever was already dirty when the watcher started

    if [ -z "$cur_hash" ]; then
      echo "[edited] $f — deleted"
      continue
    fi

    if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      stat=$(git diff --stat -- "$f" 2>/dev/null | head -1)
      echo "[edited] $f${stat:+ ($stat)}"
    else
      lines=$(wc -l < "$f" 2>/dev/null | tr -d ' ')
      echo "[edited] $f (new file, ${lines} lines)"
    fi

    if [[ "$f" =~ $HANDOFF_DOC_PATTERN ]]; then
      echo "[handoff-doc] $f changed —"
      if git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
        git diff -- "$f" 2>/dev/null | tail -n +5 | sed 's/^/    /'
      else
        sed 's/^/    /' "$f"
      fi
      continue
    fi

    if [ -n "$LINT_CMD" ] && [[ "$f" =~ $LINT_EXTS ]]; then
      out=$(eval "${LINT_CMD//\{\}/\"$f\"}" 2>&1)
      if [ -z "$out" ]; then
        echo "[lint] $f — clean"
      else
        echo "[lint] $f —"
        echo "$out" | sed 's/^/    /'
      fi
    fi

    if [[ "$f" =~ $TEST_PATTERN ]]; then
      if [ -n "$TEST_CMD" ]; then
        out=$(eval "${TEST_CMD//\{\}/\"$f\"}" 2>&1)
        echo "[test] $f —"
        echo "$out" | tail -8 | sed 's/^/    /'
      fi
      clear_noted "$f"
    elif [ "$CHECK_TEST_NAMING" = "1" ] && [[ "$f" =~ $LINT_EXTS ]] && ! is_noted "$f"; then
      expected=$(expected_test_name "$f")
      stem=$(basename "$f" | sed 's/\.[^.]*$//')
      if ! find "$REPO_ROOT" \( -name "$expected" -o -name "${stem}_test.*" \) 2>/dev/null | grep -q .; then
        echo "[note] $f has no matching test file yet (expected something like $expected)"
        mark_noted "$f"
      fi
    fi
  done

  first_tick=0
  sleep "$INTERVAL"
done
