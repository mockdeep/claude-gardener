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
`~/.config/garden/projects.yml`, which can also be edited by hand.

### `garden`

For each registered project:

1. Load saved security findings. If there are none, or they are older than a
   week, run a fresh scan.
2. Skip findings that already have a pending branch or open PR.
3. Fix up to 2 findings (default; can be changed per project in
   `projects.yml`). Each fix:
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

1. Starts `claude "/garden-review"` in the branch's worktree, with
   `--add-dir ~/.config/garden` so the central guidance can be edited.
2. You talk through the approach with Claude.
3. The skill proposes guidance edits and waits for your OK before writing them.
4. After Claude exits, `garden` asks for a decision:
   - **Approve**: open your editor on the commit message
     (`git commit --amend`), then push and run `gh pr create`
   - **Reject**: delete the branch and worktree
   - **Skip**: leave it in the queue
5. Asks "Next? (y/n)" before moving on.

## Guidance (learned from reviews)

- **General**: `~/.config/garden/guidance/`, for broad philosophy that applies
  to every project.
- **Repo-specific**: the repo's own `AGENTS.md`/`CLAUDE.md` or
  `.claude/skills/`, for patterns specific to that codebase.

Both levels are loaded into the prompt when `garden` works on a project.

## State

Kept in one YAML file per project at `~/.local/state/garden/<project>.yml`,
which can be read and edited by hand:

- saved findings and when they were scanned
- pending branches and their worktree paths
- review status (pending, approved, rejected)

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
