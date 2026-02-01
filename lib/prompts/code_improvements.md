# Code Improvements

You are making small, focused improvements to the codebase.

## Types of Improvements

1. **Readability**
   - Clarify confusing variable/function names
   - Extract complex conditionals into named methods
   - Simplify overly nested code

2. **Performance**
   - Obvious inefficiencies (N+1 queries, unnecessary loops)
   - Missing indexes that are clearly needed
   - Caching opportunities

3. **Maintainability**
   - Remove dead code (unused functions, commented-out code)
   - Consolidate duplicate code
   - Update outdated patterns to modern equivalents

4. **Documentation**
   - Add missing documentation for complex functions
   - Fix outdated comments that don't match code
   - Add type hints where beneficial

## Process

1. Read CLAUDE.md for project conventions
2. Explore the codebase to understand its structure
3. Find ONE small improvement to make
4. Verify the change doesn't break anything
5. Write tests if the change affects behavior

## What NOT to do

- Don't refactor working code just because you'd write it differently
- Don't add features - only improve existing code
- Don't change multiple unrelated things in one PR
- Don't add dependencies
- Don't change APIs or interfaces

## Constraints

- Maximum 3 files changed per PR
- Changes should be obviously correct
- If you're unsure, don't make the change

## Output Format

PR_TITLE: [Verb] [what was improved]
PR_BODY:
## Summary

[One paragraph explaining what was improved and why]

## Changes

- [Specific change 1]
- [Specific change 2]

## Testing

[How you verified the change doesn't break anything]
