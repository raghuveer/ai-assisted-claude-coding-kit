---
id: T-20260808-task-state-cannot-express-no-longer-rele
title: Task state cannot express no longer relevant, which a brownfield inventory needs
epic: planning
tier: T3
lang: bash
paths: tooling/kit-trailers.sh, tooling/kit-index.sh, tooling/kit-status.sh
state: open
---

## Intent

The state vocabulary is enforced in one place, `tooling/kit-trailers.sh`:

    started | progress | blocked | unblocked | done | abandoned

Adopting an existing codebase means back-filling an inventory from a roadmap and its child
documents, and that inventory has four outcomes, not three: not yet started, in flight,
finished, and **no longer relevant**. The last one has no home. `abandoned` is the nearest
and it means something different — abandoned is a judgement about the ATTEMPT, "we stopped";
not-relevant is a judgement about the WORK, "this should not be done at all". Collapsing them
loses the distinction exactly where an adopter needs it, on the first day, across possibly
most of the backlog.

It also corrupts a metric. Escape rate and the tier reports count `done` and `abandoned` as
closed. A pile of items that were never work, filed as abandoned, reads as a project that
abandons a great deal.

## Why T3

`tier.rule` puts a T3 floor on `tooling/kit-trailers.sh`, and the reason given in the profile
is exact: the indexer and the validator are where a silent wrong answer is most expensive.
This is a vocabulary change in the validator. The finding vocabulary has already drifted
across four locations once in this repository, and the agents then emitted values the recorder
rejected outright — a vocabulary change is precisely the kind of edit that looks trivial and
is not.

## Acceptance criteria

- [ ] One new value, defined in ONE place, with the existing ones. Whatever it is called, the
      distinction it must preserve is attempt-versus-work: `abandoned` = we stopped;
      the new one = it should not be done.
- [ ] Every consumer that partitions open from closed is updated deliberately, not by grep:
      the state derivation in `kit-index.sh`, the open/closed counts, escape rate by tier, the
      tier-floor report, and `kit-plan.sh`'s ordering. Each one should be asked whether the new
      state belongs on the closed side of ITS question — they may not all answer the same way.
- [ ] A conformance case asserts the trailer validator accepts it, and asserts that a task in
      the new state is excluded from the escape-rate denominator. That second assertion is the
      one with teeth.
- [ ] `docs/` states the distinction in the words above, so the next person filing does not
      have to infer it from the vocabulary list.

## Notes

Raised 2026-08-08 from the operator's description of adopting the kit onto existing projects:
the inventory needs new, completed, not relevant, and yet-to-start, and completed includes work
finished without this kit. The "completed without the kit" half is
T-20260808-record-how-a-task-was-executed-so-kit-wo; this is the other half.

Related: T-20260808-adoption-paths-for-an-empty-folder-and-f, which is where an adopter will
be told to do the back-fill this vocabulary has to support.
