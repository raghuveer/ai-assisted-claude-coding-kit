---
id: T-20260809-a-folded-git-trailer-loses-its-continuat
title: A folded git trailer loses its continuation and records a malformed id
epic: validation
tier: T3
lang: bash
paths: tooling/kit-index.sh
state: open
---

## Intent

A git trailer may be FOLDED: the value continues on the following line, indented. Git parses
that as one value. The indexer does not. Measured on a fixture, from this commit body:

    Task-Id: T-fold
    Tier: T1
    Task-Status: progress
    Fixes-Escape-Of: T-a,
      T-b

what reached the index was:

    T-fold/progress     correct
    T-fold/tiered       correct
    T-a,/escaped        WRONG -- separator kept, id malformed
    (T-b)               absent entirely

Two defects in one line. The continuation is dropped, so `T-b` is not recorded at all — an
escape silently ceases to exist. And the value is taken up to the fold rather than to the
separator, so `T-a,` is recorded as an id, comma included, which matches no task and never can.

**The `Task-Id` itself survives.** This was filed on a review claim that the whole trailer record
breaks and the commit's `Task-Id` is dropped, leaving the commit untagged. That was checked
before filing and is NOT what happens: `commits_untagged` stayed 0 and `T-fold` indexed
normally. The blast radius is the folded trailer's own value, which is narrower than the claim
and quite bad enough — a lost escape is the one record this project cannot afford to lose,
because escape rate is the metric the whole tiering design rests on.

## Relationship to existing records

This retires the narrower finding open on
`T-20260808-record-how-a-task-was-executed-so-kit-wo` — "the folded-trailer case that drops
`Fixes-Escape-Of`" — which is the same defect seen from one direction. Close that finding when
this lands rather than fixing it twice.

Interaction worth keeping: since
`T-20260808-a-task-id-matching-no-task-file-is-count`, an escape recorded against `T-a,` is no
longer hidden — `T-a,` has no task file, so the residue guard in `kit-status.sh` surfaces it as
an escape belonging to no task. That is the first time this defect becomes visible in the report
rather than only in the database, and it is how it should be found in the wild.

## Why T3

`tier.rule` floors `tooling/kit-index.sh` at T3, and the reason applies exactly: this is the
ingest seam, the failure is silent, and what it silently loses is an escape.

## Acceptance criteria

- [ ] A folded trailer's continuation is read as part of the value. `Fixes-Escape-Of: T-a,\n
      T-b` records escapes for BOTH `T-a` and `T-b`.
- [ ] A value is split on its separator, not on the fold: no id may be recorded with a trailing
      `,` or surrounding whitespace. Assert the stored id, not just the count.
- [ ] Applies to every trailer the indexer reads, not just `Fixes-Escape-Of` — `Task-Id`,
      `Tier`, `Task-Status` and `Via` come through the same record parse. `Task-Id` is known to
      survive today; that must be asserted rather than assumed once the parse changes.
- [ ] A conformance case covers a folded trailer. Nothing exercises folding today, which is why
      this survived: the fixture's trailers are all single-line.
- [ ] Check what an EMPTY continuation and a fold in the LAST trailer of the message do, since
      both are the boundary of whatever parse replaces this one.

## Notes

Found by the security reviewer during the T3 review of
`T-20260808-a-task-id-matching-no-task-file-is-count`, listed as an out-of-scope observation,
then reproduced — which is how the claim about `Task-Id` was corrected before it became a task
nobody could close. Pre-existing; not caused by that change.
