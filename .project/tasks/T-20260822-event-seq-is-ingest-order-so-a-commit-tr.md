---
id: T-20260822-event-seq-is-ingest-order-so-a-commit-tr
title: Event seq is ingest order so a commit trailer can never override an ndjson event
epic: measurement
tier: T3
lang: bash
paths: tooling/kit-index.sh, tooling/schema.sql
state: created
---

## Intent

Task state is derived by taking the most recent transition:

    UPDATE task SET state = COALESCE((
      SELECT a.canonical FROM event e JOIN state_alias a ON a.written = e.kind
       WHERE e.task_id = task.id
       ORDER BY e.seq DESC LIMIT 1), state, 'created');

`seq` is `INTEGER PRIMARY KEY AUTOINCREMENT`, assigned **as rows are inserted**, and the two
event sources are ingested in separate phases. Measured 2026-08-22:

    sqlite3 .project/index.db "select case when commit_sha is null or commit_sha=''
      then 'ndjson' else 'commit' end src, min(seq), max(seq), count(*) from event group by 1;"

    commit | 1   | 359 | 359
    ndjson | 360 | 961 | 602

**Every ndjson event outranks every commit trailer, whatever the dates say.** `ORDER BY seq DESC`
is documented as *"the order the history actually happened in"* — true within commits, false
across sources.

## Reproduced, and it broke a real workflow

Closing a task is a commit carrying `Task-Status: completed`. Three were closed on 2026-08-22.
Two took effect; the third did not, and the difference was invisible:

| task | last transition | source | closed? |
|---|---|---|---|
| `record-how-a-task-was-executed` | seq 354 `completed` | commit | yes |
| `a-repeatable-trial-protocol` | seq 356 `completed` | commit | yes |
| `a-finding-whose-subject-no-longer-exists` | seq 811 `progress` | **ndjson** | **no** |

The third commit was correct — the trailer is in history at `5c3931e`, dated later than the
`progress` event it should have superseded (`2026-08-22T06:23` against `2026-08-21T00:53`). It
was assigned seq 358 against that event's 811, purely because commits are ingested first.

**The failure is silent.** `git log` shows the closure; `kit-status.sh` shows the task open;
nothing reports a conflict. A person would conclude the commit was malformed.

## Why T3

`kit-index.sh` is under a T3 floor because a silent wrong answer there is most expensive, and
this is one. Ordering also decides `owner`, `closed_at`, and the finding/spend attribution that
binds a finding to the next transition at or after it — all of which read `seq`, and all of
which inherit this. Whether they are *also* wrong is not established here and must be checked
rather than assumed.

## Acceptance criteria

- [ ] Transition ordering reflects WHEN THINGS HAPPENED, not when they were ingested. `at` is
      the obvious key and is not sufficient alone: it is second-resolution on commit-derived
      events, so ties are real and need a stated tiebreak.
- [ ] `seq` keeps a defined meaning or loses its current one. Its comment claims to be history
      order; either that becomes true across both sources, or the claim goes and the ordering
      key changes. A comment that is true of one source and false of another is how this
      survived.
- [ ] Every consumer of `ORDER BY e.seq` is examined and each asked whether it wanted ingest
      order or event order. `owner`, `closed_at`, finding attribution and spend attribution all
      use it. They may not answer the same way — attribution binds to "the next transition at or
      after", which is a time question, while a tiebreak between two events in the same second
      may legitimately want insertion order.
- [ ] A check that can fail in the shape of the defect: a task whose latest ndjson transition is
      `progress`, then a commit carrying `Task-Status: completed`, asserting the task reads
      closed afterwards. That test fails on today's code — verified by the reproduction above.
- [ ] Existing history is not rewritten. Both sources are append-only records of what happened.

## Notes

Found 2026-08-22 while closing three tasks at the operator's request. Two closures succeeded and
one silently did not, which is what made the ordering visible at all — had all three shared a
source, this would have stayed hidden.

The affected task was closed via `kit-event.sh` as a workaround, which writes to the ndjson log
and therefore wins on seq. **That is the workaround, not the fix**: it means closure currently
depends on knowing which source a task's prior events came from, which no reader can see.

**Not a blocker for `T-20260808-trial-the-kit-on-one-unfamiliar-brownfie`** and deliberately not
added to its `blocked_by`. A trial subject starts with no ndjson history, so commit trailers are
the only source there and the ordering cannot conflict.
