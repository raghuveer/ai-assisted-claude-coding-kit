---
id: T-20260814-nothing-checks-that-a-finding-s-file-and
title: Nothing checks that a finding's file and symbol references exist
epic: validation
tier: T2
lang: bash
paths: tooling/kit_findings.py, tooling/kit-finding.sh, tests/conformance.sh
state: open
---

## Intent

A finding carries `file_path` and `line_no`, and the contract says they exist so the finding can
be **re-checked**. Nothing verifies that the path is real, that the line exists, or that any
`function()` named in the summary corresponds to anything in the repository.

A reviewer that invents a plausible identifier produces a finding that reads exactly like a true
one. It is recorded, counted, tiered, and reaches the escape-rate denominator. The kit has 252
findings and has never checked one of these references.

## Why this is the cheapest real control available here

It needs **no model and no judgement**. The repository is on disk; a path either resolves or it
does not; a symbol either appears or it does not. It is a grep, which is what this kit is made
of, and it attacks the one failure mode that is invisible to review: fabricated specifics that
look credible.

It is also genuinely able to fail, which makes it mutation-provable — unlike most checks on
review *content*, which can only assert that something was written.

## The change

At record time, in the validator that already owns every other check:

- **Path existence.** `file_path`, when present, resolves inside the project root. A path that
  does not resolve is refused, or recorded with the discrepancy attached — decide which, and note
  that refusing a whole batch for one bad path repeats the all-or-nothing lesson.
- **Line plausibility.** `line_no` does not exceed the file's length.
- **Symbol references.** Identifiers of the form `name()` in `summary` are looked for in the
  named file, or in the repository when no file is given. Absence is a signal, not proof — a
  reviewer may name a function it is proposing rather than one that exists — so this reports
  rather than refuses.

Two things to get right: a path is untrusted text and must not be interpolated into a glob or a
shell command (the shape this kit has an open lint task for), and the check runs against the tree
as it is at record time, which is not necessarily the tree the finding was about.

## Acceptance criteria

- [ ] A finding naming a file that does not exist is not recorded as though it does.
- [ ] A finding naming a line beyond the end of its file is caught.
- [ ] A symbol named in a summary that appears nowhere is reported.
- [ ] A finding whose references are all valid records exactly as it does today — the control
      must not tax the normal path.
- [ ] Path handling survives a filename containing a space, a quote and a glob metacharacter.
- [ ] Each control is mutation-proved on its own assertion.

## Notes

Filed 2026-08-15. The idea is adopted from external reference material on output fidelity; the
implementation is entirely local — the kit already stores `file_path` and `line_no` and already
has the one validator that would host the check.
