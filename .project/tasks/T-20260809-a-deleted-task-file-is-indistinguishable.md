---
id: T-20260809-a-deleted-task-file-is-indistinguishable
title: A deleted task file is indistinguishable from an id that never had one
epic: validation
tier: T3
lang: bash
paths: tooling/kit-index.sh, tooling/kit-status.sh
state: open
---

## Intent

Since `T-20260808-a-task-id-matching-no-task-file-is-count`, an id with no task file is not a
task. That is correct, and it makes two very different situations look identical:

    a typo in a pushed commit      never had a file, never was work
    a task file that was DELETED   had a file, had a tier, had a state, maybe had escapes

Both arrive at the same place — a row in `Unresolved task ids` — and the report cannot tell you
which, because the index holds no record that a file ever existed. The consequence is not
cosmetic: deleting a task file silently removes its closed history from the done count and from
the escape-rate denominator for its tier. That drop is deliberate and was decided deliberately
(the file is what makes a task), but it should be attributable.

Two review findings, from independent reviewers on the same change, are both this defect seen
from one side:

- The `done`/`abandoned` event count reported as evidence **misses** a task closed in its
  frontmatter with no `Task-Status:` trailer. Measured: a `state: done` task whose commits
  carried no trailers, deleted — the done count dropped 1 to 0 and the whole `T3` row vanished
  from escape rate by tier, with no `Unresolved task ids` section and nothing said anywhere.
- The same count **over-claims** in the other direction: an id that only ever appeared in a
  `Task-Status: done` commit and never had a file is counted as a completion whose file went
  missing.

The current wording was narrowed to say only what is recorded, and it names itself a floor. That
is honest but it is not the answer.

## The evidence that exists and is not used

`git log --diff-filter=D -- <tasks dir>` knows exactly which task files were deleted and in which
commit. The indexer already walks history for trailers; it does not look at task-file lifecycle
at all. A `deleted_at` and the deleting commit, recorded per id, would separate the two
populations completely and give the report the one actionable thing it currently lacks — not
"this id has no file" but "this file was deleted in <sha>, restore it or accept the loss".

## Why T3

`tier.rule` floors `tooling/kit-index.sh` at T3. This adds a new source of truth to the ingest
seam and changes what the backlog counts are computed over, which is the denominator of every
metric the kit produces.

## Acceptance criteria

- [ ] A deleted task file is distinguishable from an id that never had one, using recorded
      evidence rather than inference from event kinds.
- [ ] The deleting commit is reported, the way the introducing commit already is for a trailer
      id. "Restore or re-point it" is only actionable with a sha.
- [ ] The `done`/`abandoned` floor in `kit-status.sh` is replaced by, or reconciled with, the
      real signal — including the frontmatter-only closure that leaves no event at all.
- [ ] A conformance case covers a genuine deletion: file a task, close it, delete the file,
      reindex, and assert both the report and the counts say what happened.
- [ ] Decide what a RENAME is. Git reports it as a delete plus an add, and if the id inside the
      file is unchanged it is not a loss at all — an id that reappears under a new path must not
      be reported as deleted.
- [ ] Check the cost of walking task-file history on a large repository before adopting it. The
      indexer runs at the start of every session and `--if-stale` exists because that cost is
      already felt.

## Notes

Filed 2026-08-09 out of the second T3 review of
`T-20260808-a-task-id-matching-no-task-file-is-count`. The drop itself is not in question — it
was decided explicitly and is deliberate. What is missing is the ability to say which drops
happened and why, which is a different thing from whether they should.
