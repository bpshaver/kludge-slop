---
name: monitor-pr
description: Watch a GitHub PR for new comments in the background and act on them as they land — reply to every comment, implement Ben's requests directly, implement other people's only when obvious, and escalate anything questionable. Use when asked to monitor, watch, babysit, or poll a PR for comments or review feedback, or to keep an eye on a PR after opening it.
disable-model-invocation: false
user-invocable: true
argument-hint: "PR number or URL to watch"
---

# Monitor a PR

Watch one pull request for incoming comments and handle them as they arrive.

## Use a Monitor, not a cron

**Always arm a background `Monitor`. Never schedule a cron for this.**

A cron takes a full turn on every fire, whether or not anything happened. Two things
follow, and the second is the reason for this rule:

1. Most turns say "nothing new," which is noise.
2. **Every turn end fires the `Stop` hook.** On this machine that hook is
   `~/.claude/bin/attn-notify`, which pops a floating Zellij pane in whatever tab the
   user is looking at. A 2-minute cron pops that window at them every 2 minutes,
   forever.

A `Monitor` emits a line only when something actually changes, so a quiet PR produces
no turns and no popups. Nothing has to be muted, and the user still gets the popup on
the turns that matter — including when they ask a question and tab away.

Do not work around the popup by muting `attn-notify` (via
`~/.claude/run/attn-off.$ZELLIJ_PANE_ID` or otherwise). That switch is persistent and
per-pane, so it suppresses **every** notification from the pane, including the answer
to a question the user just asked. Removing the quiet turns is the fix; silencing the
notifier is not.

## Identify yourself in every comment

`gh` is authenticated as the user, so anything posted lands under **their** name and
face. A teammate reading the thread has no way to know an agent wrote it.

**Open every GitHub comment with `Claude Opus 5: `,** then the substance on the same
line:

```
Claude Opus 5: `EntityBase` enforces a biconditional, so the pair is the unit of
meaning...
```

Name the model, nothing else. Do not add whose account it posts from — the avatar
already says that, and repeating it in words reads as an apology.

This applies to replies, review comments, and issue comments alike.

## Who gets what

| Comment from | Reply | Implement |
| --- | --- | --- |
| **The user** | immediately | yes — do it, no questions |
| **Anyone else** | immediately | only if obvious, trivial, or clearly necessary |

Anything questionable at all from someone other than the user goes to the user first.
When in doubt, ask — a held change costs a message, a wrong one costs a review cycle.

When holding: still reply on the PR saying you have seen it and are checking with the
repo owner, still record the id as seen, and put the question to the user in the
terminal. Do not push the change until they answer.

## The ledger problem

Because `gh` posts as the user, **your own replies come back from the API authored by
the user.** Author is not a usable signal for "is this new."

Keep a ledger file of every comment id already handled, one per line, and check
against it. Append an id the moment that comment is dealt with.

```sh
LEDGER="$SCRATCHPAD/pr<N>-handled.txt"
grep -qx "$id" "$LEDGER" || handle_it
printf '%s\n' "$id" >> "$LEDGER"
```

Seed it with everything already on the PR when the watch starts, so old comments do
not all fire at once.

## Arming the watch

Three sources have to be polled — a review comment, an issue comment, and a review
body are different endpoints:

```sh
gh api "repos/$REPO/issues/$N/comments"   # top-level PR conversation
gh api "repos/$REPO/pulls/$N/comments"    # inline review comments
gh api "repos/$REPO/pulls/$N/reviews"     # review bodies (usually empty wrappers)
```

A review with an empty `body` is just a container for its inline comments and needs no
handling. A review with a non-empty body is a real comment.

```
Monitor({
  description: "new comments and CI failures on PR #<N>",
  persistent: true,
  command: <<poll loop>>,
})
```

The loop should emit a line only for:

- a comment id absent from the ledger
- CI turning red, keyed on the transition so it fires once, not every poll
- the PR's state, mergeability, or review decision changing

Track announced ids inside the monitor separately from the ledger. The ledger records
what you have *handled*; the monitor's own set records what it has *announced*. Without
that, an unhandled comment re-fires every poll.

Poll every 30s or slower — these are remote API calls with rate limits. Wrap each `gh`
call so a transient failure cannot kill the watch:

```sh
out=$(gh api ... 2>/dev/null || true)
```

`gh pr checks` and `gh pr view` resolve the repo from the working directory, which is
often not the repo you are watching. Pass `-R owner/repo` explicitly.

## Verify before pushing

A comment asking for a change is not a licence to skip the gate. Run the repo's own
checks — tests, type checker, linter — before pushing anything, and honour whatever
`AGENTS.md` says about branch targets and version bumps.

Watch for locally flaky tests. Re-run before reporting a failure as real; CI is the
arbiter.

## Merging is the human's act

**Never run `gh pr merge` unless the user asked for that PR to be merged, now.**
Pressing the button is theirs. "LGTM", "looks good", an approving review — none of
those are an instruction to merge.

### `--auto` is not a queue

`gh pr merge --auto` **merges immediately** when the repository has
`allow_auto_merge` turned off. There is no error and no prompt; the flag is simply
ignored and the merge happens now. A PR meant to sit in a queue until its base lands
is merged on the spot instead.

Check before you reach for it, and treat a `false` as "this cannot be queued":

```sh
gh api repos/<owner>/<repo> -q .allow_auto_merge   # false -> --auto merges NOW
```

When it is `false` and the user wants "merge as soon as X lands", do not simulate it
with a merge. Stack the branch, get it green, say it is ready, and leave the button
to them.

### Stacking a PR behind another

Retargeting is safe and is usually what "stack B behind A" should mean:

1. Merge A's head branch into B's branch — a merge, not a rebase, so B's branch is
   fast-forwarded rather than rewritten. No force-push, so review threads and
   approvals survive.
2. Run the full gate on the merged tree.
3. Push, then `gh pr edit <B> --base <A-head-branch>`.

B's diff then shows only B's own changes, and GitHub retargets B to A's base
automatically when A merges. That is the whole trick — it needs no merge of B.

If B's branch is checked out in a worktree you do not hold, push by refspec from a
worktree you do: `git push origin HEAD:<B-branch>`.

## Stopping

`TaskStop` the monitor when the PR merges or closes, or when the user says to stop.
Say which task id you stopped.
