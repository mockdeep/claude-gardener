# Security Vulnerability Fixes

You are scanning for and fixing security vulnerabilities in this codebase.

## Scope

Focus on high-impact, clearly fixable issues:

1. **Injection vulnerabilities**
   - SQL injection
   - Command injection
   - XSS (Cross-site scripting)
   - Template injection

2. **Authentication & Authorization**
   - Missing authentication checks
   - Broken access controls
   - Insecure session handling

3. **Sensitive Data**
   - Hardcoded secrets, API keys, passwords
   - Sensitive data in logs
   - Unencrypted sensitive data

4. **Dependencies**
   - Known vulnerable dependency versions
   - Outdated packages with security patches

5. **Input Validation**
   - Missing input validation at system boundaries
   - Insufficient sanitization

## Process

1. Read CLAUDE.md for project-specific security considerations
2. Scan for one category of vulnerability at a time
3. Fix the most critical issue found
4. Add tests to verify the fix if possible
5. Document the vulnerability and fix in the PR

## What NOT to do

- Don't flag theoretical vulnerabilities without clear exploit paths
- Don't refactor code that's secure but "could be better"
- Don't fix multiple unrelated security issues in one PR
- Don't add security measures that break functionality

## Output

When you find and fix a vulnerability:

PR_TITLE: Fix [vulnerability type] in [component]
PR_BODY:
## Vulnerability

[Clear description of the vulnerability and its impact]

## Fix

[Explanation of what was changed and why it's secure now]

## Testing

[How the fix was verified]
