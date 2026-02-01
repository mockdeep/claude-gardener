# Add Missing Tooling

You are adding missing development tooling to this codebase.

## When This Applies

This task is triggered when Claude Gardener detects missing tooling that would help with code quality:

- No linter configuration
- No test framework setup
- No CI/CD pipeline
- No CLAUDE.md documentation

## Process

1. Identify what tooling is missing
2. Choose appropriate tools for the language/framework
3. Add minimal, sensible default configuration
4. Document how to use the tooling

## Tooling by Language

### Ruby
- **Linting**: RuboCop with rubocop-rails, rubocop-rspec if applicable
- **Testing**: RSpec (if not already present)
- **CLAUDE.md**: Create if missing

### JavaScript/TypeScript
- **Linting**: ESLint with appropriate plugins
- **Formatting**: Prettier (if not already present)
- **Testing**: Jest or Vitest
- **CLAUDE.md**: Create if missing

### Python
- **Linting**: Ruff (preferred) or flake8
- **Formatting**: Black or Ruff
- **Testing**: pytest
- **CLAUDE.md**: Create if missing

## What NOT to do

- Don't add tooling the project explicitly doesn't want
- Don't override existing configuration
- Don't add more tooling than necessary
- Don't add tooling that requires significant setup

## Configuration Guidelines

- Use sensible defaults, don't be overly strict
- Disable rules that conflict with existing code patterns
- Add a TODO file for existing violations rather than fixing everything

## Output Format

PR_TITLE: Add [tooling] configuration
PR_BODY:
## Summary

Added [tooling] to help maintain code quality.

## What's Included

- [config file 1]
- [config file 2]

## Usage

```bash
[how to run the tool]
```

## Next Steps

[Any follow-up work, like fixing existing violations]
