# Scan: Security Vulnerabilities

Analyze this codebase to find specific, actionable security issues.

## Process

1. Read CLAUDE.md if present for security guidelines
2. Scan for common vulnerability patterns:
   - SQL injection, command injection, XSS
   - Hardcoded secrets, API keys, passwords
   - Missing authentication/authorization checks
   - Insecure data handling
   - Known vulnerable dependency versions

## Output Format

Output a markdown checklist of specific work items. Each item should be a single, focused fix.

Example format:
- [ ] Fix SQL injection in `app/controllers/search_controller.rb:45` - user input interpolated into query
- [ ] Remove hardcoded API key in `config/services.rb:12`
- [ ] Add CSRF protection to `POST /api/webhooks` endpoint

Keep items specific with file paths and line numbers where possible.
Do not include more than 10 items.
Do not flag theoretical vulnerabilities without clear evidence.
