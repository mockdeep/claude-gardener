# Claude Gardener

A GitHub Action that enables Claude to continuously make small improvements to your codebase. Claude Gardener selects tasks, makes focused changes, and creates PRs automatically.

## How It Works

1. **Trigger**: Run manually from the Actions tab (or on a schedule)
2. **Select**: Picks the highest priority task with available capacity
3. **Execute**: Claude makes focused changes to your code
4. **PR**: Creates a labeled pull request for review
5. **Repeat**: After merge, run again for the next improvement

## Quick Start

### 1. Create the workflow

Add `.github/workflows/claude-gardener.yml`:

```yaml
name: Claude Gardener

on:
  workflow_dispatch:
    inputs:
      category:
        description: 'Category to work on'
        required: false
        type: choice
        options:
          - auto
          - test_coverage
          - security_fixes
          - linter_fixes
          - code_improvements

permissions:
  contents: write
  pull-requests: write
  id-token: write

jobs:
  garden:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run Claude Gardener
        uses: mockdeep/claude-gardener@main
        with:
          claude_oauth_token: ${{ secrets.CLAUDE_OAUTH_TOKEN }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
          category: ${{ github.event.inputs.category || 'auto' }}
```

### 2. Add authentication

**Option A: OAuth Token (for Max/Pro subscribers)**

```bash
# Get your token
claude auth token

# Add as secret
gh secret set CLAUDE_OAUTH_TOKEN
```

**Option B: API Key (pay-per-use)**

```bash
gh secret set ANTHROPIC_API_KEY
```

Then use `anthropic_api_key` instead of `claude_oauth_token` in the workflow.

### 3. Enable PR creation

Go to **Settings → Actions → General → Workflow permissions** and check:
- "Allow GitHub Actions to create and approve pull requests"

### 4. Add configuration (optional)

Create `claude-gardener.yml` in your repository root:

```yaml
version: 1

workers:
  max_concurrent: 3

priorities:
  - category: test_coverage
    max_prs: 3
    enabled: true

  - category: linter_fixes
    max_prs: 5
    enabled: true

  - category: code_improvements
    max_prs: 3
    enabled: true

guardrails:
  max_files_per_pr: 10
  require_tests: true

excluded_paths:
  - "vendor/**"
  - "node_modules/**"
```

### 5. Run it

Go to **Actions → Claude Gardener → Run workflow**

## Task Categories

| Category | Description |
|----------|-------------|
| `test_coverage` | Adds tests for code with missing coverage |
| `security_fixes` | Fixes security vulnerabilities (OWASP Top 10, secrets, etc.) |
| `linter_fixes` | Fixes linter violations systematically |
| `code_improvements` | Small improvements to readability and maintainability |

### Custom Tasks

Define your own refactoring tasks:

```yaml
priorities:
  - category: user_transitions
    max_prs: 2
    enabled: true
    tasks:
      - "Migrate from RSpec let blocks to inline setup"
      - "Replace ERB views with Phlex components"
```

## Configuration Reference

| Option | Default | Description |
|--------|---------|-------------|
| `workers.max_concurrent` | 3 | Maximum simultaneous gardener PRs |
| `priorities[].category` | - | Task category name |
| `priorities[].max_prs` | 3 | Max open PRs for this category |
| `priorities[].enabled` | true | Whether this category is active |
| `priorities[].tasks` | [] | Custom task descriptions |
| `guardrails.max_files_per_pr` | 10 | Max files changed per PR |
| `guardrails.require_tests` | true | Require test coverage |
| `labels.base` | "claude-gardener" | Base label for PRs |
| `excluded_paths` | [] | Glob patterns to exclude |

## How Coordination Works

Claude Gardener uses PR-based locking to prevent conflicts:

- Checks which files are touched by open gardener PRs
- Avoids modifying those files until PRs are merged/closed
- Multiple runs can work on different areas simultaneously

## Inputs

| Input | Required | Description |
|-------|----------|-------------|
| `anthropic_api_key` | No* | Anthropic API key (pay-per-use) |
| `claude_oauth_token` | No* | OAuth token for Max/Pro subscribers |
| `github_token` | Yes | GitHub token for PR operations |
| `config_path` | No | Path to config file (default: `claude-gardener.yml`) |
| `category` | No | Specific category to work on (default: `auto`) |

*One of `anthropic_api_key` or `claude_oauth_token` is required.

## Outputs

| Output | Description |
|--------|-------------|
| `pr_number` | The PR number created (if any) |
| `pr_url` | The PR URL created (if any) |
| `skipped` | Whether the run was skipped (at capacity or no work) |

## Troubleshooting

| Error | Solution |
|-------|----------|
| "Credit balance too low" | Add API credits or use OAuth token |
| "Resource not accessible by integration" | Add required permissions to workflow |
| "id-token: write" error | Add `id-token: write` to permissions |
| "Not permitted to create PRs" | Enable in Settings → Actions → General |

## License

MIT
