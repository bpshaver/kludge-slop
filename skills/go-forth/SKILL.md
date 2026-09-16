---
name: go-forth
description: Pick up and advance work in a repo's PLANNING_DOCS/ — the shared, untracked, cross-branch coordination workspace (features, slugs, phases 0-open..4-closed). Bootstraps PLANNING_DOCS from a template if the repo doesn't have one yet. Use when asked to go forth, work the planning docs, pick up a slug or ticket, advance a feature workspace, or continue PLANNING_DOCS process work.
---

# go-forth

Defers entirely to `PLANNING_DOCS/README.md` (mechanics: claiming, phases,
front matter, liveness, messaging) and `PLANNING_DOCS/ROLES.md` (what each
phase's agent is responsible for). This file only covers finding/bootstrapping
`PLANNING_DOCS`, picking a workspace, and choosing autonomous vs. interactive
mode — don't re-derive process mechanics here, and if this file ever disagrees
with `README.md`, `README.md` wins.

## 0. Locate PLANNING_DOCS, or offer to bootstrap it

Resolve the repo's main checkout root (`git rev-parse --path-format=absolute
--git-common-dir`, then its dirname — this is where `PLANNING_DOCS` physically
lives even from inside a worktree; see `README.md`'s own description of this
once it exists). Check for `<main-root>/PLANNING_DOCS/README.md`.

**If it's missing**, this repo hasn't opted in yet. Tell the user, and invite
them to create a skeleton — don't do it silently or skip it. If they agree:

1. Create `<main-root>/PLANNING_DOCS/`, `workers/`, and copy in this skill's
   `templates/README.md`, `templates/ROLES.md`, and
   `templates/process_improvement.md` verbatim.
2. Run `~/.claude/bin/shared-docs-link` if it exists, so the current
   session's worktree gets its symlink and the ignore rule is registered
   immediately rather than waiting for the next `SessionStart` hook to fire.
   `PLANNING_DOCS` is already covered by the user's global `~/.gitignore`, so
   no per-repo `.gitignore` edit is needed either way.
2b. Two rules the templates describe as *enforced* are enforced by
   `PreToolUse(Write|Edit)` hooks, shipped in this skill's `hooks/`:
   `planning-docs-append-only.sh` (no `Write`/`Edit` on `progress.txt` or
   `messages.txt`) and `planning-docs-blockby.sh` (no comma-joined compound
   `block-by:`). Both are narrow — they inspect the path, exit 0 for anything
   else, and are safe to leave registered globally. If they aren't already in
   `~/.claude/hooks/` and registered in `settings.json`, tell the user what
   they do and offer to install them; if the user declines, say plainly that
   those two README rules are then documentation only.
3. Ask whether they want a first feature workspace scaffolded now (name,
   target branch) — if so, use `templates/OVERVIEW.md` to create
   `<slug>/OVERVIEW.md` plus `progress.txt` and the `[0-9]-*/unclaimed/`
   `claimed/` phase directories per the Layout section of `README.md`. If
   they'd rather do this by hand later, stop after step 2.

**Write no slug documents in this pass.** A workspace's `OVERVIEW.md` carries an
`approved:` field that only the human sets, and no slug exists in that workspace
until it is set (see the "Approval gates the first slug" section of
`templates/README.md`). Leave `approved:` empty, tell the user the overview is
waiting on them, and stop. If they have work in mind already, discuss it or
sketch it in the draft overview — don't create the files.

Creating the skeleton is the deliverable of this pass — stop there. Don't
fall through into section 2 below in the same invocation; let the user approve
the overview, populate a ticket, and invoke `go-forth` again to start working it.

If the user declines to bootstrap, stop.

## 1. Read the source of truth

`PLANNING_DOCS/README.md` exists (found above, or just created). Read it in
full, then `PLANNING_DOCS/ROLES.md` if present.

## 2. Pick a feature workspace

List the top-level entries in `PLANNING_DOCS/` that are workspaces (a
directory containing an `OVERVIEW.md`) — everything else (`README.md`,
`ROLES.md`, `workers/`, `process_improvement.md`, any repo-specific tooling
like a headless-runner script) is not one.

- **One workspace** — use it, no need to confirm with the user.
- **Multiple workspaces** — ask the user which one to work in (e.g. via
  `AskUserQuestion`) before doing anything else. Don't guess.
- **Zero workspaces** — nothing to work yet. Offer to scaffold a first one
  the same way as step 0.3 above, then stop.

Read that workspace's `OVERVIEW.md` before claiming anything.

**Check its `approved:` field first.** If it's empty, the overview is still a
draft: the human hasn't signed off, so there are no slugs to work and you may
not write any. Say what the overview needs to become approvable, ask for their
sign-off, and stop — never set the field yourself. If the field is empty but
slugs already exist, that's an inconsistency, not permission: raise it with the
user and let them decide whether to approve the overview or bin the slugs.

## 3. Set up identity

Per README's Liveness/Messaging sections, use `$CLAUDE_CODE_SESSION_ID` as
your session id and create your inbox:

    mkdir -p "PLANNING_DOCS/workers/$CLAUDE_CODE_SESSION_ID"
    touch "PLANNING_DOCS/workers/$CLAUDE_CODE_SESSION_ID/messages.txt"

README ties inbox creation to the claim itself; doing it here just means it is
already done by the time you claim anything. Either way it must exist before you
hold a slug — an owner with no inbox cannot be reached, and a sender cannot tell
that apart from being ignored.

## 4. Mode: autonomous vs. interactive

**Invoked with no arguments** — go fully autonomous, the way README.md
describes for a headless agent. Scan phases highest-first per its "Picking
up work" section, claim (or reclaim a dead claim) the first eligible slug,
and do that phase's job per the matching role section in `ROLES.md` (the table
in `README.md` maps transitions; `ROLES.md` is where the job is defined).
Never claim a slug whose `hitl:` front-matter field is non-empty — that one is
reserved for a session with a human in it. Don't stop to check in mid-work — poll your inbox at
the step boundaries README.md calls out, and follow its cooldown/blocked
rules. **Only return to the user once the slug has moved to its next phase
(or to `4-closed`, or been released with a `checked` line because it's
genuinely stuck) and this pass is finished.** Report what slug you worked,
what phase it's now in (or why it didn't move), and stop — don't
automatically pick up a second slug.

**Invoked with arguments** — the user has something specific in mind (a
slug, a question, a direction). Talk with them first and settle what they
want before claiming anything or entering the autonomous loop above. Only
go as far into that loop as they actually asked for.
