---
id: T-20260801-reviewer-agents-cannot-run-the-tools-the
title: Reviewer agents cannot run the tools their instructions require
epic: agent-contracts
tier: T2
lang: markdown
state: open
---

## Intent

`implementation-reviewer`, `approach-reviewer` and `security-reviewer` are all
`tools: Read, Grep, Glob`. All three carry this line:

> Run `kit-finding.sh --vocab` for the accepted class and severity values rather than
> guessing: an unrecognised value is rejected, not stored, and the finding is simply lost.

None of them can run it. The instruction is unexecutable as written, in all three.

Observed on a real run (greenfield TypeScript project, 2026-08-01):

- `approach-reviewer` guessed the vocabulary correctly. 18 findings, all valid classes.
- `implementation-reviewer` guessed wrong. It emitted `fail-open-guard`,
  `missing-integration-test`, `unverified-claim` and `scope-discipline-clean`. Three of
  its four findings were rejected as unknown classes -- exactly the outcome the
  instruction was written to prevent.

The same tool gap has a second, larger cost. `implementation-reviewer` was asked to
confirm four ladder commands exit 0. It cannot execute, so it ranked "independently
confirm the commands run" as its TOP required change -- a finding unresolvable by
construction, which recurs on every run where verification matters. It spent 104,769
tokens, comparable to the coder it was reviewing, and concluded "strong circumstantial
evidence, but this is not independent confirmation."

It also has no `git`, so on an uncommitted change it cannot diff. It reviewed the whole
tree instead of the change, and resorted to reading the operator's
`.claude/settings.local.json` to reverse-engineer which commands the coder had run.

## Acceptance criteria

- [ ] every instruction in an agent file is executable with that agent's declared tools,
      or the tool is granted
- [ ] a reviewer asked to verify behaviour can execute, or is never asked to
- [ ] `implementation-reviewer` can diff the change under review rather than reading the
      whole tree
- [ ] a check that fails when an agent file references a script the agent cannot run --
      this drifted back after being fixed once, so it needs a test, not just a fix

## Notes

`approach-reviewer` at 19 tool uses versus `implementation-reviewer` at 45 is the tell:
design review is a reading task and the current toolset fits it; implementation review is
an execution task and it does not. The two rungs have identical tool grants and should not.

Cheapest fix is granting Bash to `implementation-reviewer`. Whether the other two need it
is a separate call -- the `--vocab` line is a problem for all three regardless, and could
be fixed by inlining the vocabulary, though that duplication is what caused the original
drift.
