# Scan: Test Coverage

Analyze this codebase to find specific, actionable test coverage gaps.

## Process

1. Read CLAUDE.md if present for testing guidelines
2. Identify the test framework and test directory structure
3. Find files/modules that lack test coverage by:
   - Comparing source files to test files
   - Looking for complex logic without corresponding tests
   - Identifying untested edge cases in existing tested code

## Output Format

Output a markdown checklist of specific work items. Each item should be a single, focused task that a developer could complete in one PR.

Example format:
- [ ] Add unit tests for `app/models/user.rb` - missing tests for `#validate_email` and `#normalize_name`
- [ ] Add integration test for checkout flow - no test covers the full purchase path
- [ ] Add edge case tests for `lib/parser.rb` - empty input and malformed data not tested

Keep items specific and actionable. Include the file path and what specifically needs testing.
Do not include more than 10 items.
