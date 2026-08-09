---
id: T-20260808-a-task-id-matching-no-task-file-is-count
title: A Task-Id matching no task file is counted as an open task forever
epic: validation
tier: T3
lang: bash
paths: tooling/kit-index.sh, tooling/kit-status.sh, tooling/kit-plan.sh, tooling/kit-trailers.sh
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

- [x] A task id with no backing file is not counted as an open task. **Decided: dropped, not
      classed.** The node survives so the edges pointing at the id still resolve; the task row
      is never created. A separate class would have meant partitioning every derived metric on
      a flag, which is more surface than not inventing the row — and the row is the thing that
      was wrong, not its label.
- [x] It is REPORTED, by id and by the commit that introduced it. New **Unresolved task ids**
      section, immediately after the backlog counts it used to inflate.
- [x] Check every derived metric for the same shape, not just the Open list. Done below; one of
      them was wrong in a new way and needed a fix of its own.
- [x] A conformance case covers it.
- [x] Decide whether an id that later GAINS a file should be reconciled automatically. **Yes,
      and it already is** — by the ordering rather than by a reconciliation pass.

## What the sweep found

The Open list, the escape rate, the provenance breakdown and the tier-floor report all read the
`task` table, so not inventing the row fixed all four at once. Measured on this repository:

    Open list          T-20260801-cross-project-accelerator-aggregation gone
    escape rate T1     0 / 13 all  ->  0 / 12 all
    Other provenance   unknown 47 task(s)  ->  46
    tier floors        18 of 28 open  ->  17 of 27

`kit-plan.sh` needed no change, and that is a checked fact rather than an assumption: its task
population comes from `task` at three separate points, and every membership test in it is a
positive `IN`, so a phantom is simply never planned.

**Spend attribution was the exception, and dropping the row would have made it worse.** It binds
spend to the next task-status transition by reading `event.task_id` DIRECTLY — the one derivation
in the kit that does not go through `task`. Transitions survive for an id with no file, so spend
would have bound to an id with no task row, and then every spend figure in the report (all of
which join `task`) would have dropped it, while the unattributed warning counts only a NULL
`task_id` and would never have mentioned it. Attributed to nothing, reported as nothing, missing
from the totals: a third category, strictly worse than the unattributed case the code's own
comment argues must be reported. Fixed by binding only to a transition whose task exists, which
leaves it NULL and lets the existing warning do its job.

## The T3 review, and the two things the first pass got wrong

Both reviewers returned REJECT, independently, and the blind second reader found a regression
the first rated minor. Ten findings recorded. Two were defects in this change rather than
observations about it, and both were reproduced before being accepted.

**`fail-open`, both reviewers — the spend guard did not leave spend NULL, it slid it onto an
unrelated task.** `AND EXISTS (...)` in the WHERE clause does not stop the search; it makes
`LIMIT 1` skip the phantom's transition and bind to the next REAL one, however far away and
however unrelated. Measured: spend, then a `T-ghost` transition, then a later `T-real`
transition, and the cost landed on `T-real`, at `T-real`'s tier, with zero unattributed and no
warning anywhere. That is not the third category the guard was added to prevent — it is a fourth
and worse one, attributed to the WRONG thing and reading as right, where the previous behaviour
at least kept it on the id the trailer named. The existence test now sits INSIDE the selected
row: nearest transition first, on time alone, then required to be real, so a phantom neighbour
yields NULL. **And the first version of this task's test could not have caught it** — its ghost
commit was the last in the fixture, the one arrangement where the claimed NULL happens anyway.
The test asserted the comment, not the behaviour.

**`correctness`, critical — an unfiled `blocked_by` target stopped blocking, silently.** Not
inventing the row removed the thing `kit-plan.sh` was accidentally relying on: the edge survives,
its target has no task row, and the planner's filter drops the CONSTRAINT rather than the task.
Measured against the parent commit with the same fixture: a task blocked by an unfiled id moved
from layer 1 to layer 0 — first in the plan, as though nothing were in its way — silently
violating `TOPOLOGY BEATS PRIORITY`, which is that file's own first stated rule. The commit
message claimed kit-plan was unaffected and "checked rather than assumed"; the check was of the
wrong thing. It is true that a phantom is never planned. It is false that nothing changed, and
the edge was never looked at.

A `done` blocker still stops blocking — that edge is dropped on purpose. A blocker with no task
row is not satisfied, it is unknown, so its dependent is now withheld along with anything behind
it, and reported, on the same grounds the file already withholds a cycle rather than sequencing
around it.

**Also fixed from the review:** ids are rendered inside a code span with backticks stripped,
because an id beginning `<!--` sorts first under BINARY collation and commented out every row
below it and the count — in a section whose entire purpose is history that never passed the
hooks that would have caught it. The section now shows each id's ORIGIN as evidence rather than
guessing a cause: a trailer id carries its commit and its event kinds, a `blocked_by` id names
the file that declared it, where "correct the trailer" was advice about a trailer that does not
exist. Two comments this change falsified were corrected.

## A closed task whose file is deleted

Decided: **the drop stands, and is made visible.** The row goes for the same reason as any
other id with no file — the file is what makes a task, and this repository derives everything
from text — so deleting one is a statement, not an accident. What it must not be is silent,
because its closed history leaves the Closed count and the escape-rate denominator with it.
The `seen as:` evidence names it, and a line below the list says how many completed before
their file went missing and what that removed from the counts above.

## Reconciliation, and why there is nothing to run

Section 2 emits the task row from the file with its frontmatter; the derivation in section 4 runs
afterwards and only ever adds what is missing. So an id that gains a file later becomes a real
task on the next index, with the waiting spend attaching to it — no migration, no reconciliation
pass, no state to repair. This is a property of the ordering, so the conformance case asserts it
rather than the comment claiming it.

## Notes

Found while evaluating backlog scope on 2026-08-08. The kit documents the papercut that
produced it — `kit-task.sh` derives an id from the title at creation and offers no way to
correct it afterwards, and once a `Task-Id` reaches a pushed commit the id is permanent — but
documents it as a cost of the design rather than as something the indexer should handle.

The task this one shadows, `T-20260731-cross-project-accelerator-aggregation`, is itself still
open, so the backlog currently shows the same work twice at two different tiers.
