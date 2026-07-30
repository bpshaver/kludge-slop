# PLANNING_DOCS — shared, branch-independent agent workspaces

This directory is the **only** place in this repo where cross-branch coordination
documents live. This file is the authority on *where files live and how state moves*.

> **Start here if you are an agent picking up work:** read this file, then read the
> `OVERVIEW.md` of the feature workspace you were given. If a
> [`ROLES.md`](ROLES.md) exists, read the section for the phase your slug is in —
> it gives you flavor and role-specific instructions (e.g. "you are the PR agent;
> arm a background poller for GitHub comments"). `ROLES.md` is a first draft and does
> not override anything in this file; if the two disagree, this file wins.

It is:

- **Untracked.** Ignored via the global excludesFile (`~/.gitignore`), so no commit,
  no `.gitignore` edit, and no branch can ever hide or delete it.
- **Physically one directory**, in the main checkout at `<repo-root>/PLANNING_DOCS`.
  Every other worktree has a symlink of the same name pointing here, so
  `PLANNING_DOCS/foo.md` resolves to the same file from every worktree.
- **Immune to branch switches.** Ignored, untracked files are untouched by
  `checkout`/`switch`, including treehouse's `checkout -B` branch stealing.

If the symlink is missing in a worktree (fresh pool worktree, or one that was
`treehouse return --force`'d, which cleans ignored files), recreate it with:

    ~/.claude/bin/shared-docs-link

Cleaning a worktree destroys a *pointer*, never the real directory.

## What goes here vs. in `docs/design/`

| | `PLANNING_DOCS/` | `docs/design/*.md` |
|---|---|---|
| Tracked | no | yes |
| Lifetime | spans many branches and PRs | ships with the branch it describes |
| Audience | agents and the human coordinating work in flight | reviewers, future readers |
| Content | live plans, work in progress, status | the design as merged |

A plan here can *graduate* into a committed `docs/design/` doc when the work is real
and scoped to one branch. Don't duplicate: link from the plan to the design doc.

**Never link the other way.** A `docs/design/*.md` doc is tracked and ships with the
branch; a slug is untracked, local to whoever's `PLANNING_DOCS/` checkout it lives in,
and gone (or meaningless — a different feature entirely) to every other reader of that
file, including anyone on another machine, a future branch, or a code reviewer on
GitHub. Referencing a slug path or slug name from a committed design doc points readers
at something that, from their side, was never there. If a design doc needs to explain
*why*, inline the reasoning or link the PR/issue instead — those are the tracked,
durable equivalents.

## Layout

Each **feature** is a self-contained workspace. An agent is given one workspace at
startup and never looks outside it.

    PLANNING_DOCS/
      README.md                      # this file — conventions, authoritative
      ROLES.md                       # per-role flavor/instructions; non-authoritative
      process_improvement.md         # pain points on this workflow itself; see below
      workers/
        <session-id>/messages.txt    # one inbox per live agent (global; see Messaging)
      <feature-slug>/                # a workspace
        OVERVIEW.md                  # feature intent, target branch; human-owned
        progress.txt                 # sparse high-signal feed for this feature
        0-open/          unclaimed/ claimed/
        1-active/        unclaimed/ claimed/
        2-ai-review/     unclaimed/ claimed/
        3-human-review/  unclaimed/ claimed/
        4-closed/                    # terminal — no split, nothing claims it
                                     #   each holding <slug>.md

Slug names need to be unique only within a workspace. Globs that walk phases must use
`[0-9]-*/` so `workers/`, `ROLES.md`, and `OVERVIEW.md` aren't mistaken for a phase.

## Status is location

A slug's phase **is** the directory it sits in. There is no `status:` field — that
would be a second copy, and copies drift.

**Every state change is exactly one `mv`.** `rename(2)` is atomic, so a race has
exactly one winner and the loser gets `ENOENT`. That is the entire concurrency
mechanism: there is no locking, and no state change is ever a read-modify-write.

    claim    mv 2-ai-review/unclaimed/<slug>.md  2-ai-review/claimed/<slug>.md
    advance  mv 2-ai-review/claimed/<slug>.md    3-human-review/unclaimed/<slug>.md
    release  mv 2-ai-review/claimed/<slug>.md    2-ai-review/unclaimed/<slug>.md
    reclaim  (same as release, when the owner is dead — see Liveness)

A failed `mv` is **not an error**. It means another agent got there first: rescan and
pick something else.

A slug must exist in exactly one location. To check:

    ls [0-9]-*/*/<slug>.md 4-closed/<slug>.md 2>/dev/null

More than one hit means someone wrote to a path after another agent had already moved
the file — see Appending.

## Picking up work

A slug in `unclaimed/` is **unowned on purpose**: the next agent to touch it arrives
in a fresh context. The standard way to start an agent is to name its workspace and
tell it to find an orphan and move it forward.

Scan **highest phase first**, and within a phase take dead claims before the queue:

    for p in 3-human-review 2-ai-review 1-active 0-open; do
      ls "$p"/claimed/*.md    # any whose owner is dead -> reclaim this one
      ls "$p"/unclaimed/*.md  # else claim the first that isn't blocked or in cooldown
    done

Stop at the first hit. Finishing work beats starting work: review-phase slugs are
closest to delivering value, and PRs rot while their branch drifts from its base.

"Move forward" means something different per phase:

| Phase | Move forward means | Then |
|---|---|---|
| `0-open` | write the spec: goal, acceptance criteria, constraints — **and get `ready-for-implementation:` set** | → `1-active` |
| `1-active` | implement it, open the PR against `target-branch` | → `2-ai-review` |
| `2-ai-review` | run code review, address findings | → `3-human-review` |
| `3-human-review` | poll the PR for human comments, respond, push fixes | → `4-closed` |

A spec being *sufficient* and a spec being *ready-for-implementation* are two
different gates — see below.

`3-human-review` means review is happening on an **external system** (the GitHub
PR). The owner is still an agent — its job is *responding* to review, not waiting
passively. That is why `pr:` and `branch:` are load-bearing: they are all a fresh
agent has to go on.

### Cooldown

If you claim a slug and cannot advance it, append a dated check line to the doc
**before** releasing it:

    checked 2026-07-29T14:40 — pr#451, no new comments since 12:10; still
    awaiting a decision on the retry budget

Skip any `unclaimed/` slug whose newest `checked` line is under **30 minutes** old.

Without this, a slug that cannot progress absorbs every agent that starts up: `mv`
doesn't change mtime, a fresh agent has no memory of trying it, and stop-at-first-hit
means it never reaches anything else. The check line is also the only way the next
agent learns what was already looked at.

Work that will never progress goes to `4-closed/` with a line saying why. Don't leave
it parked in a queue.

### Live vs. ephemeral polling

The `checked` line and cooldown above are built for the *ephemeral* case: a fresh
agent does one check-and-release pass, and the next check happens whenever
something next starts an agent on this workspace — a human, a cron, another
agent. That's the only option when nothing is actually watching in between.

An agent running **interactively** — a session that's staying open regardless —
doesn't have to fall back to that. It can hold the claim continuously and run a
real poller against the external system (GitHub, for `3-human-review`) at a tight
interval, reacting to events as they happen instead of waiting to be re-invoked.
This is the normal mode for `3-human-review` (see `ROLES.md`): don't release the
slug just to immediately reclaim it if you're already resident and watching.

A live-held claim is still an ordinary claim for Liveness purposes below — if the
session ends, the poller dies with it, `pid:` goes stale, and the slug is
reclaimable exactly like any other dead claim. There's no special-casing for "was
mid-poll"; whoever reclaims it checks `branch:`/`pr:` on GitHub directly, same as
any other reclaim.

### Blocked

`block-by:` in front matter (see below) marks a slug as not actionable regardless of
phase — most often used in `0-open`, where dependencies between tickets are usually
discovered, but not exclusive to it. Skip any `unclaimed/` slug with a non-empty
`block-by:` during scan, same as cooldown.

The field holds one of two things:

- **Another slug's name.** Resolves itself: check whether that slug is in
  `4-closed/`. If it is, the blocker is gone and the slug is actionable — no edit
  needed, the scan just treats it as unblocked.
- **Anything else** — an issue URL, "waiting on infra," a sentence. Nothing can
  check this automatically. It stays blocking until a human, or an agent acting on
  new information, clears it by hand.

Clearing a `block-by:` you didn't set is a front-matter edit, so it follows the same
rule as everything else here: claim the slug first (`mv ... claimed/`), edit the
field, then either keep going or release it back to `unclaimed/` — never edit a
field on a file you don't hold.

### Ready for implementation

`ready-for-implementation:` in front matter gates the one transition that
matters most to get right: `0-open` → `1-active`. A spec being *sufficient* —
the `0-open` agent's own judgment call, per the phase table above — is a
necessary condition for that move, but not sufficient by itself. The field
must also be set, and **only a human sets it.**

An agent working `0-open` never sets this field, no matter how complete it
believes the spec to be — including an agent that wrote the spec itself. If
the spec looks done, say so plainly in the doc (so a human skimming
`0-open/unclaimed/` knows it's ready for their sign-off) and release back to
`0-open/unclaimed/` exactly as if a real open question remained. This is not
a failure state or a special case of "blocked" — it is the normal, expected
way most specs leave `0-open`.

Empty means not ready. Once a human sets it (`yes` is enough; a short note is
fine too), the slug is eligible for the ordinary `0-open` → `1-active` move by
whichever agent next picks it up — the human doesn't have to be the one who
moves it.

## The slug document

One document per slug, and it **accretes a section per phase**:

    0-open      -> spec
    1-active    -> spec + implementation notes
    2-ai-review -> spec + implementation notes + review

Every worker writes back into this one file. There are no per-agent note files — if
something is worth writing down, the next agent to touch this slug needs it, so it
belongs here. Sections should match location: a slug in `2-ai-review/` with no
implementation notes is evidence something went wrong.

Front matter:

    ---
    owner: <session id, empty when unclaimed — see Liveness>
    pid: <process id of the owning agent, empty when unclaimed>
    block-by: <another slug's name, or free text, or empty — see Blocked>
    ready-for-implementation: <empty until a human sets it — see Ready for implementation>
    branch: <branch name, once one exists>
    worktree: <absolute path, once one exists>
    pr: <url, once one exists>
    issue: <url, if there is one>
    ---

`owner:` is informational — the claim is the `mv`, not this write — but keep it
accurate, because it is how other agents address you and how liveness is checked.

## OVERVIEW.md

One per workspace, **written by the human** (an orchestrator agent working with the
human is fine too — the point is it isn't a slug-holding worker). It carries what
every slug in the feature must agree on:

    ---
    target-branch: release/v0.0.9
    issue: <url, if there is one>
    ---

...then the intent of the feature, its scope, and any constraint that spans slugs.
Read it before claiming anything. An agent that thinks it should change something
proposes that in its own slug doc under a `## Proposed overview changes` heading —
it does not edit `OVERVIEW.md` directly.

## Liveness

Identity is a **session id**: `$CLAUDE_CODE_SESSION_ID` in Claude Code. Outside
Claude Code, mint a short unique id for the process (e.g. `pi-b85054f6`) and use
that. Either way, identity is per-*process*, not per treehouse lease — leases are
recycled from a pool, so a lease name can belong to a different agent an hour later.

A claim is dead when its `pid:` is gone:

    kill -0 <pid> 2>/dev/null || echo dead

This fails safe: a recycled pid reads as alive, so you leave a slug claimed rather
than stealing it from a live agent.

Reclaiming a dead claim is **not** the same as picking up a clean queue entry. The
dead agent's side effects live outside this directory — a pushed branch, an open PR,
half-applied review findings, uncommitted worktree changes. Read the doc, check
`branch:` and `pr:`, look at the worktree, and **append a line saying you reclaimed
it mid-phase** before moving it. The `mv` back to `unclaimed/` erases the only
evidence it was interrupted.

## Appending

**Append with `>>`, never with an editor.**

    printf '%s\n' "[$(date -u +%FT%TZ)] <you>: <one line>" >> progress.txt

A single `write()` on an `O_APPEND` fd cannot clobber a concurrent append. `Write` or
`Edit` — or any tool that reads then rewrites the whole file — silently destroys
every append that landed since it read. This applies to any file with more than one
writer: `messages.txt` and `progress.txt`.

This is **enforced, not just documented.** A `PreToolUse` hook denies any `Write` or
`Edit` whose target basename is `progress.txt` or `messages.txt` and which sits under
a `PLANNING_DOCS/` directory at a git repo root. Reading them with any tool is fine —
only writing has to go through the shell.

Writing to a path is also how duplicate slugs appear. A write to a missing path does
not fail — it *creates*. If someone moved the file while you were thinking, writing
to the path you read from produces a second copy in the old location. Re-resolve
before writing.

## Messaging

Each agent owns an inbox at `PLANNING_DOCS/workers/<session-id>/messages.txt`. On
startup:

    mkdir -p "PLANNING_DOCS/workers/$SESSION_ID"
    touch    "PLANNING_DOCS/workers/$SESSION_ID/messages.txt"

One reader, many appenders. To reach whoever is working a slug, read `owner:` from
its front matter and append one line to that inbox. Use it only when another agent
genuinely needs to know something — it is not a log. Delivery is fire-and-forget: a
message to an agent that dies before reading it is lost.

### Reading your inbox

Creating the inbox is the same either way; *noticing* a new line is not, and it
splits the same way [Live vs. ephemeral polling](#live-vs-ephemeral-polling) does.

An **interactive** agent — a session staying open regardless — can background a
follower and let lines arrive as events:

    tail -f "PLANNING_DOCS/workers/$SESSION_ID/messages.txt" &

A **headless** agent (`claude -p`, cron, an AFK runner like `ralph.sh`) cannot: a
backgrounded `tail -f` in a one-shot run has nowhere to deliver to, and the agent
is never re-invoked to see it. It has to poll instead — remember how many lines
it has already consumed (call it `N`, starting at 0) and re-read only past that:

    tail -n +$((N+1)) "PLANNING_DOCS/workers/$SESSION_ID/messages.txt"

`N` cannot live in a shell variable, since each tool call is a fresh shell — the
agent tracks it itself, re-reading `wc -l` after each poll. Poll at step
boundaries (after claiming, between chunks of phase work, before the `mv` that
moves the slug) and periodically during anything long-running, so a message that
should have changed course still arrives while it can.

An inbox outlives its reader. A headless run that received nothing should `rm -r`
its own `workers/<session-id>/` on the way out, or an N-iteration loop leaves N
empty directories behind; one with lines in it stays as a record of what was sent.

## progress.txt

One per workspace. **Sparse and high-signal only** — a slug closed, a direction
changed, something every agent working this feature would want to know. Append with
`>>`.

The narrative of *how* work went belongs in the slug document, not here. This file
exists so an agent can catch up on the feature in a few lines.

## process_improvement.md

One per `PLANNING_DOCS/` root — not per workspace. This is for friction with
the **coordination workflow itself**: this README, `ROLES.md`, the
phase/claim/liveness mechanics. Not feature content — a workspace's own
`progress.txt` is where that goes.

Any agent that hits something confusing about *how work moves through this
system* — a convention that didn't cover a case, a phase that felt like the
wrong fit, a rule worth reconsidering — writes a note. Read it occasionally
when revising this README or `ROLES.md`; it's raw material for that, not
itself authoritative on anything.

**Deliberately best-effort, unlike `progress.txt`/`messages.txt` above**: no
`PreToolUse` hook guards it, and there's no requirement to append with `>>` —
a normal `Edit`/`Write` is fine. Occasionally clobbering a concurrent write is
an acceptable cost for a low-traffic, low-stakes log; don't build locking or
an append discipline around this one.
