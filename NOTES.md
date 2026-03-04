## Goals

* Systematically improve a codebase
    * Identify missing tooling (coverage, linters, etc.)
    * Add unit test coverage
    * Add end-to-end test coverage
    * Fix security issues
    * Fix linter violations
    * Address open issues
    * Improve overall architecture

## Process

1) Initially, scan the codebase and create aggregate issues for each of the
above categories. Each aggregate issue should have a checklist of the specific
items that need to be addressed. For example, the "Add unit test coverage"
issue might have a checklist of all the files missing coverage.

2) For each aggregate issue, workers will each create a separate PR that
addresses one of the items in the checklist. For example, the "Add unit test
coverage" PR might add a unit test for one of the files missing coverage.
    a) Each worker should first check for relevant skills to apply.
    b) Worker should make changes closely focused on the specific issue.
    c) Worker should update or create relevant skills as part of the PR.
    d) Worker should look for opportunities to clean up or condense skills.
    e) Worker should update `AGENTS.md` as needed.

3) After PR is made, when a review is submitted, it should trigger a worker to
address any feedback. It should again make any relevant updates to skills and
`AGENTS.md`

4) When a PR is merged, more workers should pick up if relevant.

## Needs

* Limit the number of PRs created per day, or maybe open at a time.
* Need the agent to be able to run freely with `--dangerously-skip-permissions`.

## Reference

* Gas Town https://github.com/steveyegge/gastown
* Beads https://github.com/steveyegge/beads
* Claude Agent Teams https://code.claude.com/docs/en/agent-teams
* Agent Docs https://openai.com/index/harness-engineering/#we-made-repository-knowledge-the-system-of-record
* code-on-incus https://github.com/mensfeld/code-on-incus
* Github Dev Containers https://github.com/devcontainers/
* tmx-claude, tmx-worktree https://gist.github.com/andynu/294bf3c468fdada439eb8c2eee71c9c4

## Questions

* Should we have built-in skills that can be copied over?
* How do we prevent multiple workers from picking off the same task?
* How does the process get initiated?
    * Does it happen automatically?
    * Do we assign it to an issue?
* How do we stop it if it gets too much?
* Where does it pull from?
    * Github Issues?
    * Honeybadger?
    * I've got a bunch of stuff in Trello, too.
