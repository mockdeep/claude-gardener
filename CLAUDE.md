# Claude Gardener - Development Guide

## Overview

Claude Gardener is a GitHub Action that enables Claude to continuously make small improvements to codebases. It's a composite action built with Ruby that orchestrates task selection, delegates to the official `anthropics/claude-code-action` for AI execution, and handles PR creation.

## Architecture

```
claude-gardener/
├── action.yml              # Composite GitHub Action definition
├── lib/
│   ├── select_task.rb      # Entry point: selects task based on config/capacity
│   ├── create_pr.rb        # Creates branch and PR after Claude makes changes
│   ├── config.rb           # Parses claude-gardener.yml configuration
│   ├── task_selector.rb    # Priority-based task selection logic
│   ├── pr_manager.rb       # PR queries (open PRs, labels)
│   ├── lock_checker.rb     # File locking via open PR detection
│   ├── github_client.rb    # Octokit wrapper for GitHub API
│   └── prompts/            # Category-specific prompts for Claude
│       ├── test_coverage.md
│       ├── security_fixes.md
│       ├── linter_fixes.md
│       ├── code_improvements.md
│       └── add_tooling.md
├── spec/                   # RSpec tests
└── templates/
    └── claude-gardener.yml # Example config for users
```

## How It Works

### Composite Action Flow

1. **Setup Ruby** - Uses `ruby/setup-ruby@v1`
2. **Install dependencies** - Bundles gems from action directory
3. **Select task** (`lib/select_task.rb`):
   - Loads user's `claude-gardener.yml` config
   - Checks worker capacity (max concurrent PRs)
   - Selects highest priority category with available slots
   - Outputs prompt and metadata to `$GITHUB_OUTPUT`
4. **Run Claude** - Delegates to `anthropics/claude-code-action@beta`
5. **Create PR** (`lib/create_pr.rb`):
   - Creates branch with timestamp
   - Commits Claude's changes
   - Pushes and creates PR with labels

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Action type | Composite | Avoids Docker permission issues |
| Claude execution | Official action | Handles auth, permissions, output |
| Task selection | Ruby | Reuses existing codebase logic |
| PR identification | Labels | Easy to query and filter |
| File locking | PR-based | No external state needed |

## Development

### Running Tests

```bash
bundle install
bundle exec rspec
```

### Testing Locally

The Ruby scripts can be run locally for debugging:

```bash
# Task selection (requires GITHUB_TOKEN, CONFIG_PATH)
GITHUB_TOKEN=$(gh auth token) \
GITHUB_REPOSITORY=owner/repo \
CONFIG_PATH=claude-gardener.yml \
CATEGORY=auto \
ruby lib/select_task.rb
```

### Key Files

**action.yml**
- Defines inputs: `anthropic_api_key`, `claude_oauth_token`, `github_token`, `config_path`, `category`
- Defines outputs: `pr_number`, `pr_url`, `skipped`
- Orchestrates the composite action steps

**lib/select_task.rb**
- Entry point for task selection
- Writes to `$GITHUB_OUTPUT` for subsequent steps
- Builds full prompt with constraints and locked files

**lib/create_pr.rb**
- Runs after Claude makes changes
- Sets git identity for commits
- Excludes output files (output.txt, etc.)
- Creates labeled PR with metadata

**lib/config.rb**
- Parses `claude-gardener.yml` from user's repo
- Provides defaults for all options
- Nested classes: `Workers`, `Priority`, `Guardrails`, `Labels`

**lib/task_selector.rb**
- Iterates priorities in order
- Checks capacity via `PrManager`
- Returns `Task` with category, prompt, locked_files

**lib/prompts/*.md**
- Category-specific instructions for Claude
- Loaded by `TaskSelector`
- Can include custom tasks from config

## Configuration Schema

Users add `claude-gardener.yml` to their repo:

```yaml
version: 1

workers:
  max_concurrent: 3          # Max simultaneous gardener PRs

priorities:
  - category: test_coverage  # Category name (matches prompt file)
    max_prs: 3               # Max open PRs for this category
    enabled: true            # Can disable categories
    tasks: []                # Custom tasks (for user_transitions)

guardrails:
  max_iterations_per_pr: 5   # Review cycles before escalation
  max_files_per_pr: 10       # Passed to Claude in prompt
  require_tests: true        # Passed to Claude in prompt

labels:
  base: "claude-gardener"    # Base label for all PRs
  categories: true           # Add category-specific labels

excluded_paths:              # Glob patterns to exclude
  - "vendor/**"
  - "node_modules/**"
```

## Workflow Permissions

Users need these permissions in their workflow:

```yaml
permissions:
  contents: write        # Create branches, push commits
  pull-requests: write   # Create PRs, add labels
  id-token: write        # OIDC auth for Claude action
```

And enable in repo settings:
- Settings → Actions → General → "Allow GitHub Actions to create and approve pull requests"

## Authentication Options

1. **API Key** (`anthropic_api_key`) - Pay-per-use API credits
2. **OAuth Token** (`claude_oauth_token`) - For Max/Pro subscribers

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
| "Not permitted to create PRs" | Enable in repo Settings → Actions |
| "Author identity unknown" | Fixed in create_pr.rb (sets git config) |
