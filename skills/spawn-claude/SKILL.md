---
name: spawn-claude
description: Start a new, named Claude Code session in a new Zellij tab without moving the user's focus, with a starting prompt and optional model. Use when the user asks to spawn, launch, or start another Claude Code session, worker, or instance in a new tab, hand a task to a fresh session, or invokes /spawn-claude.
---

# Spawn Claude

Open a new Zellij tab in the background, start Claude Code in it with a display
name and a first prompt, and leave the user looking at whatever they were looking at.

The new session shows up in `ListAgents` under its display name, so this session
can message it later with `SendMessage`.

## Quick start

```bash
~/.claude/skills/spawn-claude/scripts/spawn.sh \
  --name a4-fix \
  --model claude-opus-5 \
  --cwd /Users/bshaver/ClearFracture/Workspace \
  -- "Do task A4 from WORKSPACE.md and open a PR against release/v0.4.0"
```

Everything after `--` is the prompt. The script joins it into one argument and
hands it to `claude` unchanged. The shell still parses the command line first, so
an apostrophe or `$` in a bare prompt breaks it. Wrap the prompt in double quotes
and avoid `"` and `$` inside it, or use single quotes if the prompt has none.

The script runs, in effect:

```bash
zellij action new-tab --close-on-exit --no-focus --name "$name" --cwd "$cwd" \
  -- claude --name "$name" --model "$model" "$prompt"
```

## Arguments

| Flag        | Required | Default          | Meaning                                              |
| ----------- | -------- | ---------------- | ---------------------------------------------------- |
| `--name`    | yes      |                  | Tab name and Claude session display name             |
| `--model`   | no       | Claude's default | Passed to `claude --model`                           |
| `--cwd`     | no       | current dir      | Working directory for the tab and the session        |
| `--add-dir` | no       |                  | Extra directory to allow; repeatable                 |
| `-- <text>` | yes      |                  | The first prompt                                     |

## Workflow

1. **Parse the user's request** into a name, an optional model, an optional
   directory, and the prompt. If the user gave no name, derive a short kebab-case
   one from the task (`a4-event-loop`, `pi-strip`). Never ask for a name when a
   sensible one is obvious. Pass `--model` only when the user names a model;
   otherwise the session uses Claude's default.
2. **Pick the working directory** the task lives in. A task about one repo gets
   that repo's directory, so the session loads that repo's `CLAUDE.md`. A task
   spanning repos gets the Workspace root.
3. **Run the script.** Quote each flag value once, and wrap the prompt after `--` in
   double quotes. Reword the prompt rather than escaping apostrophes or `$`.
4. **Confirm to the user** with the tab name and directory, and say their focus
   did not move. They will not see anything change on screen.

## Things to know

- `--no-focus` is the point of this skill. Do not swap it for a focused tab, and
  never follow up with `go-to-tab`; both act on the user's view.
- `--close-on-exit` closes the tab when the session ends. If the user wants the
  tab to survive so they can read the final screen, drop that flag by running
  the `zellij action new-tab` command by hand instead of the script.
- The prompt is the session's first turn. Standing instructions for the whole
  session belong in `--append-system-prompt`, which the script does not expose;
  add it to the hand-run command if needed.
- `SPAWN_DRY_RUN=1 spawn.sh ...` prints the exact `claude` argv and exits without
  opening a tab. Use it when a prompt has unusual characters.
- The script refuses to run outside Zellij (`$ZELLIJ` unset) or with a `--cwd`
  that is not a directory, and exits non-zero with a one-line reason.
- Cross-session messages to the new session are read at its next tool round. A
  session busy on its first prompt will pick them up; one sitting idle at an
  empty prompt may not until someone types. Put the task in the prompt.

## For humans: `spawn-claude` on a hotkey

`scripts/spawn-claude` is the interactive counterpart to `spawn.sh`. It uses
[`gum`](https://github.com/charmbracelet/gum) to ask for the tab name, a model
alias (fuzzy-filtered over `default`, `fable`, `opus`, `sonnet`, `haiku`), and the
first prompt, then opens the tab with `--no-focus` exactly as `spawn.sh` does. The
one name you type becomes both the Zellij tab name and the Claude session name.
Escape at any prompt cancels.

Copy it onto your `PATH` (for example `~/.local/bin/spawn-claude`) and bind it to
a key in `~/.config/zellij/config.kdl` under `keybinds { normal { ... } }`:

```kdl
bind "Ctrl a" {
    Run "zsh" "-ic" "spawn-claude" {
        close_on_exit true
        floating true
        x "20%"
        y "20%"
        width "60%"
        height "60%"
    }
}
```

The floating pane inherits the cwd of the pane that had focus, so the new session
starts in the repo you were looking at. The pane closes when the script exits.
Binding `Ctrl a` in normal mode means the shell no longer receives it, so
`beginning-of-line` in the line editor stops working inside Zellij; pick another
key if you rely on it. Requires `brew install gum`.
