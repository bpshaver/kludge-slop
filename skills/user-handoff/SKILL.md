---
name: user-handoff
description: Hand a task off to the human to implement themselves — write a short Markdown task doc, confirm they understand it, then watch the working directory in the background and post running commentary as they edit, including targeted lint and test runs on the files they touch. Optionally calibrates on the human's understanding via /quiz-me (or a plain Q&A substitute) before the doc is written, and can scaffold a skeleton implementation/test file if asked. Use when the user wants to try implementing something themselves, wants to code while the AI just checks over their shoulder, or says things like "let me take this one", "I'll write this myself", "watch me work", or "hand this off to me".
---

# User Handoff

## Quick start

0. This skill requires the working directory to be a git repo (the watcher uses `git status`/`git diff` for change detection — there's no non-git fallback). Check `git rev-parse --is-inside-work-tree`; if it fails, ask the user whether to run `git init` before doing anything else.
1. Before writing anything, ask the user via `AskUserQuestion` (batched into one or two calls, max 4 questions per call): whether to open an editor pane (only if `$ZELLIJ`/`$EDITOR` are set), whether to speak noteworthy commentary aloud via `say`, how (if at all) to calibrate on implementation preferences and understanding before the doc is written — via `/quiz-me`, a plain Q&A substitute, or not at all — and whether to scaffold a skeleton implementation file and/or a skeleton test file. If the task looks non-trivial, also ask whether they'd like a separate `/quiz-me` pass once they're done *implementing*, to check their understanding of what they wrote.
2. If they opted into calibration, run it now — `/quiz-me` in its grilling mode, or the plain-question substitute — before drafting anything, and let what it surfaces size the doc's level of detail.
3. Write `USER_HANDOFF_<task-name>.md` describing the task, in the repo root, incorporating whatever preferences and understanding-checks came out of steps 1-2.
4. Cat the doc's full contents into the conversation, and get explicit confirmation the user understands it — don't start watching until they say so.
5. If they opted into a skeleton implementation and/or test file, create them now — a bare function stub and, if requested, a failing skeleton test, nothing more.
6. If they opted into an editor pane, open the task doc and the relevant files (including any skeletons just created) in `$EDITOR` in a new pane.
7. Detect (or ask about) lint/test tooling — see [REFERENCE.md](REFERENCE.md).
8. Start `scripts/watch.sh` via the `Monitor` tool (`persistent: true`) so its output streams into the conversation as commentary — this also watches the task doc itself, not just code, so edits to it (checked-off criteria, questions) show up too.

## Workflow

### 0. Require a git repo

This skill's change detection is git-based (`git status --porcelain` to enumerate changes, `git diff` to show them) — there is no plain-mtime fallback. Before anything else:

```bash
git rev-parse --is-inside-work-tree
```

- If that succeeds, continue to step 1.
- If it fails, ask the user directly (a quick yes/no, no need to fold it into the batched `AskUserQuestion` call below) whether to run `git init` in that directory. If they say yes, run it and continue. If they decline, stop here — say plainly that the skill can't provide its watch/commentary loop without git, rather than silently degrading to noisier polling.

### 1. Ask up front

Before drafting the task doc, ask via `AskUserQuestion` — split across two batched calls if more than 4 items apply (max 4 questions per call), rather than as separate conversational back-and-forth:

- **Editor pane** — only include this question if `$ZELLIJ` and `$EDITOR` are both set (see step 6 below); there's nothing to offer otherwise.
- **Spoken commentary** — do they want noteworthy events also spoken aloud via `say` this session? (See step 7 for what "noteworthy" covers and how long the preference lasts.)
- **Calibration before the doc is written** — how (if at all) do they want to nail down implementation preferences and confirm they understand the task before you draft the doc? Offer: "Run `/quiz-me`" (only if that skill is available), "Just ask me a few questions here" (a plain substitute — see step 2), and "No, use your judgment" (skip straight to drafting). This is the entry point into step 2, and replaces asking for free-text preferences in isolation — the point isn't just to collect preferences, it's to check the human actually has them clear in their head.
- **Skeleton implementation file** — offer to create the target file now with just a stub of the function/class named in the task (signature + `raise NotImplementedError` or the language's equivalent, nothing else). Default recommendation is "no" — a bare stub is low-risk, but scaffolding anything more starts prescribing the human's approach, which undercuts the point of them implementing it themselves.
- **Skeleton test file** — offer to create a matching test file (if one doesn't already exist) with a skeleton test that currently fails against the stub — a red starting line for TDD-style work. This is independent of the implementation-skeleton question above; the human can want one without the other.
- **`/quiz-me` afterward** — only ask this if the task looks non-trivial (multi-file, tricky control flow, a real algorithm, anything more than a one-line stub). Frame it as a separate, later pass distinct from step 2's calibration: once they say they're *done implementing*, to check their understanding of what they wrote (step 10). Skip this question entirely for trivial tasks — don't make the user dismiss it every time.

Record every answer — they shape steps 2, 3, and 5, and some persist for the rest of the session (say preference in step 7, the post-done quiz-me opt-in for step 10).

### 2. Calibrate before writing (quiz-me or a plain substitute)

If the user opted out of calibration in step 1, skip straight to step 3.

- **If they chose `/quiz-me`**: invoke it in its grilling mode — interviewing them for implementation decisions, judgment calls, and anything about the task that needs human input. There's no code or diff yet, so this isn't the review-a-diff half of that skill; it's the "resolve open branches of the decision tree" half.
- **If `/quiz-me` isn't available, or they picked the plain substitute**: do the same thing without the skill — ask a handful of direct questions yourself (approach, data structures, edge cases they care about, a comprehension check or two on the trickier parts of the task) via `AskUserQuestion` or plain conversation.
- Either way the goal is the same: find out how much the human already has clear in their head. Someone who nails the tricky parts unprompted needs a terser doc; someone who's shaky on an edge case needs it spelled out explicitly in Acceptance criteria.

Fold whatever this surfaces into the doc you write next — don't discard it.

### 3. Write the task doc

Write the doc directly in the repo root — not in a hidden or nested directory, it needs to be easy for the human to spot. Name it `USER_HANDOFF_<task-name>.md`, where `<task-name>` is a short kebab-case slug you choose that identifies the task (e.g. `USER_HANDOFF_fibonacci-in-main.md`, `USER_HANDOFF_add-retry-logic.md`).

```md
# <Task title>

## Goal
<1-3 sentences on what "done" looks like>

## Context
<relevant files, prior discussion, constraints — link file paths, don't paste whole files>

## Acceptance criteria
- [ ] <concrete, checkable criterion>
- [ ] ...

## Out of scope
<anything explicitly not part of this task, if relevant>
```

Keep it short — this is a handoff note, not a spec. Pull the content from the current conversation plus whatever came out of steps 1 and 2; don't invent scope that wasn't discussed. Calibrate the level of detail to what step 2 surfaced: spell out edge cases explicitly in Acceptance criteria if the human seemed shaky on them, keep it terser if they were already fluent.

### 4. Confirm before watching

Immediately before scaffolding or starting the watcher, cat the doc's full contents into the conversation (don't just reference the path — the human should see the whole thing inline) and ask them to confirm it matches their understanding of the task. Only proceed to steps 5-6 once they say yes — if they push back, revise the doc first. Do not start the watcher speculatively.

### 5. Scaffold skeleton files (optional)

If the user opted into a skeleton implementation file in step 1, create it now that the doc (and its acceptance criteria) are confirmed:

- Create the target file at the path called out in the doc's Context section, containing only the function/class signature named there, a stub body (`raise NotImplementedError` in Python, or the language's equivalent), and at most a one-line docstring pulled from the Goal.
- Don't add anything beyond that one signature — no helper functions, no internal structure, no partial logic. Prescribing more than the bare entry point defeats the purpose of the human asking to do this themselves.

If the user opted into a skeleton test file in step 1:

- Check whether a test file already exists for the target module. You need the naming convention for this — if you haven't sampled it yet (that normally happens in step 8), do a quick check now (`find . -name 'test_*.py'` vs `*_test.py`, or the JS/TS equivalent) rather than waiting; reuse the result in step 8 instead of re-detecting.
- If none exists, create one with a skeleton test per acceptance criterion (at most a small handful) that calls the stub and asserts the expected behavior. It will fail against the stub — that's expected, and is the point: a red starting line for TDD-style work.
- If a test file already exists, leave it alone — this is additive scaffolding, never an overwrite of existing tests.

Tell the human explicitly which file(s) you created and that they're stubs, so it isn't a surprise when they open their editor.

### 6. Open an editor pane (optional)

If the user opted into this in step 1, open the task doc alongside the files the human will actually edit — including any skeleton files just created in step 5 — in a new pane:

```bash
zellij action new-pane --direction right -- $EDITOR USER_HANDOFF_<task-name>.md <file-x> <file-y>
```

- Direction defaults to `right`; ask if the user wants a different layout (`down`, or let Zellij pick the biggest available space by omitting `--direction`).
- `<file-x> <file-y> ...` are whatever files the task doc's Context section calls out as what the human needs to edit — pass the actual paths, not placeholders.
- This is only tested against Zellij. The same idea should work in tmux (`tmux split-window -h -- $EDITOR ...`) or other multiplexers, but treat that as unverified — confirm with the user before assuming it behaves the same way.

### 7. Spoken commentary

If the user opted in during step 1 (or opts in later, unprompted — e.g. "use say", "use 'say'"):

- In step 11, when something worth relaying comes in, also run `say "<condensed one-sentence version>"` alongside the text commentary — don't pipe raw lint/test output through it, that's unlistenable.
- This is a per-session choice made by the agent relaying commentary, not something built into `scripts/watch.sh` — the script only ever prints to stdout.
- If not on macOS, ask what TTS is available rather than assuming `say` exists.
- The preference isn't scoped to watcher events only — once on, keep using `say` for any concise, important feedback for the rest of the session (e.g. answering "any feedback on the code?"), not just `[lint]`/`[test]` notifications.
- It persists across the whole session once granted, whether given upfront or opted into mid-session — don't ask again each time something worth saying comes up. Only stop when the user explicitly asks you to.

### 8. Choose lint/test commands

Read [REFERENCE.md](REFERENCE.md) and inspect the repo for existing lint/test config. Prefer whatever the project already uses, scoped to just the files being edited (for speed). If nothing is configured for the language in play, default to `ruff check` + `mypy --strict` for Python — but say so and let the user object before you start, since they may want something else or lack those tools installed. For anything you're not confident about (unfamiliar stack, multiple languages, no config found), ask rather than guessing.

Also sample existing test files to learn the naming convention (`test_<name>.py` vs `<name>_test.py`, or the JS/TS equivalent) so the watcher can flag edits that don't have a correspondingly-named test — skip this if step 5 already sampled it for the skeleton test file.

### 9. Start the watcher

Invoke `Monitor` with `command` set to the bundled script, passing detected config via env vars (see the header of `scripts/watch.sh` for the full list):

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)" \
WATCH_PATH="." \
LINT_CMD='ruff check {} && mypy --strict {}' \
LINT_EXTS='\.py$' \
TEST_CMD='python -m pytest {}' \
TEST_NAME_TEMPLATE='test_{}.py' \
bash /path/to/this/skill/scripts/watch.sh
```

Use `persistent: true` and a description like `"handoff watch: <task title>"`. The script itself does the polling (every 5s by default) and only prints a line when something actually changed — an edited file, a lint result, a test result, a naming-convention note, or an edit to the task doc itself — so it won't spam clean ticks.

### 10. If they opted into a post-implementation `/quiz-me` pass

When the user says they're done (or the doc's acceptance criteria all look checked off), and they opted into this in step 1, offer to run the `/quiz-me` skill against the diff they produced before wrapping up — don't launch it unprompted, just remind them of the earlier opt-in and confirm they still want it now, since "done" may arrive much later in the session than the ask did. This is quiz-me's review-a-diff mode (quizzing understanding of actual code changes), distinct from the grilling mode used in step 2 before any code existed — don't conflate the two if the user opted into both.

### 11. While it runs

- Relay the notifications as brief, human commentary rather than raw output dumps — a sentence of framing plus the interesting bit (e.g. "ruff flagged an unused import in `foo.py`") reads better than pasting the tool's stdout verbatim.
- Watch for `[handoff-doc]` events specifically — the human may check off acceptance criteria or leave a question directly in `USER_HANDOFF_<task-name>.md`. Read the diff and respond in conversation (answer the question, acknowledge the checked-off item) rather than treating it like a routine lint/test event.
- Don't jump in and fix things yourself — the point is the human is doing the implementation. Point out issues; let them decide whether/when to address them.
- If the user asks to pause or wraps up, stop the monitor with `TaskStop`, run step 10 if applicable, and mention the `USER_HANDOFF_<task-name>.md` doc can be deleted once the task lands.

## Notes

- One watcher per task/repo is enough — check `TaskList` before starting a second one.
- This skill requires a git repo (step 0) — `scripts/watch.sh` hard-fails if the working directory isn't inside a git work tree. There is no non-git fallback; if the user declines `git init`, don't start the watcher.
- This skill only narrates and lints/tests during the watch — the one exception is the optional skeleton implementation/test file(s) it creates up front in step 5, and only when the human opts in. After that, it never touches the human's files again.
