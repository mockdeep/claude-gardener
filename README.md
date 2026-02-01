# Claude Gardener 🌱

A GitHub Action that enables Claude to continuously make small improvements to your codebase. Claude Gardener creates focused PRs, responds to review feedback, and learns from the process.

## How It Works

Claude Gardener operates in a continuous improvement loop:

1. **Start**: Manual trigger or scheduled run
2. **Select**: Pick the highest priority task with available capacity
3. **Execute**: Claude makes focused changes and creates a PR
4. **Review**: You review and provide feedback
5. **Iterate**: Claude addresses feedback (up to configured limit)
6. **Merge**: When satisfied, merge the PR
7. **Repeat**: After merge, Claude starts on the next task

## Quick Start

### 1. Create the workflow file

Add `.github/workflows/claude-gardener.yml` to your repository:

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

  pull_request_review:
    types: [submitted]

  push:
    branches: [main]

jobs:
  garden:
    runs-on: ubuntu-latest
    if: |
      github.event_name == 'workflow_dispatch' ||
      (github.event_name == 'pull_request_review' &&
       contains(github.event.pull_request.labels.*.name, 'claude-gardener')) ||
      (github.event_name == 'push' &&
       contains(github.event.head_commit.message, '[gardener]'))

    steps:
      - uses: actions/checkout@v4

      - name: Run Claude Gardener
        uses: mockdeep/claude-gardener@v1
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          github_token: ${{ secrets.GITHUB_TOKEN }}
          event_type: ${{ github.event_name }}
          category: ${{ github.event.inputs.category || 'auto' }}
```

### 2. Add configuration (optional)

Create `claude-gardener.yml` in your repository root:

```yaml
version: 1

workers:
  max_concurrent: 3

priorities:
  - category: test_coverage
    max_prs: 3
    enabled: true

  - category: security_fixes
    max_prs: 2
    enabled: true

  - category: linter_fixes
    max_prs: 5
    enabled: true

  - category: code_improvements
    max_prs: 3
    enabled: true

guardrails:
  max_iterations_per_pr: 5
  max_files_per_pr: 10
  require_tests: true

excluded_paths:
  - "vendor/**"
  - "node_modules/**"
```

### 3. Add your Anthropic API key

Add `ANTHROPIC_API_KEY` to your repository secrets.

### 4. Start gardening

Go to Actions → Claude Gardener → Run workflow

## Task Categories

### test_coverage
Identifies code with missing or low test coverage and adds focused, behavior-driven tests.

### security_fixes
Scans for security vulnerabilities (OWASP Top 10, hardcoded secrets, etc.) and fixes them.

### linter_fixes
Runs your configured linter and fixes violations systematically.

### code_improvements
Makes small improvements to code readability, performance, and maintainability.

### Custom Tasks

You can define custom refactoring tasks:

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
| `priorities[].tasks` | [] | Custom tasks for user_transitions |
| `guardrails.max_iterations_per_pr` | 5 | Review cycles before escalating |
| `guardrails.max_files_per_pr` | 10 | Max files changed per PR |
| `guardrails.require_tests` | true | Require test coverage |
| `labels.base` | "claude-gardener" | Base label for PRs |
| `labels.categories` | true | Add category-specific labels |
| `excluded_paths` | [] | Glob patterns to exclude |

## How Coordination Works

Claude Gardener uses PR-based locking to prevent conflicts:

- Before starting work, it checks which files are touched by open gardener PRs
- It avoids modifying those files until the PRs are merged or closed
- Multiple gardener instances can work on different areas simultaneously

## Escalation

When a PR reaches `max_iterations_per_pr` review cycles without being approved:

1. The `needs-human` label is added
2. A comment explains the situation
3. Claude stops working on that PR

You can then:
- Provide more specific guidance
- Make changes yourself
- Close the PR if the approach isn't working

## Learning

Claude Gardener learns from feedback:

- If it discovers project conventions, it updates `CLAUDE.md`
- Repeated patterns may become skills in `.claude/skills/`
- Future PRs benefit from this accumulated knowledge

## License

MIT
