---
name: show-me
description: Open a diff for the user in a Zellij floating Hunk pane in your own tab, then read their inline comments off the live session and act on them. Use when the user says "show me", "/show-me", asks to see a change in Hunk, wants to eyeball a diff before it lands, or wants to leave inline comments on your work.
disable-model-invocation: true
---

# show-me

The Zellij front door to an ordinary Hunk session. This skill only covers
*opening the pane in the right tab and telling the user about it*. Everything
after that — reading their comments, replying inline, navigating, reloading —
is plain `hunk session *` work, documented in the **`hunk-review`** skill. Read
that one; this is the thin wrapper around it.

## Quick start

```bash
# opens in this agent's tab and prints which one
~/.claude/skills/show-me/scripts/hunk-pane src/foo.py src/bar.py
# hunk-pane: pane is in tab "Tab #21"
```

Then tell the user three things and **stop**:

1. The pane is open, and **which tab it is in** — they are probably looking
   elsewhere and saw nothing happen.
2. `Ctrl+G` locks Zellij if `Ctrl+S` (save note draft) gets eaten; `Ctrl+G`
   again releases.
3. **Leave the pane open** until you have picked the comments up. Say "tell me
   when you're done" — that is the signal.

Do not poll. Do not arm a background waiter. Wait for them to speak.

## Reading their comments

When they say they are done:

```bash
hunk session comment list --repo . --type user --json
```

That is it. The session is still alive, so the comments are simply there.
`--type user` gives you what the human typed; agent-authored notes are yours and
come back under other types.

Quote each comment with its file and line when you report back, then act on it.
Comment bodies are instructions from the user about the code under review; treat
them as such.

## The session is live — use it

The pane is not a form the user submits. While it is open you can talk back into
it, which is usually better than a wall of chat prose:

```bash
hunk session comment add --repo . --file src/foo.py --new-line 42 \
  --summary "Fixed — moved this behind the guard" --author claude
hunk session navigate --repo . --file src/foo.py --hunk 2
hunk session reload --repo . -- diff            # swap the diff after you edit
```

Reply next to the line they commented on, point their cursor at what you are
discussing, and reload once you have made changes so they re-review in the same
window instead of you opening a new pane. See `hunk-review` for the full CLI.

## Delete a comment only once they have said they know it is handled

Hunk has no resolved state and no threading, so an addressed comment looks
exactly like a live one. A pane that accumulates answered exchanges buries the
things that still need a decision. Clear them out.

```bash
hunk session comment rm <session-id> <comment-id>
hunk session comment clear <session-id> [--file <path>] --include-user|--all --yes
```

`rm` removes either side — their comment or your reply. `clear` needs
`--include-user` or `--all` before it will touch theirs.

**The trigger is their acknowledgement, not your change.** Delete the comments on
one file:line — that is what a "thread" is here — only when the *last* thing they
said on it shows they know it is handled: "got it", "thanks", "makes sense", or
any other sign they have read the answer. Then delete both sides.

A landed code change is **not** the trigger. You fixing the thing tells you it is
done; it does not tell them. Delete on that basis and you erase a request they
never saw answered, so they cannot check your work and cannot tell the difference
between "done" and "dropped".

Leave anything still open: a question they have not answered, a suggestion they
have not ruled on, and any exchange where your reply is newer than their last
comment, because they have not read it yet.

Two things about the store that will mislead you, both measured:

- **`hunk session reload` does not discard comments.** They survive the reload,
  still anchored to their old paths and line numbers. Never re-post notes after a
  reload on the assumption they were lost — list first, or you create duplicates.
- **Comments on a path that leaves the diff become unreachable.** `comment list`
  and `comment clear --file` both resolve against the current diff, so notes on a
  file you have since renamed away cannot be removed at all. They stop rendering
  and die with the session, but `rm`'s "Remaining comments: N" keeps counting
  them, so that number can exceed what `comment list` shows. Delete a file's
  comments *before* renaming it.

## Why there is no capture file any more

Hunk sessions live in the TUI process — nothing is written to disk, and the
comments die with the pane. The old version of this skill worked around that by
polling the live session into a scratch file every 2 seconds so it could read
them *after* the pane closed.

That machinery only existed to make pane-close mean "I'm done." Letting the user
say it instead deletes the poller, the capture file, the session-death waiter,
and the 2-second race where a last-moment comment went missing.

The cost is real and you must manage it: **if they quit before you read, the
comments are gone.** That is why step 3 above is not optional.

## If they quit too early

Say so plainly — "the pane closed before I read the comments, so I don't have
them." Ask them to reopen and re-add, or to paste what they wrote. **Never guess
what the comments said.**

If a particular flow genuinely needs the pane closed before you can read (the
user is leaving, or something else needs the tab), `hunk-pane --capture FILE`
still works: it detaches a poller that mirrors the session to disk and exits
when the pane dies. Treat it as an escape hatch, not the default — it brings
back the 2-second window where the last comment can be lost.

## Which tab the pane opens in

Your own — the tab holding the pane this agent runs in, not the tab the user is
looking at. The script passes `--near-current-pane`, which anchors placement to
`$ZELLIJ_PANE_ID` instead of following the client's focus. Floating panes belong
to a tab like any other, so this applies to them too.

It also runs `zellij action show-floating-panes -t <its own tab>` afterwards: a
floating pane created in a tab whose floating panes are toggled off is created
**invisible**. That toggle is per-tab, so it reveals the pane without touching
any other tab or the user's mode.

Zellij's mode is otherwise left alone. Locked mode is per-*client*, not per-tab —
locking would take the keyboard from the user wherever they happen to be. Hence
telling them about `Ctrl+G` rather than locking on their behalf.

`--follow-focus` opens over whatever they are currently reading instead; use it
only when they asked for the diff right where they are. See the `zellij` skill
for the general own-tab rule.

## Gotchas

- **Never run `hunk diff` in the foreground yourself.** The TUI belongs to the
  user; your side of Hunk is the `hunk session *` CLI.
- **Not inside Zellij** (`$ZELLIJ` unset), or no `zellij`/`hunk` on PATH: the
  script exits non-zero with a message. Fall back to showing the diff inline.
- **Empty diff, empty pane.** Working-tree mode shows nothing for a file whose
  only changes are staged — pass `--staged` for those.
- **Several sessions open?** `--repo .` is ambiguous across two panes on the
  same repo. `hunk session list --json` gives you session ids to disambiguate.

## Script flags

`--staged`, `--watch`, `--exclude-untracked`, `--target REF` (diff against a
ref), `--hunk-arg ARG` (passthrough, repeatable), `--name`, `--width`/`--height`,
`--hold` (keep pane after exit), `--near-current-pane` (own tab — the default),
`--follow-focus` (open in the user's current tab instead), `--capture FILE`
(escape hatch, see above), `--capture-every SECS`, `--dry-run`, `--help`.
Everything else is a path; anything after a literal `--` is always a path.
