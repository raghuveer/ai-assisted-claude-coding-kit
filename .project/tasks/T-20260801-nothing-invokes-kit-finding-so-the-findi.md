---
id: T-20260801-nothing-invokes-kit-finding-so-the-findi
title: Nothing invokes kit-finding so the findings loop is open circuit
epic: feedback-loop
tier: T2
state: open
---

## Intent

The README says findings "are recorded with language and defect class, which is the
mechanism by which the accelerators are improved from real work rather than invented."

On a real project that had run a T2 implementation review and a T3 design review, the
finding table held ZERO rows. Both reviewers had emitted correctly formatted
`Findings (recordable)` blocks. Nothing consumed them.

The agent files say the lines "are piped straight into `kit-finding.sh --batch`" -- but
nothing does the piping. No hook, no skill step, no script. It happens only if the
orchestrating session does it by hand, which means it happens when someone remembers,
which is the failure mode the checkpoint hook exists to avoid.

Consequence: every escape-rate and accelerator claim in the README is computed from an
empty table. `T0 0/2, T1 0/5, T2 0/7, T3 0/13` reads as "nothing escaped" and actually
means "nothing was recorded."

19 rows appeared the moment the blocks were piped in manually.

## Acceptance criteria

- [ ] findings reach the table without the operator remembering
- [ ] a review that produces findings and records none is visible as a warning, the way
      trailer discipline already is
- [ ] rejected findings are surfaced at the point of rejection, not discovered later by
      querying

## Notes

Interacts with [[T-20260801-reviewer-agents-cannot-run-the-tools-the]]: even once
something does the piping, roughly half the emitted findings are currently rejected for
unknown classes, so fixing the plumbing alone would record a biased sample.

The checkpoint hook is the obvious home, but it fires per work unit and reviews happen
mid-unit, so the findings would need somewhere to accumulate first.
