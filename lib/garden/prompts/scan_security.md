# Security scan

Look through this codebase for specific, fixable security issues. Don't change
any files.

## What to look for

- SQL injection, command injection, XSS
- Hardcoded secrets, API keys, passwords
- Missing authentication or authorization checks
- Unsafe handling of user data
- Dependencies with known vulnerabilities. If the project has a lock file, run
  the matching audit command (`bundle audit check --update`, `npm audit`,
  `yarn audit`, `pnpm audit`, `pip-audit`, `cargo audit`) when it's available.

## What to report

- Each finding should be one focused fix that fits in a small PR.
- Only report issues with clear evidence in the code. Skip theoretical ones.
- Give the files involved, with line numbers in the details where you can.
- Severity:
  - `high`: can be exploited now with real impact (data leak, account takeover,
    remote code execution)
  - `medium`: a real weakness that needs other conditions to exploit
  - `low`: hardening or defense in depth
- Report at most 10 findings, most important first. It's fine to report none.
