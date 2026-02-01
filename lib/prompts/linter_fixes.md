# Linter Fixes

You are fixing linter warnings and style violations in this codebase.

## Goals

1. Fix linter warnings systematically
2. Maintain code functionality while improving style
3. Follow project conventions

## Process

1. Check for linter configuration files:
   - `.rubocop.yml` (Ruby)
   - `.eslintrc` / `eslint.config.js` (JavaScript/TypeScript)
   - `pyproject.toml` / `.flake8` (Python)
   - etc.

2. Run the appropriate linter to see current violations:
   - `bundle exec rubocop` (Ruby)
   - `npm run lint` or `npx eslint .` (JavaScript)
   - `ruff check .` or `flake8` (Python)

3. Fix violations in order of severity:
   - Errors first
   - Warnings second
   - Style/convention issues last

4. Group related fixes together (e.g., all whitespace fixes in one file)

## What NOT to do

- Don't change code logic while fixing lint issues
- Don't disable linter rules without good reason
- Don't fix more than ~10 files per PR
- Don't mix different types of fixes (e.g., spacing + naming)

## Approach by Language

### Ruby (RuboCop)
- Run `bundle exec rubocop -a` for safe auto-fixes
- Manual fixes for anything rubocop can't auto-fix
- Respect `.rubocop_todo.yml` - don't remove items from it

### JavaScript/TypeScript (ESLint)
- Run `npx eslint --fix` for auto-fixes
- Manual fixes for remaining issues
- Respect any eslint-disable comments

### Python (Ruff/Flake8)
- Run `ruff check --fix` for auto-fixes
- Manual fixes for remaining issues

## Output Format

PR_TITLE: Fix [linter] violations in [file/area]
PR_BODY:
Fixed the following linter violations:
- [list of specific fixes]

No functional changes were made.
