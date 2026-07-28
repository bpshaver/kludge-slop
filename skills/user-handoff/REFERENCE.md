# Detecting lint/test configuration

Do this detection yourself (Read/Glob/Bash) before building `LINT_CMD` / `TEST_CMD` for `scripts/watch.sh`. The script itself is dumb — it only runs whatever command template it's given against changed files.

## Python

Check, in order, for an existing config:

- `ruff.toml`, `.ruff.toml`, or a `[tool.ruff]` table in `pyproject.toml` → lint with `ruff check {}`
- `mypy.ini`, a `[mypy]` section in `setup.cfg`, or a `[tool.mypy]` table in `pyproject.toml` → type-check with `mypy {}` (use whatever strictness the config already sets — don't force `--strict` if the project has deliberately configured otherwise)
- `.flake8` or a `[flake8]` section in `setup.cfg`/`tox.ini` → `flake8 {}`
- A `lint` entry under `[tool.poe.tasks]`, a `Makefile` target named `lint`, or a `scripts.lint` in a project's task runner → prefer the project's own command if it cleanly accepts a file list; otherwise fall back to running it unscoped and mention that to the user (slower, but honors project config)

If **none** of the above exist, default to:

```
LINT_CMD='ruff check {} && mypy --strict {}'
```

and confirm this default with the user before starting the watcher — they may not have `ruff`/`mypy` installed, or may prefer something else.

Test runner: if `pytest` is importable (`python -m pytest --version` succeeds) or the repo has a `pytest.ini` / `[tool.pytest.ini_options]` / `tests/` dir, set:

```
TEST_CMD='python -m pytest {}'
```

### Test naming convention

Sample the existing tests before assuming a convention:

```bash
find . -name 'test_*.py' | wc -l
find . -name '*_test.py' | wc -l
```

Whichever pattern dominates is the project's convention — set `TEST_NAME_TEMPLATE` to match (`test_{}.py` or `{}_test.py`) and set `TEST_PATTERN` to recognize both when scanning edits, e.g.:

```
TEST_PATTERN='(^|/)(test_[^/]+\.py|[^/]+_test\.py)$'
```

If there are no existing tests at all, default to `test_{}.py` (the more common convention) and say so.

## JavaScript / TypeScript

- A `scripts.lint` entry in `package.json` → prefer running that; check whether it accepts a file list (many `eslint`-backed scripts do — try `npm run lint -- <file>` syntax) before falling back to running it unscoped
- `.eslintrc*` or an `eslint.config.*` with no `lint` script → `npx eslint {}`
- No config found → ask the user what they'd like rather than guessing a default (there's no JS equivalent to the ruff/mypy fallback requested for Python)

Test runner: a `scripts.test` entry in `package.json` (jest/vitest can usually take a file path directly), e.g. `TEST_CMD='npx vitest run {}'`.

## Other languages

If the edited files aren't Python or JS/TS and no obvious lint config is found (`.golangci.yml`, `rubocop.yml`, `.rspec`, etc.), ask the user what they'd like linted with rather than silently skipping — but don't block starting the watcher on an answer; you can start with `LINT_CMD` unset (the script just skips lint checks and still reports diffs) and update it later if they'll only tell you once they've started.

## Multiple languages in one repo

Run detection independently per language and combine both into one `LINT_CMD`, e.g.:

```
LINT_CMD='{ echo "$f" | grep -q "\.py$" && ruff check {} && mypy {}; } || { echo "$f" | grep -q "\.tsx\?$" && npx eslint {}; }'
```

In practice it's simpler to just extend `scripts/watch.sh`'s lint block with a second `LINT_EXTS`/`LINT_CMD` pair if a task spans both — the script is short and meant to be adapted per run rather than treated as a rigid black box.
