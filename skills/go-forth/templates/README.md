# PLANNING_DOCS — shared, branch-independent agent workspaces

This directory is the **only** place in this repo where cross-branch coordination
documents live. This file is the authority on *where files live and how state moves*.

> **Start here if you are an agent picking up work:** read this file, then read the
> `OVERVIEW.md` of the feature workspace you were given. If a
> [`ROLES.md`](ROLES.md) exists, read the section for the phase your slug is in —
> it tells you what that phase's agent is responsible for and what it is not.
>
> **The two files own different things and never restate each other.**
> `ROLES.md` owns *what each phase's agent does*; this file owns *where files
> live and how state moves* — layout, claiming, front matter, liveness,
> messaging. On duties `ROLES.md` is authoritative; on mechanics this file is.
> If they ever state the same fact two different ways, that is a **bug in one of
> them** — precedence is for gaps, not for contradictions. Stop, note it in
> `process_improvement.md`, and ask a human which one is right.

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
        OVERVIEW.md                  # feature intent, target branch; human-owned,
                                     #   and human-approved before any slug exists
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
             (and create your inbox in the same breath — see Messaging)
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

"Move forward" means something different per phase. **`ROLES.md` defines each
phase's job** — the table below maps transitions and the gating invariants this
file owns, and deliberately does not restate those definitions:

| Phase | Role (see `ROLES.md`) | Gate this file owns | Then |
|---|---|---|---|
| `0-open` | the specification agent | `ready-for-implementation:` is set | → `1-active` |
| `1-active` | the implementing agent | commit to `branch:` and push — **no PR yet** | → `2-ai-review` |
| `2-ai-review` | the review agent | reviews the branch **locally**, never a PR | → `1-active` / `0-open` / `3-human-review` |
| `3-human-review` | the PR agent | **the PR is opened here, and not before** | → `4-closed` |

A spec being *sufficient* and a spec being *ready-for-implementation* are two
different gates — see below.

**No PR exists before `3-human-review`.** `1-active` and `2-ai-review` both work
against the pushed branch directly (`git diff origin/<target-branch>...<branch>`
or an equivalent local diff) — a human should never see a slug's code on GitHub
until an agent has already judged it spec-complete. `3-human-review` means
review is happening on an **external system** (the GitHub PR) for the first
time. The owner is still an agent — its job is *responding* to review, not
waiting passively. That is why `pr:` and `branch:` are load-bearing: they are
all a fresh agent has to go on.

### Slugs that enter mid-pipeline

A human may drop a slug straight into a later phase when the work already exists
— code sitting on a branch, a design already written — instead of back-filling it
through `0-open`/`1-active`. The slug's *phase* is then right, but its acceptance
criteria are usually written for the whole job, including phases it will never
walk. A `2-ai-review` agent inherits "full test suite passes on the merged tree";
that is `1-active` work, and this role is explicitly barred from doing it.

**A criterion you are barred from meeting is grounds to route the slug back one
phase** — clean code or not, findings or no findings. Append a line naming which
criterion belongs to which phase, then `mv` it back.

Never delete or tick off a criterion to make it fit the phase you are in.
Criteria are the human's statement of what the work is; an agent that may retire
an inconvenient one has a general-purpose escape hatch from any work it doesn't
feel like doing. Whoever injects a slug can spare the bounce by stripping the
criteria that belong to skipped phases at injection time — but the receiving
agent never needs to wait for that.

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

**Blocked by more than one thing: separate the clauses with `;`.** Each clause
resolves independently by the two rules above, and the slug becomes actionable
only once every clause has:

    block-by: pipeline-artifact; waiting on cf-argo PR #198

Use `;` and nothing else. A comma, an "and", or a sentence joining two
conditions is a *single opaque free-text blocker*: it can never self-resolve,
nothing errors, and the slug quietly drops out of every future scan — a stall
that looks exactly like an empty queue. This is enforced: a `PreToolUse` hook
rejects a `block-by:` that looks compound but isn't `;`-separated.

Clearing a `block-by:` you didn't set is a front-matter edit, so it follows the same
rule as everything else here: claim the slug first (`mv ... claimed/`), edit the
field, then either keep going or release it back to `unclaimed/` — never edit a
field on a file you don't hold.

### Human-in-the-loop

`hitl:` in front matter marks a slug only a human-driven session may work. It is
not a weaker `block-by:` — a blocked slug isn't actionable by anyone, an `hitl:`
slug is perfectly actionable *with a human in the loop*:

- Running **unattended** — headless, cron, an AFK runner, any fully-bypassed
  autonomous loop — skip any slug with a non-empty `hitl:`, exactly as you skip a
  blocked one. Say so if something made it look actionable; don't claim it.
- Running **with a human in the session** — claim and work it normally. That is
  what the field is for.

Saying `Type: HITL` in the slug's prose does nothing. The scan reads front
matter, so a marker anywhere else is a note to humans, not a rule.

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
    block-by: <a slug name, `;`-separated clauses, free text, or empty — see Blocked>
    hitl: <non-empty if only a human-driven session may work this — see Human-in-the-loop>
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
    target-branch: <the one branch every slug in this feature builds on and PRs into>
    issue: <url, if there is one>
    approved: <empty until a human approves this overview — see below>
    ---

Resolve `target-branch` from the repo's own conventions (`AGENTS.md` / `CLAUDE.md`)
at the time the workspace is created — never copy a version number out of this
template, and re-check it before a long-lived workspace opens its next PR, since
release branches get cut, merged, and deleted underneath you.

...then the intent of the feature, its scope, and any constraint that spans slugs.
Read it before claiming anything. An agent that thinks it should change something
proposes that in its own slug doc under a `## Proposed overview changes` heading —
it does not edit `OVERVIEW.md` directly.

### Approval gates the first slug

`approved:` works exactly like `ready-for-implementation:` on a slug, one level
up: **empty means not approved, and only a human sets it.** An agent never sets
it, including the agent that drafted the overview.

**Write no slug into a workspace whose `approved:` is empty.** Until a human
sets it, the workspace holds `OVERVIEW.md` and nothing else — no slug docs, and
no scaffolded phase directories to put them in. Discuss the slugs you have in
mind with the human in conversation, or sketch them inside the draft overview
itself; do not create the files.

Three reasons this gate is worth the wait:

- Slugs inherit their scope, target branch, and cross-cutting constraints from
  the overview. Every slug written against a draft has to be re-read, and often
  rewritten, once the human moves a boundary.
- The phase machinery is autonomous. A slug in `0-open/unclaimed/` is an
  invitation, and a headless agent will accept it — grilling a human, splitting
  tickets, and spending real work on a premise nobody signed off on.
- The overview is the human's statement of what the feature *is*. Slugs written
  first quietly become that statement instead, and the human ends up reviewing
  an agent's decomposition rather than writing the intent.

Once `approved:` is set (`yes` is enough; a short note is fine too), the
workspace is open for business: scaffold the phase directories if they aren't
there yet, and write slugs normally. Approval is per-workspace and does not
expire — a later change of direction is an ordinary edit to `OVERVIEW.md`, not
a re-approval.

An agent that finds slugs already sitting in a workspace with an empty
`approved:` has found a real inconsistency: say so, and ask the human whether to
approve the overview or bin the slugs. Don't set the field yourself to make the
contradiction go away.

A workspace with **no `approved:` field at all** pre-dates this rule. Treat its
existing slugs as approved and keep working them, but mention the missing field
so the human can add it; don't start a *new* slug there until they have.

## Liveness

Identity is a **session id**: `$CLAUDE_CODE_SESSION_ID` in Claude Code. Outside
Claude Code, mint a short unique id for the process (e.g. `pi-b85054f6`) and use
that. Either way, identity is per-*process*, not per treehouse lease — leases are
recycled from a pool, so a lease name can belong to a different agent an hour later.

A claim is dead only when **both** signals say so:

    kill -0 <pid> 2>/dev/null || echo pid-unreachable   # 1. process not visible
    find <slug>.md -mmin +30 | grep -q . && echo stale  # 2. and doc untouched

`kill -0` on its own is not enough, and reading it as "alive or dead" is wrong.
It answers *"is this pid visible from where I am running?"* — three states
collapse into two, because **alive-but-invisible fails identically to dead**. An
interactive session and a headless runner routinely share a `PLANNING_DOCS/`
without sharing a process table, and the probe then reports a perfectly healthy
owner as gone. The failure is one-sided: a recycled pid reading as alive is
harmless (you leave the slug alone), while a live pid reading as dead costs you
the thing this mechanism exists to protect — you steal a working agent's slug and
act on stale information, on GitHub, where it is visible.

The doc's mtime is the second signal, and it is observer-independent: a working
owner appends as it goes. Unreachable pid **and** a doc untouched for 30 minutes
is a real death. Either one alone is not — if the pid is unreachable but the doc
is fresh, leave the claim and pick something else.

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

Each agent owns an inbox at `PLANNING_DOCS/workers/<session-id>/messages.txt`.
**Creating it is part of claiming** — one gesture with the `mv`, not a startup
step to remember separately:

    mv 1-active/unclaimed/<slug>.md 1-active/claimed/<slug>.md
    mkdir -p "PLANNING_DOCS/workers/$SESSION_ID"
    touch    "PLANNING_DOCS/workers/$SESSION_ID/messages.txt"

Holding a claim with no inbox means the one way to reach you doesn't exist, and a
sender can't distinguish that from silence — a workspace-wide direction change
then has nowhere to go but `progress.txt` and hope. A sender creating the missing
directory doesn't fix it either: that solves delivery, not reading, and an agent
that never made an inbox has no reason to look in one.

If you find a **claimed** slug whose owner has no inbox, note it in the doc
("owner `<id>` has no inbox — unreachable") and pick something else. **It is not
grounds to reclaim.** A missing directory says nothing about whether that agent is
alive; liveness has its own two signals above, and this one would fire only
against runners that create inboxes by hand.

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

**Keep it short by promoting, not by accumulating.** As it grows, anything still
*binding* — a decision several slugs depend on, a direction that still holds —
belongs somewhere durable: the slug doc that owns it, or a `## Proposed overview
changes` note for `OVERVIEW.md`. Once it lives there, append a line saying so:

    [ts] <you>: promoted the collect_pipeline rejection decision into
    <slug>.md; entries above 2026-07-30 are trimmable

Agents promote and mark; **the human truncates.** Trimming is a read-modify-write
of a multi-writer log — precisely what the hook blocks — so an agent doing it
through the shell would silently eat any append that landed mid-operation.

**A question two slugs both need answered is the common case.** Answer it once,
say in `progress.txt` which slug owns the answer, and put a pointer in the *other*
slug's doc. The pointer is the part that matters: `progress.txt` only reaches
agents that start after it was written, and sibling slugs have no ordering
guarantee — both can already be in flight, each about to answer the same question
its own way, with nothing detecting the conflict.

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
