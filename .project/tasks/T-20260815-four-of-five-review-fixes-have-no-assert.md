---
id: T-20260815-four-of-five-review-fixes-have-no-assert
title: Four of five review fixes have no assertion
tier: T2
lang: bash
paths: tests/conformance.sh
state: open
---

## Intent

Five findings from the first implementation review of `kit-entry.sh` were fixed in one pass. Only
one -- the `doc_shaped` column -- gained an assertion. The other four are live code with no check
that can fail: `merges N` and the lower-bound disclosure resting on it; `skipped scanfail N`; the
`reconciled MISMATCH` branch; and the `/* */` block state machine in the tokeniser.

This is the lesson from the same review one finding earlier: an unasserted behaviour is
indistinguishable from an unimplemented one. `doc_shaped` was specified in ADR 0001 and in the
design, was simply absent from the code, and every fixture passed.

## Acceptance criteria

- [ ] Each of the four has a fixture asserting its behaviour, each proved by a mutation that turns
      it red.
- [ ] The `reconciled MISMATCH` case is CONSTRUCTED, not assumed: a fixture makes a per-file scan
      fail and asserts the mismatch is reported rather than the run dying or reading clean.
- [ ] A `/* */` block whose interior lines carry no leading `*` is asserted at its true length.

## Notes

Filed 2026-08-15. The mismatch branch is a control written against a failure nobody has ever
reproduced, which is the shape LESSONS section 1 exists for.
