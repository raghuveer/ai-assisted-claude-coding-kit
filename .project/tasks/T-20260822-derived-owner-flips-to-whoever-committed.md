---
id: T-20260822-derived-owner-flips-to-whoever-committed
title: Derived owner flips to whoever committed last so it is wrong half the time
epic: planning
tier: T2
lang: bash
paths: tooling/kit-index.sh, tooling/schema.sql, tooling/kit-status.sh
state: open
---

## Intent

`task.owner` is derived at `kit-index.sh:1270` as the actor of the **most recent activity event**,
ordered by `seq`. A task is worked by more than one contributor across many commits, so "the last
person who committed" is not a fact anyone wants, and it is presented as though it were ownership.

**Reproduced 2026-08-22**, not inferred. One task, three commits, two authors:

    alice commits Task-Status: progress   ->  owner = alice
    bob   commits Task-Status: progress   ->  owner = bob
    alice commits Task-Status: progress   ->  owner = alice

It flips on **every** commit. After a merge, `seq` is rebuild order over the combined history, so
the value depends on which side of the merge committed last — and it changes again on the next
rebuild with no edit to any task file.

**A single `owner` is the wrong shape, not a wrong query.** Measured on this repository:

    sqlite3 .project/index.db "select n, count(*) from (select task_id, count(distinct actor) n
      from event where actor<>'' and task_id<>'' group by task_id) group by n;"
    # 1 actor: 40 tasks    2 actors: 9 tasks

    git log --format='%(trailers:key=Task-Id,valueonly)' | grep -v '^$' | sort | uniq -c | sort -rn
    # up to 19 commits on one task

**Nine tasks already have two contributors and the column keeps one of them.** The other is
discarded silently — not reported as unknown, not reported at all.

## Two different questions wearing one column

- **Who has worked on this?** A SET, derived from history, factual, and it only grows. Never
  ambiguous, never flips.
- **Who is responsible for it now?** A declaration, authored by a person, which is
  `T-20260822-a-task-has-no-authored-assignee-so-a-cla`.

`owner` is derived like the first and singular like the second, so it is read as an assignment
while actually meaning "last committer". That is the worst available combination: it looks
authoritative and is not.

## Acceptance criteria

- [ ] Contribution is recorded as a **set**, not a latest-value. Whatever it is called, two
      contributors on one task must both survive a rebuild, and the value must not change when
      no task file and no commit has changed.
- [ ] The set is derived from evidence that already exists — commit authors via `Task-Id`, and
      `event.actor` — with the two sources reconciled deliberately rather than one silently
      preferred. They disagree today: 81 tasks have exactly one git author while 9 have two
      event actors, because agent-written events carry a different actor from the committer.
- [ ] `owner` is either removed or given a meaning it actually has. Removing a derived column is
      cheap; leaving one that reads as assignment and means last-committer is what this task is
      about. If it stays, `kit-status.sh` must not present it as ownership.
- [ ] A check that can fail in the shape of the defect: a fixture with two authors committing
      alternately against one task, asserting the contributor set is stable across all three
      rebuilds. That test fails on today's code — verified by the reproduction above.
- [ ] Whatever lands is reported somewhere a person reads. A contributor set nothing surfaces is
      a column, not a capability.

## Notes

Filed 2026-08-22 from a working session on ADR 0008. Not a blocker for
`T-20260808-trial-the-kit-on-one-unfamiliar-brownfie` and deliberately not added to its
`blocked_by`: the trial does not depend on it, and the backlog's habit of growing blockers faster
than it closes them is the thing to avoid here.

Related but NOT the same object: `T-20260808-parallel-task-execution-has-no-isolation` covers
whether two agents can safely run at once. This is about recording who did, after the fact.
