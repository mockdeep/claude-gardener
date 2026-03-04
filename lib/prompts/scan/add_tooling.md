# Scan: Missing Tooling

Analyze this codebase to identify missing development tooling.

## Process

1. Check what tooling already exists (linters, test frameworks, CI/CD, formatters)
2. Identify gaps based on the language/framework
3. Suggest only tooling that would clearly benefit the project

## Output Format

Output a markdown checklist of specific work items.

Example format:
- [ ] Add RuboCop configuration with project-appropriate rules
- [ ] Add GitHub Actions CI workflow for running tests
- [ ] Create CLAUDE.md with project conventions and development guidelines
- [ ] Add pre-commit hooks for linting

Keep items to tooling that is standard for the project's ecosystem.
Do not include more than 5 items.
