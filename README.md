# Claude Gardener

A GitHub Action that enables Claude to continuously make small improvements to your codebase. Claude Gardener scans for improvements, creates work items, and opens PRs automatically.

## How It Works

1. **Scan**: Analyzes your codebase per category (test coverage, security, etc.) and creates GitHub issues with checklists of improvements
2. **Work**: Picks items from those checklists, makes focused changes, and creates PRs
3. **Handle**: Responds to PR reviews, fixes build failures, and cleans up after merge

## Quick Start

### 1. Create the workflows

You need three workflow files. Copy them from the [templates](templates/workflows/) directory:

**`.github/workflows/gardener-scan.yml`** - Scans for improvements:

```yaml
name: Gardener Scan

on:
  workflow_dispatch: {}
  # schedule:
  #   - cron: '0 6 * * 1'  # Every Monday at 6am

permissions:
  contents: read
  issues: write
  id-token: write

jobs:
  plan:
    runs-on: ubuntu-latest
    outputs:
      categories: ${{ steps.plan.outputs.categories }}
      plan_issue: ${{ steps.plan.outputs.plan_issue }}
      skipped: ${{ steps.plan.outputs.skipped }}
    steps:
      - uses: actions/checkout@v4

      - name: Create scan plan
        id: plan
        uses: mockdeep/claude-gardener/actions/plan-scan@main
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}

  scan:
    needs: plan
    if: needs.plan.outputs.skipped != 'true'
    runs-on: ubuntu-latest
    strategy:
      matrix:
        category: ${{ fromJson(needs.plan.outputs.categories) }}
      max-parallel: 2
      fail-fast: false
    steps:
      - uses: actions/checkout@v4

      - name: Run scan
        uses: mockdeep/claude-gardener/actions/run-scan@main
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          category: ${{ matrix.category }}
          plan_issue: ${{ needs.plan.outputs.plan_issue }}
```

**`.github/workflows/gardener-work.yml`** - Executes improvements:

```yaml
name: Gardener Work

on:
  workflow_dispatch: {}

permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write

jobs:
  setup:
    runs-on: ubuntu-latest
    outputs:
      tasks: ${{ steps.setup.outputs.tasks }}
      skipped: ${{ steps.setup.outputs.skipped }}
    steps:
      - uses: actions/checkout@v4

      - name: Select work items
        id: setup
        uses: mockdeep/claude-gardener/actions/setup-work@main
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}

  work:
    needs: setup
    if: needs.setup.outputs.skipped != 'true'
    runs-on: ubuntu-latest
    strategy:
      matrix:
        task: ${{ fromJson(needs.setup.outputs.tasks) }}
      max-parallel: 3
      fail-fast: false
    steps:
      - uses: actions/checkout@v4

      - name: Execute work item
        uses: mockdeep/claude-gardener/actions/work@main
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          task: ${{ toJson(matrix.task) }}
```

### 2. Add authentication

**Option A: API Key (pay-per-use)**

```bash
gh secret set ANTHROPIC_API_KEY
```

**Option B: OAuth Token (for Max/Pro subscribers)**

```bash
# Get your token
claude auth token

# Add as secret
gh secret set CLAUDE_OAUTH_TOKEN
```

Then use `claude_oauth_token` instead of `anthropic_api_key` in the workflows.

### 3. Enable PR creation

Go to **Settings -> Actions -> General -> Workflow permissions** and check:
- "Allow GitHub Actions to create and approve pull requests"

### 4. Add configuration (optional)

Create `claude-gardener.yml` in your repository root:

```yaml
version: 2

max_concurrent: 3

categories:
  - test_coverage
  - code_improvements

excluded_paths:
  - "vendor/**"
  - "node_modules/**"
```

### 5. Run it

1. Go to **Actions -> Gardener Scan -> Run workflow** to scan for improvements
2. Review the created issues to see what was found
3. Go to **Actions -> Gardener Work -> Run workflow** to execute improvements
4. Review the PRs that are created

## Task Categories

| Category | Description |
|----------|-------------|
| `test_coverage` | Adds tests for code with missing coverage |
| `security_fixes` | Fixes security vulnerabilities (OWASP Top 10, secrets, etc.) |
| `linter_fixes` | Fixes linter violations systematically |
| `code_improvements` | Small improvements to readability and maintainability |
| `add_tooling` | Adds development tooling (linters, test frameworks, etc.) |

## Configuration Reference

| Option | Default | Description |
|--------|---------|-------------|
| `version` | 1 | Config schema version (use `2` for simplified format) |
| `max_concurrent` | 5 (v2) / 3 (v1) | Maximum simultaneous gardener PRs |
| `categories` | All built-in | List of categories to scan and work on |
| `excluded_paths` | [] | Glob patterns to exclude from scanning |
| `pr_assignees` | [] | GitHub usernames to assign to each PR |
| `pr_reviewers` | [] | GitHub usernames to request review from on each PR |

## How Coordination Works

- **Scan plan issues** track which categories have been scanned
- **Aggregate issues** contain checklists of work items per category
- Work items are **claimed** by PRs to prevent duplicate work
- Items are **checked off** when PRs merge
- Aggregate issues **auto-close** when all items are complete
- Re-running a scan closes old issues and creates fresh ones

## Troubleshooting

| Error | Solution |
|-------|----------|
| "Credit balance too low" | Add API credits or use OAuth token |
| "Resource not accessible by integration" | Add required permissions to workflow |
| "id-token: write" error | Add `id-token: write` to permissions |
| "Not permitted to create PRs" | Enable in Settings -> Actions -> General |

## License

MIT
