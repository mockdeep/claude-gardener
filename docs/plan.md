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
3. Fix up to 2 open findings, highest severity first (the limit can be changed
   per project in `projects.yml`). Each fix:
   - gets its own branch and git worktree, so your main checkout is never
     touched. Worktrees live at
     `~/.local/share/garden/worktrees/<project>/<branch>/`, outside Dropbox
     and out of the project folders
   - runs Claude headless (`claude -p`) with the work prompt plus the general
     and repo-specific guidance
   - ends with a commit on that branch
4. Record each new branch as pending review.

### `garden review`

Goes through pending branches across all projects as a queue:

1. Starts `claude "/garden-review <summary-file>"` in the branch's worktree,
   with `--add-dir ~/.config/garden` so the central guidance can be edited.
   The summary file is `~/.local/state/garden/reviews/<id>.md`.
2. You talk through the approach with Claude.
3. The skill proposes guidance edits and waits for your OK before writing them.
4. At the end, the skill writes a short summary of the discussion to the
   summary file, including why you'd reject it, if you lean that way.
5. After Claude exits, `garden` asks for a decision:
   - **Approve**: open your editor on the commit message
     (`git commit --amend`), then push and run `gh pr create`, using the
     summary in the PR description
   - **Reject**: save the summary as the reason, then delete the branch and
     worktree
   - **Skip**: leave it in the queue

Failed findings are reviewed the same way, using whatever partial changes are
in the worktree. Their choices are **approve** (only if there's now a commit),
**retry** (set back to `open`), **reject**, or **skip**.
6. Asks "Next? (y/n)" before moving on.

## Guidance (learned from reviews)

- **General**: `~/.config/garden/guidance/`, for broad philosophy that applies
  to every project.
- **Repo-specific**: the repo's own `AGENTS.md`/`CLAUDE.md` or
  `.claude/skills/`, for patterns specific to that codebase.

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
    status: pending_review
    branch: garden/security/a1b2c3-sql-injection
    worktree: /home/me/.local/share/garden/worktrees/my-app/garden-security-a1b2c3
    pr_url: null
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
