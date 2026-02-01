# Test Coverage Improvement

You are improving test coverage for this codebase.

## Goals

1. Identify files with low or missing test coverage
2. Write focused, behavior-driven tests
3. Follow existing test patterns in the codebase
4. Keep changes focused - one logical area per PR

## Process

1. First, look for a CLAUDE.md file and read any testing guidelines
2. Examine existing tests to understand patterns and conventions
3. Find code that lacks tests by:
   - Looking for files without corresponding test files
   - Finding functions/methods that aren't exercised by tests
   - Checking for edge cases that aren't covered

4. Write tests that:
   - Test behavior, not implementation
   - Use descriptive test names
   - Follow the Arrange-Act-Assert pattern
   - Cover both happy paths and error cases

## What NOT to do

- Don't add tests for trivial code (getters/setters, simple delegations)
- Don't rewrite existing tests unless they're broken
- Don't change production code just to make it more testable (unless that's also an improvement)
- Don't add more than one test file per PR

## Learning

If you discover testing conventions specific to this project:
- Update CLAUDE.md with testing guidelines
- Or create a skill file at .claude/skills/testing.md
