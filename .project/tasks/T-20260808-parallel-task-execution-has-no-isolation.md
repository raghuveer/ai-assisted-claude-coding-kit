---
id: T-20260808-parallel-task-execution-has-no-isolation
title: Parallel task execution has no isolation story and the obvious one is measured void
epic: validation
tier: T2
paths: docs/MEASUREMENTS.md, skills/task-context/SKILL.md
state: open
---

## Intent

Running several tasks at once is the intended way to work, and the kit has no account of what
that does to its own guarantees.

The obvious approach is already measured and it does not work. `docs/MEASUREMENTS.md` §D:
**a worktree path in a prompt does not isolate a subagent.** On the implementation-reviewer
tier test both agents found and read the live repository — one said so explicitly and reviewed
it instead — and that comparison was declared VOID. Isolation by instruction is not isolation.

Everything the kit derives assumes one writer at a time:

- `.project/events.ndjson` is append-only and marked `merge=union`, which is the right shape
  for concurrent appends — this part is probably fine and should be confirmed rather than
  assumed.
- The index is rebuilt whole from a temp file and renamed into place. Two concurrent rebuilds
  race on one fixed temp path, and the second rename wins. Both would produce a valid index;
  neither is guaranteed to be the later one.
- A reviewer reading the working tree while another task edits it reviews a state that never
  existed as a commit.
- `docs/COMPETITIVE-LANDSCAPE.md` records the current position explicitly:
  single-writer-per-repo is fine for the present scope. That was a scoping decision, and
  running tasks in parallel is the thing that ends it.

## Acceptance criteria

- [ ] State what is and is not safe to run concurrently TODAY, from evidence, not from
      reasoning about the code. Concurrent appends to the event log, concurrent index
      rebuilds, and two agents reading one working tree are three different questions.
- [ ] Give an isolation mechanism that actually isolates, or say plainly that the kit does not
      provide one and that parallelism is the operator's to arrange. A git worktree per task is
      the candidate — but it must be verified to isolate a SUBAGENT, since the one time that
      was assumed it was false.
- [ ] Whatever the answer, `docs/` and the known-limits section say it. An operator running
      tasks in parallel on the strength of silence is the failure mode.
- [ ] If a mechanism is provided, one measurement of what it costs. A worktree per task is not
      free, and the kit's argument is deliberate spending rather than accumulated convenience.

## Notes

Raised 2026-08-08: tasks are expected to run in parallel at times, with each subagent holding
context for its own task and a group of related tasks sharing context to avoid repeated review.
The sharing half is T-20260808-cluster-packs-are-generated-and-read-by-; this is the half about
whether running them at once is safe.

Deliberately scoped to establishing and documenting the truth first. The kit's stated design
priority is simplicity, and "we do not support this, here is why" is a legitimate outcome that
costs nothing to maintain.
