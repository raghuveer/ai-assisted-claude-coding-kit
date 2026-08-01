---
id: T-20260801-finding-vocabulary-has-no-class-for-test
title: Finding vocabulary has no class for test coverage or verification defects
epic: feedback-loop
tier: T1
state: open
---

## Intent

`kit-finding.sh --vocab` accepts:

    class:    fail-open race false-rationale perf compliance correctness style unclassified
    severity: critical major minor nit

On a real T2 review, `implementation-reviewer` raised three findings with no home in that
list:

- a missing regression test for CLI glue -- a test-coverage gap
- an unverified claim about whether commands had actually been run -- a
  process/verification defect
- a positive note that scope discipline held -- arguably not a finding at all

Only the first of its four mapped cleanly (`fail-open`). `unclassified` exists as the
escape hatch, but routing a whole defect category through it destroys the signal the
table is for: the README's accelerator query groups by `lang, class`, and a pile of
`unclassified` teaches nothing.

Test coverage is one of the most common things a reviewer legitimately finds. Its absence
from the vocabulary is why reviewers invent class names.

## Acceptance criteria

- [ ] a class exists for test-coverage gaps
- [ ] a decision is recorded on whether verification/process defects are in scope for this
      table at all, or belong somewhere else
- [ ] agents cannot silently invent a class -- either they can read the vocabulary, or the
      rejection is loud at the point it happens
- [ ] adding a class does not require editing it in four places, which is what caused the
      drift the `--vocab` flag was introduced to fix

## Notes

Adding classes has a cost the script header already names: the vocabulary was restated in
the schema comment, two skills and the agent output contracts, and all four drifted. Any
fix here should reduce the number of places the list lives, not add a sixth.
