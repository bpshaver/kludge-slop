---
name: ask-again
description: Re-ask one unanswered question through AskUserQuestion, with all the context needed to decide on the spot, so the user can answer without scrolling back or opening the ticket. Use when /ask-again is invoked, when the user says they missed or can't find a question, when questions have piled up unanswered, or when an earlier answer did not address what was asked.
---

# /ask-again

The user did not answer. Assume they did not read your earlier message, the ticket, or the PR,
and that they cannot see text you wrote earlier in this turn. The picker is the only thing they
are sure to see, so it must carry everything they need.

## 1. List what is open

Go back through the thread and list every question still waiting on the user: a decision, an
approval of wording, a yes or no. Leave out any question that a later answer already settled.

Pick **one**. Pick the one that blocks the most work: a worker waiting, a PR that can't merge.
If two are tied, pick the older one. Ask the others later, one at a time.

## 2. Build one AskUserQuestion

One question per call. Put the context **inside the picker**, not in chat text before it.

**`question`** says, in plain words:
- what the thing is, by name and meaning: "the Gitea merge-request mode (#134)", never "#134" alone;
- what happens today, and the problem in one or two sentences;
- the exact choice to make now.

**`options`**: two to four, mutually exclusive. Your recommendation comes first, marked
"(Recommended)". Each `description` says what will happen next if the user picks it: who acts,
on what, and any cost ("Sonnet worker opens a PR", "about $1.50", "closes issue X").

**`preview`**: use it whenever the user must approve or compare **text**, such as wording, an
entry body, a config block, or a diff. Put the full text, or old text against new, in the preview of
each option. Previews are the reliable way to show text; chat text before a picker may never
be seen.

**`header`**: at most 12 characters, naming the subject, for example `aws.s3`, `#953 scope`.

## 3. Write it plainly

- Lead with the decision. Then the facts that decide it. Nothing else.
- Spell out acronyms. No internal shorthand ("OBE", "P2", "arm") unless it is explained.
- Give numbers where you have them: counts, costs, sizes.
- Do not ask the user for facts you could look up. Look them up first.

## 4. After the answer

- Say in one line which option you read and what you are doing about it. Then do it.
- If the answer is free text, read it closely. It may change the question or add a condition.
  Follow what it says, not the option you expected.
- If questions remain open, say how many, in one line. Ask the next one with this same process,
  in a separate call. Never put two unrelated questions in one picker.

## Example

Bad: "Approve the aws.s3 wording above?" The user never saw "above".

Good: `question`: "Reference library entry aws.s3 tells the compiler how to handle S3 403
errors. With the current text, 9 of 15 test compiles still raised an error on an AWS account-ID
mismatch. The new text bans comparing the ARN, role name, or account ID. Write the new text to
dev?" Option 1, "Approve (Recommended)", carries a `preview` holding the full new text with
the changed words marked. Option 2, "Change the wording", carries a `preview` holding the
current text.
