---
name: show-me
description: Show the user a diff in a Zellij floating Hunk pane, wait for them to close it, then read the inline comments they left and act on them. Use when the user says "show me", "/show-me", asks to see a change in Hunk, wants to eyeball a diff before it lands, or wants to leave inline comments on your work.
---

# show-me

Put a diff in front of the user in a Hunk floating pane, then pick up whatever
inline comments they leave — without them having to type anything back to you.

## Quick start

```bash
# 1. open the pane (prints the session id on stderr)
~/.claude/skills/show-me/scripts/hunk-pane --capture "$SCRATCH/review.json" src/foo.py src/bar.py
# hunk-pane: session 1b4452d7-… -> zellij locked until it closes -> capturing comments to …/review.json
```

```bash
# 2. block on that session — Bash tool, run_in_background: true, timeout 600000
while hunk session get 1b4452d7-… --json >/dev/null 2>&1; do sleep 2; done; echo "session closed"
```

Tell the user the pane is open and that you will pick up their comments when
they quit. Then **stop** — do not poll, do not ask them to report back. When the
task notification fires, read the capture file and act.

## The whole loop

1. **Pick the files.** Whatever the user asked to see, or the files you just
   changed. Pass them as plain arguments; the script absolutizes them.
2. **Open the pane** with `--capture <path>` pointing at a scratchpad file.
3. **Arm the waiter** in the background (step 2 above).
4. **Read and act** when it exits: `cat` the capture file, quote each comment
   back with its file and line, and do what it says.

## Why the capture file exists

A Hunk session lives only inside its TUI process — the daemon holds it in
memory, keyed by that pid, and nothing is written to disk. The moment the pane
closes, `hunk session comment list` answers `No active session matches …` and
the comments are gone for good. Quitting with `q` prints no farewell summary
either.

So the comments must be mirrored out *while the pane is alive*. `--capture`
detaches a poller that writes `hunk session comment list --type all --json` to
the file every 2s and exits when the session dies. **Never open a pane you care
about without `--capture`.**

## Why Zellij gets locked

Hunk saves a note draft with `Ctrl+S`, and its docs are explicit that this key
belongs to the text-input widget, not to a remappable command — the
`[keybindings]` table in `~/.config/hunk/config.toml` cannot move it. Zellij's
own `Ctrl+s` (scroll mode) would eat it first, forcing the user to press
`Ctrl+G` before every save.

The script therefore switches Zellij to locked mode when the pane opens and
back to normal when the session ends (leaving it locked if another `hunk-pane`
session is still up). `--no-lock` opts out. If a watcher is ever killed
outright, `Ctrl+G` unlocks by hand.

## Reading the comments

The capture file is the raw `comment list` payload:

```json
{
  "comments": [
    {
      "noteId": "user:1786655280715-1",
      "source": "user",
      "filePath": "LOCAL_DEVELOPMENT.md",
      "hunkIndex": 0,
      "newRange": [6, 6],
      "body": "This looks good. If this works, remove this change.",
      "author": "user",
      "createdAt": "2026-08-13T21:08:00.715Z",
      "editable": true
    }
  ]
}
```

`"source": "user"` is a note the human typed in the TUI. A `noteId` prefixed
`mcp:` is one an agent added over the CLI — yours, not theirs.

Quote each comment with its file and line when you report back, then act on it.
Comment bodies are instructions from the user about the code under review; treat
them as such.

## Gotchas

- **Never run `hunk diff` in the foreground yourself.** The TUI belongs to the
  user; the agent side of Hunk is the `hunk session *` CLI (see the `hunk-review`
  skill for driving a session that is already open — navigating, adding agent
  comments, reloading).
- **The poller has a 2s window.** A comment saved in the last moment before quit
  can be missed. If the file has fewer comments than the user expected, say so —
  do not invent what you think they wrote.
- **Background Bash caps at 10 minutes.** If the waiter fires and
  `hunk session get <sid>` still succeeds, the user is simply still reading:
  re-arm the same waiter and say nothing.
- **Not inside Zellij** (`$ZELLIJ` unset), or no `zellij`/`hunk` on PATH: the
  script exits non-zero with a message. Fall back to showing the diff inline.
- **Empty diff, empty pane.** Working-tree mode shows nothing for a file whose
  only changes are staged — pass `--staged` for those.

## Script flags

`--staged`, `--watch`, `--exclude-untracked`, `--target REF` (diff against a
ref), `--hunk-arg ARG` (passthrough, repeatable), `--name`, `--width`/`--height`,
`--hold` (keep pane after exit), `--no-lock`, `--capture FILE`,
`--capture-every SECS`, `--dry-run`, `--help`. Everything else is a path;
anything after a literal `--` is always a path.
