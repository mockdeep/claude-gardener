# Scan: Code Improvements

Analyze this codebase to find small, focused improvement opportunities.

## Process

1. Read CLAUDE.md if present for project conventions
2. Look for improvement opportunities:
   - Dead code (unused functions, commented-out code)
   - Duplicate code that could be consolidated
   - Overly complex methods that could be simplified
   - Outdated patterns that have modern equivalents
   - Missing or outdated documentation for complex logic

## Output Format

Output a markdown checklist of specific work items. Each should be a small, safe improvement.

Example format:
- [ ] Remove unused `legacy_auth` method in `app/models/user.rb:89-120`
- [ ] Extract duplicate validation logic from `OrderController` and `CartController` into shared concern
- [ ] Simplify nested conditionals in `lib/permissions.rb:45-78`

Keep items specific and low-risk. Avoid suggesting changes to APIs or interfaces.
Do not include more than 10 items.
