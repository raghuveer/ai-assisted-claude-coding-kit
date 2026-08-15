---
id: T-20260815-co-change-withheld-disabled-and-empty-ar
title: Co-change withheld disabled and empty are one empty table
tier: T3
lang: bash
paths: tooling/kit-index.sh, tooling/kit-status.sh, tests
state: open
---

## Intent

`kit-index.sh` §2b computes the co-change graph in one awk program whose `END` block has four
early exits, and **all four return before the `cochange_*` meta rows are printed**:

- pair budget exceeded — `aborted`, prints a warning to stderr, `exit`
- no commits in the window — `cctotal == 0`, `exit`
- every file hub-filtered away — `!files`, `exit`
- hairball self-check tripped — `avg > CCMAXD`, prints two warnings, `exit`

The meta rows (`cochange_pairs`, `cochange_files`, `cochange_avg_degree`, `cochange_commits`)
are written only on the success path. So a consumer reading the index sees exactly one thing in
all five cases — success-with-nothing, and the four failures — an empty `cochange` table and no
meta.

The warnings go to **stderr at build time**. They are not durable, not in the index, and not
available to anything reading the database later.

This is the kit's own `absent is not zero` rule broken inside the indexer. Found by both
approach reviewers independently on 2026-08-15 (round 1 finding 6, blind round finding 6) while
reviewing `T-20260814-one-entry-mechanism-brownfield-is-the-ge`, whose design proposes to read
the `cochange` table for "structural clusters, **or the fact that it was withheld**" — a fact
the table cannot currently carry. That design is blocked on this, but the defect is older than
it and is filed separately rather than folded in.

## Acceptance criteria

- [ ] The four non-success states are distinguishable from success-with-zero by a reader that
      has only the index — no stderr, no build log.
- [ ] Whatever records the state is written on EVERY path out of the awk `END` block, including
      the two that currently print a warning and exit.
- [ ] A consumer that asks "was the graph withheld?" gets an answer, and a consumer that asks it
      of a repository indexed before this change gets "did not look" rather than a false "no".
- [ ] Each of the five states is proved by a mutation that is red alone. A fixture asserting only
      that meta rows exist on the happy path does not discharge this.
- [ ] `kit-status.sh` reports the state where it currently reports co-change, using the existing
      house convention for naming what could not be determined.

## Notes

Filed 2026-08-15 out of the entry-mechanism approach reviews.

The obvious fix — move the meta writes above the exits — is not sufficient on its own: the
values differ per state (`avg` is meaningful when the hairball check trips and undefined when
there are no commits), so a single row set written unconditionally would report zeros that mean
four different things. That is the same defect one level down.

Careful: an index built before this change has no state row at all, and the absence must read as
`did not look`, not as a fifth state. `T-20260814-a-fresh-adoption-reports-none-outstandin`
is the same shape in the findings gate and its resolution should be consistent with this one.
