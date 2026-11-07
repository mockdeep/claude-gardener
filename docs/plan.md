# Plan: Local `garden` CLI

## Goal

Replace the GitHub Actions workflow with a local command-line tool. `garden`
scans registered projects, fixes issues on local branches, and offers a review
step where lessons from each review are saved as guidance for later runs.

The first focus is **security issues**.

## Commands

### `garden setup`

Links the `garden-review` skill from this repo (`skills/garden-review/`) into
`~/.claude/skills/garden-review/`, so `/garden-review` works from any project.
It's a link, not a copy, so edits to the skill in this repo take effect right
away.

### `garden add [path]`

Registers a project (defaults to the current directory). Projects are saved to
`~/.config/garden/projects.yml`, which can also be edited by hand:

```yaml
defaults:            # optional, applies to every project
  model: opus
projects:
  - name: my-app
    path: /home/me/code/my-app
    fix_limit: 3                 # optional, default 2
    model: sonnet                # optional, default is Claude's own default
    audit_commands: [composer audit]   # optional, added to the built-in list
    test_commands: [bundle exec rspec] # optional, guessed if not set
    worktree_files: [.env]             # optional, linked into fix worktrees
    setup_commands: [npm ci]           # optional, run in fix worktrees
    fix_timeout: 1800                  # optional, seconds per Claude run
```

### `garden scan [project] [--force]`

Runs only the scan part of `garden` (below) for one project, or all of them,
and prints each finding's severity, title and files. `--force` rescans even if
the saved findings are less than a week old.

### `garden`

For each registered project, one at a time:

1. **Tidy up state.** Remove approved findings whose PR is merged or closed
   (checked with `gh`), and rejections older than a week.
2. **Scan if needed.** If the saved findings are more than a week old (or
   there are none):
   - `git fetch`, then reset a scan worktree
     (`~/.local/share/garden/worktrees/<project>/scan`) to the latest default
     branch (from `origin/HEAD`, falling back to `main`/`master`)
   - run `claude -p` there with structured output (`--json-schema`), read-only
     file tools, and a short allowed list of audit commands (`bundle audit`,
     `npm audit`, `yarn audit`, `pnpm audit`, `pip-audit`, `cargo audit`,
     plus any extras set in `projects.yml`)
   - the prompt is the security scan prompt, plus every `.md` file in
     `~/.config/garden/guidance/`, plus in-progress and recently rejected
     findings (with reasons) so Claude doesn't report them again
   - each finding has a title, details, files, and a severity (`high`,
     `medium`, `low`); at most 10 per scan
   - if the scan fails, keep the old findings, show the error, and move on
3. **Fix.** First fetch (even if no scan ran), and mark any finding left in
   `fixing` by a crashed run as `failed`. Then fix up to `fix_limit` open
   findings, highest severity first. For each one:
   - mark it `fixing` and create branch `garden/security/<id>-<short-title>`
     from the latest default branch, in a worktree at
     `~/.local/share/garden/worktrees/<project>/garden-security-<id>/`
     (outside Dropbox and out of the project folders)
   - link `worktree_files` from the main checkout and run `setup_commands`
     (garden runs these itself, so Claude doesn't need permission for them)
   - run `claude -p` in `acceptEdits` mode, so it can edit files and use basic
     file commands in the worktree, plus the `test_commands` and read-only git
     commands. Nothing else is allowed. The prompt has the finding, the
     guidance, and the git commit template if one is set. Time limit:
     `fix_timeout` (default 30 minutes)
   - Claude returns `fixed`, `not_an_issue` or `failed`, plus a summary and a
     commit message
   - garden runs the `test_commands` itself. If they fail, it resumes Claude's
     session once with the output; if they still fail, the finding is marked
     `failed` and the log is saved to `~/.local/state/garden/logs/<id>.log`
   - garden (not Claude) commits and marks it `pending_review`. If Claude says
     `not_an_issue` or `failed`, or there are no changes, it's marked `failed`
     with a note, so it lands in the review queue

`test_commands` is guessed when it isn't set: `Gemfile` means
`bundle exec rspec` (or `bundle exec rake test` without a `spec/` folder);
`package.json` means `npm test`; `pyproject.toml` means `pytest`;
`Cargo.toml` means `cargo test`; `go.mod` means `go test ./...`.

Tests run against your real local setup (database and other services). The
worktree shares the main checkout's test database, which is fine as long as
you aren't running tests yourself while garden runs.

### `garden fix [project]`

Runs only the fix part, without scanning.

### `garden review`

Goes through pending branches across all projects as a queue:

1. Writes a context file for the finding to
   `~/.local/state/garden/reviews/<id>/context.md` (the finding, Claude's
   note, the end of any test log, the branch, the default branch, and where
   guidance goes).
2. Makes sure the project's guidance worktree exists (see below).
3. Starts `claude "/garden-review <context-file>"` in the fix worktree, with
   `--add-dir` for `~/.config/garden`, the guidance worktree, and the review
   folder.
4. You and Claude review the fix (see the skill below). At the end, the skill
   writes `summary.md` next to the context file.
5. After Claude exits, `garden` asks for a decision:
   - **Approve**: open your editor on the commit message
     (`git commit --amend`), then push and run `gh pr create`, using the
     summary in the PR description
   - **Reject**: save the summary as the reason, then delete the branch and
     worktree
   - **Skip**: leave it in the queue
6. Asks "Next? (y/n)" before moving on.
7. When the session ends, for each project whose guidance worktree has
   changes: commit them (opening your editor for the message), push, and
   open a PR, or add to the one already open.

Failed findings are reviewed the same way, using whatever partial changes are
in the worktree. Their choices are **approve** (only if there's now a commit),
**retry** (delete the branch and worktree and set back to `open`), **reject**,
or **skip**.

### The `garden-review` skill

1. **Overview.** Reads the context file and the diff
   (`git diff <default>...HEAD`), then gives a short rundown: the issue, what
   changed, whether the tests passed, and anything that looks off. For a
   failed finding, it explains what went wrong instead.
2. **Discussion.** You talk it through. If you want the fix changed, Claude
   edits the code, runs the tests, and folds the changes into the fix commit
   (`git commit --amend --no-edit`). A failed finding with no commit yet gets
   a new commit.
3. **Lessons.** Only when you clearly push back on the approach, the skill
   suggests a lesson, says whether it's general or repo-specific, shows the
   exact edit, and waits for your OK. You can redirect it.
4. **Wrap-up.** Writes `summary.md`: what was discussed, lessons saved, and a
   suggested decision (approve, reject, retry or skip) with the reason.

## Guidance (learned from reviews)

- **General**: `~/.config/garden/guidance/<topic>.md`, for broad philosophy
  that applies to every project.
- **Repo-specific**: the repo's `AGENTS.md` if it has one, otherwise
  `CLAUDE.md`; a skill in `.claude/skills/` only for a narrow, step-by-step
  procedure. These edits are made on a separate `garden/guidance` branch, in
  its own worktree at `~/.local/share/garden/worktrees/<project>/guidance`,
  so they don't get mixed into fix PRs and aren't lost when a fix is
  rejected. The skill only edits; garden commits and opens the PR at the end
  of a review session.

Both levels are loaded into the prompt when `garden` works on a project.

## State

Kept in one YAML file per project at `~/.local/state/garden/<project>.yml`,
which can be read and edited by hand:

```yaml
scanned_at: "2026-11-06T20:00:00Z"
findings:
  - id: a1b2c3                # short random id
    title: SQL injection in user search
    details: Search param is put straight into the query...
    files: [app/models/user.rb]
    severity: high
    status: pending_review
    branch: garden/security/a1b2c3-sql-injection
    worktree: /home/me/.local/share/garden/worktrees/my-app/garden-security-a1b2c3
    pr_url: null
    note: null                # from the fix, e.g. "Claude thinks it's not an issue"
    log: null                 # path to a saved test log, when tests failed
    reason: null              # set on reject, from the review summary
    rejected_at: null
```

**Statuses**

- `open`: found, not fixed yet
- `fixing`: a fix is running
- `pending_review`: fixed, waiting in the review queue
- `failed`: Claude couldn't fix it; also goes in the review queue
- `approved`: PR opened
- `rejected`: turned down in review

**Rules**

- On rescan, `open` findings are replaced by the new results. Anything with a
  branch or PR is kept.
- Rejected findings are removed 7 days after `rejected_at`.
- Approved findings are removed once their PR is merged or closed (checked
  with `gh` at the start of each run).
- Scan prompts include recent rejections (with reasons) and in-progress
  findings, and Claude judges whether a new finding is the same issue.
- Writes go to a temp file that's then renamed into place, and a lock file
  stops two `garden` runs editing the same project's state at once.

## Technical choices

- Ruby gem with a `garden` executable.
- Reuse config parsing, prompts (`lib/prompts/`), and checklist parsing where
  they fit.
- Uses the local Claude Code login, so no API key or OAuth token setup.
- Run by hand for now. Scheduling (cron/systemd timer) comes later.
- Projects run one at a time. Parallel runs can come later, since each project
  already has its own state file.

## Removed

All GitHub Actions code: `action.yml`, `actions/`, `templates/workflows/`, and
the GitHub-specific Ruby (issue manager, PR manager, review/build/merge
handlers, task claimer, legacy task selection). `AGENTS.md` and the README will
be rewritten to match.

## Build order

1. Gem skeleton with the `garden` executable, `garden setup`, and `garden add`.
2. State storage.
3. Security scan: run Claude, parse findings, save them, rescan after a week.
4. Fix step: worktree, branch, headless Claude run, commit, limit per run.
5. `garden-review` skill, including the propose-then-write guidance edits.
6. `garden review` queue with approve/reject/skip.
7. Remove the GitHub Actions code and update the docs.
