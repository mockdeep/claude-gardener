# Claude Gardener - Development Guide

## Overview

Claude Gardener is a GitHub Action that enables Claude to continuously make small improvements to codebases. It's a set of composite actions built with Ruby that orchestrate scanning for improvements, creating work items, delegating to the official `anthropics/claude-code-action` for AI execution, and handling PR lifecycle events.

## Architecture

```
claude-gardener/
├── action.yml                     # Legacy single-action entry point
├── actions/
│   ├── plan-scan/action.yml       # Phase 1: Create scan plan issue
│   ├── run-scan/action.yml        # Phase 2: Scan a category for work items
│   ├── setup-work/action.yml      # Phase 3a: Compute worker matrix
│   ├── work/action.yml            # Phase 3b: Execute a single work item
│   ├── review-handler/action.yml  # Respond to PR review comments
│   ├── build-handler/action.yml   # Fix build failures
│   └── merge-handler/action.yml   # Post-merge cleanup
├── lib/
│   ├── scan_planner.rb            # Creates scan plan issue with category checklist
│   ├── scanner.rb                 # Runs scan, processes results into aggregate issues
│   ├── work_selector.rb           # Selects work items from aggregate issues
│   ├── worker.rb                  # Prepares prompts for individual work items
│   ├── task_claimer.rb            # Claims/completes items in aggregate issues
│   ├── create_pr.rb               # Creates branch and PR after Claude makes changes
│   ├── config.rb                  # Parses claude-gardener.yml (v1 and v2)
│   ├── issue_manager.rb           # Manages plan and aggregate GitHub issues
│   ├── checklist_parser.rb        # Parses markdown checklists from issues
│   ├── github_client.rb           # Octokit wrapper for GitHub API
│   ├── pr_manager.rb              # PR queries (open PRs, labels, capacity)
│   ├── output_writer.rb           # Writes to $GITHUB_OUTPUT
│   ├── review_handler.rb          # Prepares prompts for review responses
│   ├── build_handler.rb           # Prepares prompts for build fixes
│   ├── merge_handler.rb           # Post-merge item check-off and conflict detection
│   ├── select_task.rb             # Legacy single-task selection
│   ├── task_selector.rb           # Legacy priority-based task selection
│   └── prompts/
│       ├── scan/                  # Scan prompts (identify work items)
│       │   ├── test_coverage.md
│       │   ├── security_fixes.md
│       │   ├── linter_fixes.md
│       │   ├── code_improvements.md
│       │   └── add_tooling.md
│       ├── test_coverage.md       # Work prompts (execute improvements)
│       ├── security_fixes.md
│       ├── linter_fixes.md
│       ├── code_improvements.md
│       └── add_tooling.md
├── spec/                          # RSpec tests
└── templates/
    ├── claude-gardener.yml        # Example config for users
    └── workflows/                 # Example workflow files
        ├── gardener-scan.yml
        ├── gardener-work.yml
        └── gardener-handlers.yml
```

## How It Works

### Pipeline Overview

The gardener operates in phases across three workflows:

**Gardener Scan** (workflow_dispatch):
1. **Plan** (`scan_planner.rb`): Creates a GitHub issue with a checklist of categories to scan. Closes any existing plan issue first.
2. **Scan** (matrix job per category): Claude analyzes the codebase and outputs a markdown checklist of improvements. Results are parsed and stored as aggregate issues (one per category). Old aggregate issues for the same category are closed.

**Gardener Work** (workflow_dispatch):
3. **Setup** (`work_selector.rb`): Reads open aggregate issues, selects unclaimed items, outputs a matrix of work items.
4. **Work** (matrix job per item): Claude executes the improvement. A PR is created with the changes, linked back to the aggregate issue.

**Gardener Handlers** (event-driven):
5. **Review handler**: When a PR review is submitted, Claude responds to comments.
6. **Build handler**: When a check fails, Claude attempts to fix the build.
7. **Merge handler**: When a PR merges, checks off the item in the aggregate issue. Closes the aggregate issue if all items are complete.

### Issue Lifecycle

- **Plan issue** (`claude-gardener:plan` label): Checklist of categories. Each scan job checks off its category. Closed when all categories are scanned, or replaced on next scan run.
- **Aggregate issue** (`claude-gardener:scan:<category>` label): Checklist of work items for a category. Items are claimed by PRs, checked off on merge. Closed when all items are complete or replaced by a new scan.

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Action type | Composite | Avoids Docker permission issues |
| Claude execution | Official action | Handles auth, permissions, output |
| Task selection | Ruby | Reuses existing codebase logic |
| PR identification | Labels | Easy to query and filter |
| File locking | PR-based | No external state needed |
| Work tracking | GitHub issues | No external state, visible to users |

### claude-code-action Integration

The `anthropics/claude-code-action@beta` outputs a single value:
- `execution_file`: Path to a JSON file containing an **array** of conversation entries

To extract Claude's response, find the entry with `"type": "result"` and read its `"result"` field:
```ruby
entries = JSON.parse(File.read(execution_file))
entries.find { |e| e['type'] == 'result' }.fetch('result')
```

## Development

### Running Tests

```bash
bundle install
bundle exec rspec
```

### Key Files

**lib/scan_planner.rb**
- Creates plan issue with category checklist
- Closes existing plan issue if one exists (fresh start)

**lib/scanner.rb**
- Loads category-specific scan prompt from `prompts/scan/`
- Appends excluded paths and output format instructions
- `post_scan`: Parses Claude's checklist output, creates aggregate issue, closes old ones
- Checks off plan issue item with retry logic (handles race conditions from parallel matrix jobs)

**lib/issue_manager.rb**
- Creates/finds/closes plan and aggregate issues
- Manages labels (`claude-gardener:plan`, `claude-gardener:scan:<category>`)

**lib/checklist_parser.rb**
- Parses `- [ ] item` / `- [x] item` from issue bodies
- Supports claiming (`claimed by PR #N`) and checking off items

**lib/merge_handler.rb**
- Finds the aggregate issue linked from PR metadata
- Checks off the completed item
- Closes the aggregate issue if all items are complete

**lib/config.rb**
- Parses `claude-gardener.yml` from user's repo
- Supports v1 (priorities-based) and v2 (simplified categories) schemas

## Configuration Schema

### V2 (recommended)

```yaml
version: 2

max_concurrent: 3

categories:
  - test_coverage
  - code_improvements

excluded_paths:
  - "vendor/**"
  - "node_modules/**"

pr_assignees:
  - your-github-username

pr_reviewers:
  - your-github-username
```

### V1 (legacy)

```yaml
version: 1

workers:
  max_concurrent: 3

priorities:
  - category: test_coverage
    max_prs: 3
    enabled: true
    tasks: []

guardrails:
  max_iterations_per_pr: 5
  max_files_per_pr: 10
  require_tests: true

labels:
  base: "claude-gardener"
  categories: true

excluded_paths:
  - "vendor/**"
  - "node_modules/**"
```

## Workflow Permissions

### Scan workflow
```yaml
permissions:
  contents: read
  issues: write
  id-token: write
```

### Work workflow
```yaml
permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write
```

And enable in repo settings:
- Settings -> Actions -> General -> "Allow GitHub Actions to create and approve pull requests"

## Authentication Options

1. **OAuth Token** (`claude_oauth_token`) - For Max/Pro subscribers
2. **API Key** (`anthropic_api_key`) - Pay-per-use API credits

Get OAuth token: `claude auth token`

## Future Improvements

- [ ] PR review feedback handling (respond to comments)
- [ ] Iteration tracking and escalation
- [ ] Learning: update CLAUDE.md with discovered patterns
- [ ] Scheduled runs (cron trigger)
- [ ] Tooling detection (add linters/test frameworks)

## Troubleshooting

| Error | Solution |
|-------|----------|
| "Credit balance too low" | Add API credits or use OAuth token |
| "Resource not accessible" | Add required permissions to workflow |
| "id-token: write" needed | Add `id-token: write` to permissions |
| "Not permitted to create PRs" | Enable in repo Settings -> Actions |
| "Author identity unknown" | Fixed in create_pr.rb (sets git config) |
| Empty Claude output | Check `execution_file` parsing — it's an array, not an object |
