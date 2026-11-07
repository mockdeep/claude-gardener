# Security fix

Fix the security issue described below. You're in a fresh git worktree, on a
branch made just for this fix.

## How to work

1. Check the issue is real. Read the code involved and trace how input reaches
   it. If it isn't a real issue, change nothing and report `not_an_issue`,
   explaining why.
2. Make the smallest change that fixes the root cause. Don't refactor, tidy, or
   fix anything unrelated.
3. Add or update tests that would have caught the issue, following the
   project's existing test style.
4. Run the tests and make sure they pass.
5. Don't commit. Garden commits your changes using the commit message you
   report.

If you can't fix it (for example the fix needs a design decision, or the tests
can't run), stop and report `failed`, explaining what got in the way. Leave
any partial changes in place so they can be reviewed.

## Commands

You can edit files and use basic file commands. The only other commands you
can run are the test commands listed below and read-only git commands
(`git status`, `git diff`, `git log`, `git show`). Anything else will be
denied, so don't try to install packages or reach the network.

## What to report

- `outcome`: `fixed`, `not_an_issue`, or `failed`
- `summary`: a few sentences on what you changed and why, or why it isn't an
  issue, or what stopped you
- `commit_message`: a commit message for the change (see below)
