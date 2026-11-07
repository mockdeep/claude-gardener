# Claude Gardener: development guide

`garden` is a Ruby command-line tool. It runs Claude Code headless over
registered local projects to find and fix security issues, one branch and
worktree per fix. Then `garden review` walks the user through each fix in an
interactive Claude session. The full design is in `docs/plan.md`.

## Layout

```
exe/garden                    # entry point (works when symlinked onto PATH)
lib/garden.rb                 # requires everything
lib/garden/
  cli.rb                      # commands: (none), scan, fix, review, add, setup, help
  paths.rb                    # where files live (XDG dirs, CLAUDE_CONFIG_DIR)
  registry.rb                 # projects.yml and per-project settings
  finding.rb                  # one finding: severity, status, branch, notes
  state.rb                    # State (rules) and StateStore (locked YAML file)
  scan_step.rb                # tidy state, then scan if due
  scanner.rb                  # scan prompt + structured output -> findings
  fix_step.rb                 # pick findings, mark fixing, record outcomes
  fixer.rb                    # fix one finding: worktree, Claude, tests, commit
  test_commands.rb            # guess test commands from project files
  review_queue.rb             # `garden review`: sessions, decisions, guidance PR
  review_context.rb           # context.md handed to the review skill
  review_summary.rb           # reads the skill's summary.md
  repo.rb                     # git operations
  claude.rb                   # `claude -p` with JSON schema output
  github.rb                   # `gh` lookups and PR creation
  shell.rb                    # running commands (timeouts, process groups)
  terminal.rb                 # interactive programs and questions
  guidance.rb                 # general guidance files -> prompt section
  setup.rb                    # links skills into ~/.claude/skills
  prompts/                    # scan_security.md, fix_security.md
skills/garden-review/SKILL.md # the interactive review skill
spec/garden/                  # RSpec specs, named after the files they test
```

## How a run flows

1. `ScanStep`: remove approved findings whose PR closed and week-old
   rejections, then (if the last scan is over a week old) fetch, reset the
   scan worktree, and run `Scanner`.
2. `FixStep`: mark stuck `fixing` findings as `failed`, then for each of the
   top `fix_limit` open findings, set a branch and worktree, run `Fixer`, and
   save the outcome (`pending_review` or `failed`).
3. `ReviewQueue`: for each `pending_review`/`failed` finding, write the
   context, start `claude "/garden-review <context>"`, read the summary, and
   carry out approve / reject / retry / skip. At the end, commit and open a PR
   for guidance changes.

Finding statuses: `open` → `fixing` → `pending_review` or `failed` →
`approved` (PR open) or `rejected`. Retry sets a finding back to `open`.

## Conventions

- **Outside commands go through `Shell`** (or `Terminal` for interactive
  ones), and classes take them as constructor arguments so specs can swap
  them out.
- **Errors meant for the user are `Garden::Error`.** The CLI prints them
  without a stack trace. A failure in one project or finding shouldn't stop
  the others.
- **State changes go through `StateStore#update`**, which locks the file.
  Keep long work (Claude runs) outside the block, and don't nest calls for
  the same project.
- **Garden commits, not Claude**, during fixes. Claude's permissions are
  limited by `--tools`, `--allowed-tools` and the permission mode; see
  `Scanner` and `Fixer`.
- **`claude` flag order:** `--add-dir` and `--allowed-tools` take lists, so
  put the prompt before them.
- Prompts and user-facing text use plain language.

## Testing

```bash
bundle exec rspec
```

- `spec/garden/support.rb` has the `"garden sandbox"` shared context. It
  points every garden folder, Claude's config folder and git's global config
  at a temp folder. Use it in any spec that touches files or git.
- Git-related specs use real repos (and a local bare repo as `origin` where
  pushing matters). Claude, `gh` and the editor are faked.
- To try a real run without touching your own setup, set `XDG_CONFIG_HOME`,
  `XDG_STATE_HOME` and `XDG_DATA_HOME` to a scratch folder first.
