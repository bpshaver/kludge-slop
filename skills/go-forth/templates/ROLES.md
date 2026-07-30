# Worker roles

> **Non-authoritative.** This gives each phase's agent flavor and role-specific
> instructions — what it's like to *be* the review agent, that the PR agent should
> arm a background poller for GitHub comments, and so on. `README.md` owns layout,
> phase names, and the claim/release mechanics; where the two disagree, `README.md`
> wins. Treat this as color to fold into a role's prompt, not as a second spec.

Every unit of work is a **slug**. The slug *is* the specification — a single document
that gets written, executed against, and revised as it travels, accreting a new
section each phase (spec → + implementation notes → + review). It lives in exactly
one **phase** at a time, and each phase has a **worker role** attached to it: the
kind of agent that is allowed to claim the slug while it sits there. The role tells
you what the agent in that phase is responsible for and, just as importantly, what
it is *not*.

Phases, in the normal forward order:

    0-open → 1-active → 2-ai-review → 3-human-review → 4-closed

Not shown above: `2-ai-review` may send a slug back to `1-active` (the common
outcome — the code doesn't yet meet spec) or all the way back to `0-open` (the spec
itself was wrong). Either move is the review agent's own call, made by `mv`ing the
file — see "Who moves a slug" below.

A slug is claimed and released via `unclaimed/`/`claimed/` inside each phase
directory (see `README.md`). **Only one role ever holds a slug**, because only one
role's `claimed/` directory it can sit in at a time — a slug under review is, by
construction, not being implemented. Claiming, working, and releasing (or advancing)
is a single agent's pass through a slug; there is no other handoff mechanism and no
lock beyond the atomic `mv`.

---

## `0-open` — the specification agent

**Goal:** turn a ticket that a human wrote in thirty seconds into a specification
that an implementing agent can execute without asking anyone anything.

While a slug is in `0-open`, the agent's job is to **grill and quiz the human**. Not
to write code, not to sketch a design in isolation — to interrogate. What is actually
supposed to be true when this is finished? Which of the three readings of this
sentence did you mean? What happens in the failure case you didn't mention? Which
existing behavior is this allowed to change?

The agent keeps pushing until the ticket is *fleshed out*: the intent is explicit,
the acceptance criteria are checkable, and the constraints that would otherwise be
discovered halfway through implementation are written down.

A ticket that turns out to be several tickets **gets split**. Each piece becomes its
own slug, and every one of those pieces lands back in `0-open/unclaimed/` — a split
does not promote anything to `1-active`. Splitting is the normal outcome for
anything large; a spec that can only be satisfied by a sprawling change is a spec
that hasn't been broken up yet.

**Exit:** `mv 0-open/claimed/<slug>.md 1-active/unclaimed/<slug>.md` once the
specification is sufficient **and `ready-for-implementation:` is set** (see
`README.md`). These are two separate gates: sufficiency is this role's own
judgment call; `ready-for-implementation:` is not — never set it yourself, not
even on a spec you just finished and believe is done. If the spec looks
sufficient but that field is still empty, say so in the doc precisely so a
human skimming `unclaimed/` knows it's ready for sign-off, and release it back
to `0-open/unclaimed/` exactly as you would with a genuinely open question.
That is the normal, expected way most specs leave this phase — not a failure.

**Not this role's job:** implementing anything, deciding priority, or deciding
a spec is ready for implementation.

---

## `1-active` — the implementing agent

**Goal:** implement the ticket to its specification.

This role is a software engineer. It works from the specification it was handed and
treats that specification as its context budget: if the spec is sufficient — and by
the time a slug reaches `1-active` it is supposed to be — the agent should not need
to go re-derive intent from the human. Where the spec genuinely doesn't reach, the
agent says so in the slug doc rather than guessing silently.

Two obligations beyond writing the code:

- **Write implementation notes into the slug doc.** This is the durable record of
  what was done and what's still open, readable by anyone who picks the slug up
  later — including a future instance of this same role, if it bounces back from
  review. `progress.txt` is not this record; see below.
- **Use the messaging facility to talk to other agents** — `messages.txt` under a
  worker's own directory (see `README.md`, "Messaging"). Address a message by
  reading the recipient's session id out of `owner:` in whatever slug they hold.
  Cross-agent communication goes through that log, not through side channels and
  not through editing files another agent owns.

### `progress.txt` vs. the slug doc

Don't confuse the two. The slug doc is where *how this piece of work went* lives —
implementation notes, review findings, everything a future reader of this slug
needs. `progress.txt` is the workspace's shared, sparse, high-signal feed: append to
it only for things every agent working the feature would want to know (a slug
closed, a direction changed) — not a running narrative. See `README.md` for the
append mechanics and why they're enforced by a hook.

**Exit:** `mv 1-active/claimed/<slug>.md 2-ai-review/unclaimed/<slug>.md` once you
believe the specification is satisfied.

**Not this role's job:** renegotiating the goal, expanding scope beyond the spec, or
opening the PR.

---

## `2-ai-review` — the review agent

**Goal:** check the code against the specification, and leave the specification in
the right shape for whatever happens next.

The review agent reads the implementation as edited by the `1-active` agent and
reviews it **against the goals laid out in the specification** — not against its own
taste in architecture, and not as an open-ended bug hunt of the whole repo.

It has write access to the slug doc, in both directions:

- **Add** to it: anything that needs to be fixed or changed becomes part of the
  spec, so the next `1-active` pass has it as instruction rather than as review
  prose to interpret.
- **Remove** from it: context that has served its purpose and is no longer needed
  to carry the work forward comes out. The doc accretes sections per phase, but
  within a section it's still a working document, not an archive.

Then it **routes the slug itself** — this is the one role with three possible
destinations, and picking one is the job:

| Destination | When |
|---|---|
| `1-active/unclaimed/` | The common case. The spec is still right; the code doesn't meet it yet. |
| `0-open/unclaimed/` | The spec itself is wrong or underspecified — the work goes all the way back to being fleshed out. |
| `3-human-review/unclaimed/` | The implementation satisfies the spec. |

Summarize your findings in the slug doc either way, so the destination is legible to
whoever picks it up next — including a human glancing at `progress.txt` or the doc
itself, not just the agent.

**Not this role's job:** fixing the code itself.

---

## `3-human-review` — the PR agent

**Goal:** get the change in front of the human on GitHub, and stay responsive until
it's merged.

Two responsibilities:

1. **Open the PR against the workspace's `target-branch`** (from the feature's
   `OVERVIEW.md`), following the repository's conventions for PR body, issue
   linking, and labels.
2. **Stay responsive to GitHub, in whichever mode fits how you're running** (see
   `README.md`, "Live vs. ephemeral polling"):
   - **Interactive** — a session that's staying open regardless: hold the claim
     and run an actual poller against the PR (new comments, new reviews, merge
     status), reacting as events arrive. Don't release the slug just to
     immediately reclaim it.
   - **Ephemeral** — a fresh, one-shot invocation with nothing left running after
     it exits: do a single check-and-respond pass, then release the slug with a
     `checked` line (see `README.md`, "Cooldown") rather than sitting on a claim
     nothing is actually watching.

   Either way, this phase means review is happening on an *external* system, not
   that the agent is idle.

**Exit:** `mv 3-human-review/claimed/<slug>.md 4-closed/<slug>.md` when the human
merges the PR — that merge is the signal, detected by your poller.

**Not this role's job:** merging the PR. That is the human's act.

---

## `4-closed`

Terminal — no `claimed/`/`unclaimed/` split, nothing claims a slug here.

Reached normally by merge. A slug that will never progress (abandoned, superseded,
duplicated) also goes here — `mv` it in directly from wherever it's stuck, with a
line in the doc saying why. There's no separate "abandoned" phase; a reason line in
`4-closed/` is the record.

---

## Who moves a slug

Every move is a `mv`, and the agent holding the claim makes it — there is no human
gate baked into the mechanism itself. A human can always intervene by hand (it's
just a shell command), and the `0-open` and `2-ai-review` roles are explicitly
written to lean on human judgment before they move — but the move is the agent's to
make, not something it waits for someone else to perform.

| Transition | Made by |
|---|---|
| `0-open` → `0-open` (split into smaller slugs) | specification agent |
| `0-open` → `1-active` | specification agent, once the spec is sufficient |
| `1-active` → `2-ai-review` | implementing agent |
| `2-ai-review` → `1-active` / `0-open` / `3-human-review` | review agent, per the table above |
| `3-human-review` → `4-closed` | PR agent, on detecting the merge |

The pattern: **agents advance work end to end.** Review gates are judgment calls an
agent makes explicitly and records in the doc, not a human editing files.

---

## Open questions

1. **Who performs the `3-human-review` → `4-closed` move?** By the time a slug is
   merged, it's held by the PR agent — which is also the thing already polling
   GitHub and therefore the thing that observes the merge. This document assumes
   **the PR agent closes it**, triggered by the merge it detects.

Resolved since the previous draft: message addressing is by reading `owner:` from
the recipient's slug front matter (see `README.md`, "Messaging"); there's no separate
abandon phase — abandoned work goes to `4-closed/` with a reason line (see above).
