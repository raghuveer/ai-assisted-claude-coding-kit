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

## The second T3 review

Both reviewers ran again on the fixed change, blind to each other. Security REJECTED,
implementation APPROVED — not a contradiction: the approving reviewer's findings were all minor,
while the rejecting one built fixtures the other did not and reproduced two majors in them.
Fourteen more findings, twenty-four on this task in total. Everything below was reproduced.

**The withhold blast radius, measured at last.** 22 open tasks, one mistyped `blocked_by`, 20
tasks behind it: **one task planned, twenty-one withheld**, reported by a single stderr line
naming the root, with no count and exit 0. Both reviewers independently said keep withholding —
sequencing around an unknown blocker asserts something unevidenced — and both said the defect is
visibility, not policy. So the magnitude is now reported and persisted to the index, because
stderr is not a record: this repository's own fixtures run `kit-plan.sh` with stderr redirected
away, which is exactly how an orchestrator would run it.

**The `GONE` line was wrong in both directions**, and neither reviewer saw both. It missed a task
closed in frontmatter with no `Task-Status:` trailer — measured, a `done` T3 task deleted, and
the done count and its whole escape-rate row vanished in silence — while claiming "finished
before the file went missing" about ids that never had a file. It now counts recorded evidence,
calls itself a floor, and asserts no narrative. Doing this properly needs git history in the
indexer and is `T-20260809-a-deleted-task-file-is-indistinguishable`.

**Spend could still be attributed to nothing and reported as nothing** — the reader side of the
defect fixed on the writer side last round. Every spend figure joins `task`; the unattributed
warning counted only NULL. A row naming an unfiled id fell between them.

**A NULL `node.id` emptied the new section** — the same SQLite deviation this file hardened the
residue query against, not applied to the query added beside it in the same commit.

**Only one of three fields was escaped.** The id was hardened; the event kinds and the declaring
path were not, and `Task-Status:` is checked against no vocabulary where `Via:` is. The reviewer
was careful here: it could not reproduce actual silencing, since the id sits first on the line
and CommonMark needs a closing `-->`, and declined to call it live. A latent trap that becomes a
hole the moment someone reorders the fields — which is an accident of layout, not a property of
the fix.

**And the line presented as the gate was dead code.** The guarded `INSERT OR IGNORE INTO task …
path IS NOT NULL` could never add a row, because section 2 has already inserted one per file.
Verified by indexing with and without it: identical task rows. Deleted, and the comment now says
where the rule actually lives — a phantom is stopped by an ABSENCE, which has to be stated or the
next reader restores the invention.

Also fixed: `unblocks[]` counted withheld descendants into a surviving task's priority;
`GROUP_CONCAT` had no ordering; and comments in two files still claimed the residue branch could
not fire "because kit-index materialises a task row" — which this very change made false.

**Twelve mutations across three rounds**, each red only in the steps asserting it. Two needed
re-running: one missed its pattern, and one targeted a line since rewritten, so its guard asked
"is the old text still present?", concluded a mutation had applied when the pattern had simply
never matched, and ran an unmutated suite to a green 34/0. A mutation that does not mutate is
indistinguishable from a passing control in a summary; both guards now assert the mutated text is
present and count occurrences before and after.

Persisting the withheld count on every run, including the clean one, moved the fixture index
fingerprint. Deterministic, so nothing failed — but the fingerprint is the drift signal, and a
control that emits false drift on every run teaches people to ignore it. It now writes only when
tasks are actually withheld, and the fingerprint is back to `d923228d…`.

## The third T3 review

REJECT again, seven findings, thirty-one on this task. The pattern held for the third time: it
found defects inside the fixes for the previous round, and two of them were claims this task file
and its commits had already reported as done.

**A regression introduced by the round-2 fix.** The withheld read-back became the last command in
`kit-plan.sh`, and a `case` matching nothing returns 0 — so the display query's exit status was
discarded. A failing plan query, realistically a locked database while `kit-index.sh` swaps the
file at session start, returned empty stdout and success: indistinguishable from "no work left".
Reproduced with a `sqlite3` shim; the fixed script exits 1 where `039537c` exits 0. The
conformance control for that status only ever exercised the success path, so it went quiet at the
same moment the defect appeared and is now backed by a shim-injected failing query.

**"EVERY field is stripped and wrapped" was false — the line has FOUR fields.** The commit sha
went out raw. A backtick and a newline injected into `commit_sha` fabricated a bullet and moved
the rendered count with it, because the count is `grep -c .` over lines rather than rows. Three
fields hardened, a comment claiming all of them, and the fourth exposed — the same shape as the
defect the round-2 fix existed to close.

**The withhold-magnitude fix was illusory.** The count was persisted to the index and read back
out through `kit_warn`, which is `printf >&2` — the very channel the finding was about. The data
moved; the channel did not. It now prints to stdout beside the plan it qualifies, `#`-prefixed so
a session parsing those lines is not broken by it.

**And a false statement in the rendered report.** "Excluded from every figure above" was untrue:
`By scope` and the per-model figures read `FROM spend` with no join, so they count unattributed
spend and always did — measured at 1.4M of 1.5M reported. That is correct for what those figures
measure, which is transcripts rather than tasks. The number was never wrong; the sentence about
it was, and it appeared in the comment, the commit message and this file. Now the report names
which figures include the cost and which do not.

Also fixed: the `meta` writes discarded their status, so a failed DELETE on a locked database
would leave a stale withheld count reading as current — the exact failure the paragraph above it
argued against; and "this number is a floor" had no stated referent, which left the deletion
reading it had just been rewritten to avoid.

Audited and found sound, independently: `UNATT` is correct and cannot double-count, `unblocks[]`
after withholding cannot under-count a placed task, the deleted INSERT really was dead (49
identical task rows, re-derived), and the event-kind and path escaping hold.

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
