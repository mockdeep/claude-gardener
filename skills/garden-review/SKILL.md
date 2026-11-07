---
name: garden-review
description: Review a security fix made by garden with the user, adjust it if asked, save lessons as guidance, and write a summary for garden. Use when started as `/garden-review <context-file>`.
argument-hint: <context-file>
---

# Garden review

You're reviewing a fix that garden (an automated tool) made on its own branch.
The current folder is that branch's worktree. Your job is to help the user
decide what to do with it, and to capture lessons so future fixes improve.

The argument is the path to a context file: $ARGUMENTS

Keep your messages short and plain. The user decides; you advise.

## 1. Overview

Read the context file first. It has the finding, the fix's note, any test
log, the branch to compare against, the test commands, and where guidance and
the summary go.

Then look at the change: `git diff <compare-against>...HEAD`, plus
`git status` for anything uncommitted.

Give the user a short rundown:

- **The issue**: one or two sentences, and whether you think it's real
- **The fix**: what changed, in plain terms
- **Tests**: whether they passed, and whether the new tests would actually
  catch the issue
- **Concerns**: anything that looks wrong, risky, too broad, or missing. Say
  "none" if there aren't any

If the status is `failed`, explain what went wrong instead (from the note and
test log), and whether the finding looks worth another try.

Then ask what they think. Don't decide for them.

## 2. Discussion and changes

Answer questions and dig into the code as needed.

If the user wants the fix changed:

1. Make the change.
2. Run the test commands from the context file.
3. If they pass, fold the change into the fix commit:
   `git add --all && git commit --amend --no-edit`. If there's no fix commit
   on this branch yet (a failed finding), make a new commit instead, with a
   message that follows the repo's commit template if it has one.
4. Tell the user what changed.

Never push, open PRs, or delete branches. Garden does that after you're done.

## 3. Lessons

Only suggest a lesson when the user clearly pushes back on the approach: they
correct it, disagree with it, or say they'd have done it differently. Don't
suggest lessons when they simply approve, or ask questions.

When you suggest one:

1. Say it in one sentence, written as guidance for future fixes ("Prefer
   ... over ...", "Don't ...").
2. Say where you'd put it and why:
   - **General** (applies to any project): a topic file in the general
     guidance folder from the context file, e.g. `fixes.md` or `testing.md`.
     Add to an existing topic file when one fits.
   - **Repo-specific** (only makes sense for this codebase): the file named
     in the context file, inside the guidance worktree (not the current
     folder). Use a skill in `.claude/skills/` there only for a narrow,
     step-by-step procedure.
3. Show the exact edit, and wait for the user's OK. They may reword it or
   move it.
4. Only then write it. Don't commit guidance changes; garden does that.

Keep guidance short and specific, and avoid repeating what's already there.
Read the target file before editing.

## 4. Wrap-up

When the user says they're done (or is about to exit), write the summary file
named in the context file, then tell them it's written and they can exit.

Use this format:

```markdown
# <finding title>

**Suggested decision:** approve | reject | retry | skip

**Reason:** <one or two sentences, in the user's terms. If rejecting, say why
the fix or finding was turned down; this is shown to future scans so they
don't report it again.>

## Discussion

<a few bullet points: what was looked at, concerns raised, what was decided>

## Changes made during review

<bullets, or "None">

## Lessons saved

<each lesson and where it went, or "None">
```

Base the suggested decision on what the user said, not your own view. Use
`retry` only for a failed finding that's worth another automatic attempt, and
`skip` when they haven't decided.

If the user exits without asking, that's fine; garden copes with a missing
summary.
