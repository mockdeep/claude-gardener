# Claude Gardener

A command-line tool that runs Claude Code over your local projects to find
and fix small problems, one reviewable branch at a time. You review each fix
with Claude, and lessons from those reviews are saved as guidance, so later
fixes get better.

It currently looks for **security issues**.

## How it works

1. **`garden`** goes through each registered project. It scans for security
   issues (at most once a week), then fixes the most severe ones, each on its
   own branch in its own git worktree. Your normal checkout is never touched.
2. **`garden review`** goes through the fixes one by one. For each, it opens
   an interactive Claude session to talk the fix through. Then you approve it
   (garden opens a PR), reject it, retry it, or skip it.
3. When you push back on a fix during review, Claude suggests a lesson and
   saves it once you agree. General lessons go in `~/.config/garden/guidance/`;
   repo-specific ones go on a `garden/guidance` branch with its own PR.

## Requirements

- Ruby 3.4 or newer
- git
- [Claude Code](https://code.claude.com), logged in (`claude` on your PATH)
- [GitHub CLI](https://cli.github.com) (`gh`), logged in, for opening PRs

## Setup

```bash
git clone https://github.com/mockdeep/claude-gardener.git
cd claude-gardener
bundle install
ln -s "$PWD/exe/garden" ~/.local/bin/garden   # or anywhere on your PATH

garden setup        # links the garden-review skill into ~/.claude/skills
```

Then register each project you want garden to work on:

```bash
cd ~/code/my-app
garden add
```

## Commands

| Command | What it does |
|---------|--------------|
| `garden` | Scan every project (if due), then fix open findings |
| `garden scan [project] [--force]` | Only scan; `--force` rescans even if the last scan is recent |
| `garden fix [project]` | Only fix, without scanning |
| `garden review` | Review fixes with Claude, then approve, reject, retry or skip each |
| `garden add [path] [--name NAME]` | Register a project |
| `garden setup` | Link the review skill into Claude Code |

## Configuration

Projects live in `~/.config/garden/projects.yml`, which you can edit by hand:

```yaml
defaults:                           # optional, applies to every project
  model: opus
projects:
  - name: my-app
    path: /home/me/code/my-app
    fix_limit: 2                    # fixes per run, most severe first
    model: sonnet                   # Claude model; default is Claude's own
    test_commands: [bundle exec rspec]   # guessed from the project if unset
    setup_commands: [npm ci]        # run in each fix worktree before Claude
    worktree_files: [.env]          # ignored files linked into fix worktrees
    audit_commands: [composer audit]     # extra audit tools the scan may run
    fix_timeout: 1800               # seconds per Claude run
```

### What Claude may run

- **Scanning:** read-only file tools, plus audit commands (`bundle audit`,
  `npm audit`, `yarn audit`, `pnpm audit`, `pip-audit`, `cargo audit`, and
  any `audit_commands`).
- **Fixing:** edits and basic file commands in the fix worktree, the
  `test_commands`, and read-only git commands. Nothing else. Garden runs
  `setup_commands` itself, and garden (not Claude) makes the commit.

Tests run against your real local setup, so a database or other services
need to be running. Fix worktrees share your main checkout's test database.

## Where garden keeps things

| Path | Contents |
|------|----------|
| `~/.config/garden/projects.yml` | Registered projects and settings |
| `~/.config/garden/guidance/` | General lessons from reviews |
| `~/.local/state/garden/<project>.yml` | Findings and their status |
| `~/.local/state/garden/reviews/`, `logs/` | Review context and summaries, failed test logs |
| `~/.local/share/garden/worktrees/` | Scan, fix and guidance worktrees |

These follow `XDG_CONFIG_HOME`, `XDG_STATE_HOME` and `XDG_DATA_HOME` when set.

## Development

```bash
bundle install
bundle exec rspec
```

GitHub Actions runs the tests on Ruby 3.4 and 4.0 for every pull
request and push to `main`.

See [AGENTS.md](AGENTS.md) for how the code fits together, and
[docs/plan.md](docs/plan.md) for the design.

## License

MIT
