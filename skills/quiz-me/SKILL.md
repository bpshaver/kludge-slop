---
name: quiz-me
description: Interactive session that interleaves grilling the user for decisions (implementation details, judgment calls, anything needing human input) with quizzing their understanding of a proposed solution or of actual code changes. In review mode it summarizes each change, prints the diff, and checks why the old code was wrong / new code was needed / a deletion was correct. Use when the user says "quiz-me" / "quiz me" / "quizme", wants to be tested on a design direction or a diff/PR, or wants a beat-by-beat walkthrough with comprehension checks.
---

# quiz-me

Run an interactive session that alternates between two move types. **They are fundamentally different and must never be confused by the user** — one takes the user's answer as authoritative, the other grades it. Every question carries a visible tag saying which it is (see the labeling rule below):

- **Ask for Input** (grill) — a question with **no correct answer**: a decision *you* need from the human (implementation detail, judgment call, trade-off, missing requirement). The user's choice is authoritative — you adopt it. Always surface your own read (a "Recommendation", or a "My Intention" when it's what you'd have just done — see Question mechanics). Record the answer and apply it to the work.
- **Quiz for Understanding** (quiz) — a question **with a correct answer**: a check of the human's *understanding*. Their answer will be graded, not adopted; there is a right answer and you will say whether they got it.

Interleave them. Don't run all inputs then all quizzes — follow the natural flow (e.g. ask for input on an open decision, then quiz that the human understands its consequence).

**Prefer the `grill-me` skill for the grill portions when it's available.** The `[Ask for Input]` moves are exactly what the `grill-me` skill does (relentless interviewing that resolves each branch of the decision tree). If `grill-me` is installed in this harness, use it to drive the grilling rather than improvising your own. It may not be present in every environment this skill runs in — if it isn't, run the grills inline as described here. The quizzing (`[Quiz for Understanding]`) always stays with this skill.

## Golden rules

- **Label every question — this is non-negotiable.** The user must know at a glance whether they're deciding or being tested. Prefix every question with an explicit tag: **`[Ask for Input]`** (your recommendation is on the table but their answer wins and is adopted) or **`[Quiz for Understanding]`** (there is a correct answer and their response will be graded). Never leave a question untagged, and never let a quiz read like a request for a decision or vice-versa. If the harness's multiple-choice tool has a title/header field, put the tag there too so it's unmissable.
- **In pi, prefer the `ask_user_question` tool when it is available.** It is the local equivalent of Claude Code's `AskUserQuestion`: one TUI multiple-choice question at a time, optional custom answer path, optional short note after the choice. Use it instead of plain chat whenever the harness exposes it.
- **One question at a time.** Deliver a short bit of context (a "beat"), then ask exactly one question via the built-in multiple-choice tool. Wait for the answer, respond, then move to the next. Never dump multiple questions at once — every question is preceded by its own beat of text and asked on its own.
- **Plan ahead, reveal one by one.** Work out the full set of questions you intend to ask up front (keep it in the scratchpad tracker), but only ever surface them to the user a single question at a time. The plan is for you; the user sees one beat + one question per step.
- **Re-check relevance before every question.** The plan is not a fixed script. Before asking each question, verify it's still relevant given the user's prior answers. A previous answer often renders a later question **OBE (overcome by events)** — already answered, mooted, or no longer applicable. Skip those silently or note briefly that a prior answer settled them; don't ask a question the user has effectively already resolved. Mark them resolved/dropped in the tracker and move on.
- **Draw the correct answer's position with a real RNG.** Your default habit is to place the correct answer first, and any pattern you pick by hand (rotation, "feels random") is predictable to a repeat user — so *draw the slot from an actual random source*. Before writing the options, run a shell command to pick the slot, e.g. `echo $((RANDOM % 4 + 1))` for a 4-option question (change the `4` to the option count). Record the drawn slot in the tracker, then place the correct answer there and fill the rest with distractors. Distractors must be plausible, not obvious throwaways. (Quizzes only; grills have no correct answer.)
- **Never let option text length or detail reveal the answer.** The `description` field under each option is per-option and always shown, so a longer or more convincing description on the correct option telegraphs it — and it is genuinely harder to write a convincing description for a false answer, which is exactly the tell. Keep every option's `description` matched in length and specificity: a distractor's description must be as fleshed-out as the correct one, or omit descriptions entirely for the quiz. Do NOT put the reasoning for *why* an answer is right/wrong in the option text — that belongs in grading, after the user has answered (see below). (Quizzes only.)
- **Grade every quiz immediately, and reveal the full explanation only now.** State right/wrong plainly. The detailed reasoning you deliberately kept out of the option text (per the rule above) gets delivered here — after the user has committed to an answer — regardless of whether they got it right or wrong. This is where the correct answer earns its long explanation, not in the options.
- **On a wrong answer:** give the full explanation of what the correct answer is and *why*, then ask an **easier follow-up** that isolates the concept the human missed. Keep going until they've got it before advancing.
- **On a correct answer:** confirm, then still give the full explanation of *why* it's correct (don't shortcut it just because they got it right) and note why a tempting distractor was wrong.

## Pick the phase

Detect (or ask) which phase you're in:

### Solution / design phase — an approach is proposed but not yet built
Quiz questions check understanding of **the direction**: what problem the approach solves, why this shape over alternatives, what a given decision implies downstream. Grill questions resolve the open design decisions you still need from the human. Use this phase's answers to firm up the plan.

### Review phase — code changes exist (working tree or a PR)
**Assume the human has NOT looked at the diff yet.** For each meaningful change, do this in order:

1. **Summarize** the change in a sentence or two.
2. **Print the modified code** — the actual diff/hunk (old → new), or the added/deleted lines.
3. **Attribute it:** say "I made this change."
4. **Quiz** their understanding of *why*:
   - for **modified** code — what was wrong with the old code and why it needed changing;
   - for **added** code — why the new code was needed;
   - for **deleted** code — why the old code needed to be removed.

Walk changes one at a time, most important first.

## Question mechanics

Use the harness's single-select multiple-choice tool, 2–4 options per question.

- **In pi, use `ask_user_question` when available.** Put the visible tag (`[Ask for Input]` / `[Quiz for Understanding]`) in the tool's `title` field. Put the beat/context in normal prose first; if a short reminder is still useful inside the picker, pass it via the tool's `context` field. Use `allowComment` when you want a short rationale after the choice. Use `allowOther` only when a typed custom answer is genuinely acceptable.
- **In Claude Code, use `AskUserQuestion`.** If the harness provides per-option `preview`/annotation support, use it according to the rules below.
- **If the current harness has no multiple-choice question tool, stop and surface this to the user.** Tell them the skill relies on a multiple-choice prompt that this harness doesn't provide, and ask how they'd like to proceed (for example, plain-text numbered options answered in chat). Don't silently improvise a degraded flow.

**When the harness supports answer annotations/notes, collect them in a way that does not leak the answer.** In Claude Code this is the `preview` affordance on `AskUserQuestion`; in pi this is the optional post-selection comment collected by `ask_user_question` when `allowComment` is true. Treat any note that comes back as part of the answer, not an aside.

- **`[Ask for Input]` grills — collect rationale whenever possible.** If the harness supports notes/comments, enable them by default so the user can add caveats or reasoning that affect how you'll apply the decision.
- **`[Quiz for Understanding]` — notes are optional, and must stay answer-neutral before commitment.** If the harness's note-enabling mechanism risks telegraphing the correct answer, skip it. In pi, a post-selection comment is safe because it is asked only after the answer is chosen.

- Quiz options: one correct, the rest plausible distractors. Place the correct one in the slot drawn by the RNG rule in the Golden rules (`echo $((RANDOM % option_count + 1))`), and keep every option's `description` even in length/detail so the text doesn't give it away.
- Grill options: the realistic choices. **Always signal where you stand** — a grill is a genuine decision, and the user is asking for your read, not a neutral menu. Use two clearly distinct tiers, and it's fine to lead with your pick (the one place first-position is allowed):
  - **Recommendation** — you have a hunch or a lean but aren't certain. Mark the option "(Recommended)" and say why in a sentence.
  - **My Intention** — you would simply *have done it this way* if you weren't being asked to grill the user for input. Make this **very clear**: mark it "(My Intention)" (not merely "Recommended") and state plainly that this is what you'd have done by default, so the user knows they're overriding your intended action if they pick otherwise.
- Keep each question self-contained; put the needed context in the beat before it, not buried in option text.

## Running the session

1. Confirm the subject (a plan, a diff, a PR) and the phase.
2. For a longer session, keep a scratchpad tracker file (e.g. `quiz.md`) listing beats, questions, correct answers, and pass/fail — so you can grade consistently and summarize at the end.
3. At the end, give a short scorecard (which quizzes passed/failed, which decisions the grills settled) and offer to expand any beat.
