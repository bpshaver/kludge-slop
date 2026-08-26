---
name: ntfy
description: Ask the user a multiple-choice question on their phone over an ntfy.sh topic, then wait for the answer without ending the turn. Use when /ntfy is invoked, or when you are blocked and the user is away from the terminal.
disable-model-invocation: true
license: MIT
---

# /ntfy — ask the user on their phone and wait

Push one question to an ntfy topic. The user answers by tapping one of three buttons
in the ntfy app. A single background listener picks up the answer and you act on
it.

## Topic

The scripts resolve the topic in this order:

1. `--topic <name>`
2. `$NTFY_TOPIC`
3. `~/.claude/ntfy-topic` (a single line; currently `<your-topic>`)

## Which phone

The ntfy app is not the same on both platforms, and the difference decides what a
question may contain:

| | Buttons | Typing a reply |
| --- | --- | --- |
| **iOS** | three | not in the app — only via the web-app link in the footer |
| **Android** | three | yes, each topic has a send field |

Ask the user which one they are on the first time you use this skill, then write `ios` or
`android` to `~/.claude/ntfy-platform`. Do not ask again once that file exists.
It currently says `ios`.

`ntfy-ask` reads that file. On iOS it refuses a question with no buttons, and
refuses a body that offers an option with no button — an unbuttoned option costs
the user a browser trip and typing, when the whole point is one tap. An unknown
platform is treated as iOS, because iOS is the strict case.

**On iOS, typing a reply means the web app — and it is one tap.** Because the app
cannot compose, `ntfy-ask` ends every message with `https://ntfy.sh/<topic>`. The
user taps it, the web app opens in mobile Chrome, and they can type anything. The footer
is automatic: do not write the URL into `--body` yourself, and it does not count
against your body length.

**Keep the `https://` on that URL.** A bare `ntfy.sh/<topic>` is not tappable in
the iOS app — tapping it only copies the text to the clipboard. The full URL with
the scheme is tappable. This was tested on a real device; do not "tidy" the scheme
away.

The three buttons are still the plan. They are one tap and no typing. The link is
for what the buttons do not cover, not a substitute for offering three real ways
forward.

## The commands

```sh
S=~/.claude/skills/ntfy/scripts
```

| Script | Does |
| --- | --- |
| `ntfy-ask` | Sends one question. Prints the message id. |
| `ntfy-listen` | One session-long watch. Prints `ANSWER: <text>` per human reply. |
| `ntfy-wait <id>` | Waits for one answer, then exits. For a single one-off question. |

Send a question:

```sh
ID=$($S/ntfy-ask --title "Mongo adapter - which way?" \
                 --body "A) Add it behind a flag, off by default
B) Write the tests and design doc only
C) Park it, I move to the queue bug" \
                 --btn "A:flag it off" --btn "B:tests and doc" --btn "C:park it")
```

`ntfy-ask` also takes `--link <url>` — tapping the notification body opens that
URL. It costs you no button slot.

**`--dry-run` runs every check, prints the message, and sends nothing.**

Use it when you are testing or changing this script. Do not use it as a rehearsal
before an ordinary question — `ntfy-ask` refuses a malformed question and sends
nothing, so a real question needs no dry run first. The user settled this
rule directly.

The hard version: **never exercise this script against the live topic without
`--dry-run`.** Test posts are indistinguishable from real questions on a phone,
and they wake the user for nothing.

## Waiting

**One listener per session, never one per question.** Start it the first time you
ask, and route every later answer through it:

```
Monitor({
  command: "~/.claude/skills/ntfy/scripts/ntfy-listen",
  description: "ntfy answers on <your-topic>",
  persistent: true,
  timeout_ms: 3600000,
})
```

`persistent: true` is required. Monitor's timeout caps at one hour and the
user's answer may take two. The listener costs no tokens while the topic is quiet —
Monitor only notifies you when a line comes out.

Answers arrive as `ANSWER: <text>`. `ntfy-listen` refuses to start a second copy
for the same topic, because two would double every event. If it says it is
already listening, use the watch you have.

**The one-off exception.** If you are asking exactly one question and then you
are finished, skip the listener and run `ntfy-wait "$ID"` with Bash
`run_in_background`. It polls every 10 seconds, exits on the first answer, and
gives up after two hours.

**Never use cron for this.** A cron wake-up ends the turn and fires the stop
hook. Polling in-session does not.

**Never pipe the streaming endpoint into `grep -m1`.** `curl .../json?since=now |
grep -m1` silently misses answers — the pipe buffers and `curl` never sees the
broken pipe. Poll with `?poll=1&since=<id>` instead. That is what the scripts do.

## Rules for the question

The user is not at the terminal. They have not read the code, they do not know
your variable names, and they cannot ask you a follow-up. Write for that person.

**Three options, filling the three button slots.** ntfy allows three actions per
message, so a question has three answers and never more. Use two only when a
third would be invented filler. Put every option in `--body` as well, one short
line each — button labels get truncated on a phone.

**Every option is a way forward.** Each one must be something you can start the
second they tap it. Never offer "wait for me" or "I'll hold" — that is the one
answer that buys nothing. If you cannot think of three ways forward, you are
asking about mechanics instead of direction. Re-frame it.

**Order them: your recommendation first.** Button A is what you would do. B and C
are the real alternatives.

**Favor reversible, safe, and work-preserving.** Rank candidate options by:

1. Can it be undone cheaply? A flag defaulted off, a branch, a draft PR, a doc.
2. Can it break anything they care about? If yes, it is not option A.
3. How much useful work does it unlock before they get back?

A good third option is almost always "do the groundwork, leave the decision" —
write the tests, write the design doc, stage the change unmerged.

**Basic multiple choice, plain words.** Name the consequence, not the mechanism.
No file paths, no function names, no jargon in the question itself. If an option
needs a sentence of setup to make sense, it is the wrong option.

A question that works:

```
Title: Mongo adapter - which way?
A) Add it behind a flag, off by default   <- reversible, I keep building
B) Write the tests and design doc only    <- no production code lands
C) Park it, I move to the queue bug       <- nothing lands, other work advances
```

**No standing `bro` option.** On Android the user can type `bro` at any moment and
the listener reads it, so it costs nothing. On iOS they cannot type, so a `bro` option
would eat one of your three slots — spend it only when the stakes are high and
you doubt the question will land. The better fix is to write the question clearly
enough that `bro` is never needed. If a `bro` answer does arrive, do not answer
and do not guess: re-ask the same question in simpler language per the `bro`
skill, keeping every fact verbatim, then send a fresh question.

**Ask several small questions, not one dense one.** Send them one at a time and
wait for each. Every answer arrives on the same topic with no reference to what
it answers, so two questions in flight cannot be told apart. `ntfy-ask` refuses a
second question while the previous one is unanswered (exit 69).

**Consecutive questions must not share answer keys.** Rotate `A/B/C` to `D/E/F`
and back. The user may tap an old notification minutes or hours later, and the answer
arrives as bare text — a second `B` right after a first `B` is unreadable. Reuse
a key only when the earlier question is far enough back that no stray tap can
still arrive. `ntfy-ask` enforces this against the previous question's keys and
exits 70 on a clash; `--force` overrides it when that question truly can no
longer be answered.

This rule is what makes the log readable in practice. When one live question
offers `A/B/C` and the one before it offered `D/E/F`, a bare `C` can only belong
to one of them.

**Push detail into a GitHub issue.** When the choice truly needs more context
than three short lines, open an issue in the relevant repo with the full
write-up, then pass its URL as `--link`. The user opens it from the notification. Use
the `gh-axi` skill. Prefer the small question over the issue: ask only what
unblocks you.

**Keep the text small.** `ntfy-ask` rejects a title over 120 characters or a body
over 1000. Two reasons. The notification is read on a phone, and the topic is a
public unauthenticated feed — anyone who guesses the name can read it. Never post
secrets, credentials, customer data, file contents, or code.

## Sending a plain reply

Sometimes the user asks *you* something over the topic. That needs a statement, not a
question, so `ntfy-ask` is the wrong tool — it demands buttons on iOS. Send it
with `curl`, and **always include a `Title` header**:

```sh
curl -s -H "Title: Short subject" -d "plain words

Type a reply: https://ntfy.sh/<topic>" ntfy.sh/<topic>
```

The title is not decoration. `ntfy-listen` treats any untitled message as a human
answer, so a titleless reply from you comes straight back at you as a fake
`ANSWER:` event. Add the URL footer by hand here — only `ntfy-ask` appends it
automatically.

## Reading the answer

The listener prints raw text. Match it case-insensitively against your option
keys. On iOS that is all you will ever get, because a button is the only way to
answer. On Android, or from a browser, the reply may be free text — `bro` means
re-ask in plainer words, anything else read as English.

Tell the user which option you read and what you are doing about it. They tapped
a button on a phone; nothing on their screen tells them what happened next.
