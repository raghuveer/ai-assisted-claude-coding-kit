---
id: T-20260801-validate-a-task-s-recorded-tier-against-
title: Validate a task's recorded tier against its own tier rule floors
epic: tiering
tier: T2
state: open
---

## Intent

Nothing checks that a task's `tier:` frontmatter is at least the floor its own
`tier.rule:` globs imply. Under-tiering is therefore silent, and it is the dangerous
direction: a task recorded T1 that should be T2 gets one fewer reviewer and nobody knows.

Measured on a real project (2026-08-01). Three tasks were re-classified by two independent
classifiers each, cold, with the `tier-classify` rules:

| task | recorded | run A | run B |
|---|---|---|---|
| cache invalidation epoch | T2 | T3 | T3 |
| liveness/readiness split  | T1 | T2 | T2 |
| nonce store               | T3 | T3 | T3 |

The classifier is stable -- 3/3 pairwise agreement. The recorded tiers are not: two of
three were too low, both because the backlog had been tiered from the source findings'
SEVERITY rather than from blast radius, reversibility and ambiguity, and never checked
against the floors.

The result is stronger than a blind test would give: the classifiers could see the
recorded tier in the frontmatter and overrode it anyway ("that predates applying the
floor"). Anchoring biased against the finding and it held.

Escape rate per tier is the kit's central measurement and it is computed from these
values. Wrong tiers do not make it noisy, they make it wrong in a direction that looks
calibrated.

## Acceptance criteria

- [x] a task whose recorded tier is below a matching `tier.rule` floor is reported
- [x] the check runs where it will be seen -- indexing or status, not a script someone
      remembers
- [x] floors raise and never lower, so a task tiered ABOVE its floor is not flagged
- [x] the report distinguishes "below floor" from "no tier recorded at all"

## Notes

"Cheap: floors and task tiers are both already in the index, this is a query" was half right.
Task tiers are in the index; the FLOOR is not, because a floor needs the paths a task will
change and the index only knows the paths it has already changed. 7 of 8 open tasks in this
repository had no touches edges, so an edge-only floor would have passed every one of them
silently -- and an unstarted task is exactly when the tier still matters, since it gates the
review that happens during the work.

So floors come from two sources. An optional `paths:` frontmatter glob list, which works
before any commit, and touches edges, which catch a task whose declared paths were wrong or
absent once work begins. Both raise, neither lowers, and MAX takes the higher.

Three states, not two: below floor, at-or-above, and no basis to judge. The third is
reported as a count rather than passed over -- silence on an unjudgeable task is how
under-tiering stays invisible, which is the same failure the escape rate had while the
findings loop was open.

Does not address tiering by severity at import time, which is the upstream cause. Worth a
separate note wherever tasks are bulk-imported from a findings register.
