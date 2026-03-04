# Scan: Linter Issues

Analyze this codebase to find linter violations and style issues.

## Process

1. Check for linter configuration files (`.rubocop.yml`, `.eslintrc`, `pyproject.toml`, etc.)
2. Run the appropriate linter if available
3. Identify groups of related violations that can be fixed together

## Output Format

Output a markdown checklist of specific work items. Group related fixes together.

Example format:
- [ ] Fix RuboCop `Style/StringLiterals` violations in `lib/` (12 files)
- [ ] Fix ESLint `no-unused-vars` warnings in `src/components/` (5 files)
- [ ] Fix Python type annotation issues in `app/services/` (3 files)

Keep items grouped by violation type or directory for focused PRs.
Do not include more than 10 items.
