---
id: T-20260808-a-task-id-matching-no-task-file-is-count
title: A Task-Id matching no task file is counted as an open task forever
epic: validation
tier: T3
lang: bash
paths: tooling/kit-index.sh, tooling/kit-status.sh
state: open
---

## Intent

This repository carries a phantom task, and it is in every count the kit produces.

    id      T-20260801-cross-project-accelerator-aggregation
    file    none
    origin  aa377ed "docs: record the library catalogue proposal..."
    real    T-20260731-cross-project-accelerator-aggregation   (the date is a typo)

`kit-index.sh` creates a `task` row for any `Task-Id` it sees in a trailer, whether or not a
file backs it. So a one-character typo in a pushed commit became a permanent open T1 task with
no title and no epic. It appears in the Open list, in the backlog count, and in the escape-rate
denominator for its tier.

The controls that exist all act too early. `kit-trailers.sh` warns "matches no task" at commit
time; `pre-push` blocks it before it is shared. Both work. Neither helps for history that is
already pushed — and `INSTALL.md` already tells adopters this repository carries one from
before the hook existed. What is missing is the handling for the case that got through.

## Why T3

`tier.rule` floors `tooling/kit-index.sh` at T3, and the reason the profile gives applies
exactly: the indexer is where a silent wrong answer is most expensive. This changes what
counts as a task, which is the denominator of every derived metric.

## Acceptance criteria

- [ ] A task id with no backing file is not counted as an open task. Whether it is dropped or
      held in a separate class is the decision to make; what it must not do is sit in the
      backlog looking like work.
- [ ] It is REPORTED, by id and by the commit that introduced it. This is the same rule the kit
      already applies to unattributed spend, refused tier.rules and unusable paths: the thing
      that could not be resolved is named rather than silently discarded. An adopter inheriting
      a brownfield history may have many, and they are evidence about trailer discipline.
- [ ] Check every derived metric for the same shape, not just the Open list: escape rate by
      tier, the tier-floor report, `kit-plan.sh` ordering, and the spend attribution heuristic
      that binds spend to the next task-status transition.
- [ ] A conformance case covers it — a commit whose Task-Id matches no file, asserting the
      task does not appear as open and that the report names it.
- [ ] Decide whether an id that later GAINS a file should be reconciled automatically. A task
      filed after the commit that referenced it is a normal sequence, not an error.

## Notes

Found while evaluating backlog scope on 2026-08-08. The kit documents the papercut that
produced it — `kit-task.sh` derives an id from the title at creation and offers no way to
correct it afterwards, and once a `Task-Id` reaches a pushed commit the id is permanent — but
documents it as a cost of the design rather than as something the indexer should handle.

The task this one shadows, `T-20260731-cross-project-accelerator-aggregation`, is itself still
open, so the backlog currently shows the same work twice at two different tiers.
