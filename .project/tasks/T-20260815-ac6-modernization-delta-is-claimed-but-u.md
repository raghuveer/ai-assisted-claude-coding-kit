---
id: T-20260815-ac6-modernization-delta-is-claimed-but-u
title: AC6 modernization delta is claimed but untested
tier: T3
lang: bash
paths: .project/tasks, docs, tests
state: open
---

## Intent

AC6 of `T-20260814-one-entry-mechanism-brownfield-is-the-ge` says the modernization source-to-target
delta must be expressible without a second mechanism. Nothing implements it and nothing tests it.

The delta lives in the solution overlay, which `docs/DESIGN-NOTES.md` section 2 marks proposed and
unbuilt. Design 2 inherited the claim from design 1 without re-examining it, and the conformance
step whose comment mentions the three starting conditions actually tests a one-commit history --
the imported-history case, not the delta.

AC6 is therefore satisfied by an argument rather than a check. Found by the final implementation
review, 2026-08-15.

## Acceptance criteria

- [ ] Either AC6 is demonstrated -- a delta expressed as an input to the existing mechanism, with a
      fixture -- or the criterion is amended to defer it until the overlay exists, agreed rather
      than assumed.
- [ ] The step comment stops implying coverage it does not have.

## Notes

Filed 2026-08-15. Do not close the parent on the current wording: an acceptance criterion met by an
unbuilt component is met by nothing.
