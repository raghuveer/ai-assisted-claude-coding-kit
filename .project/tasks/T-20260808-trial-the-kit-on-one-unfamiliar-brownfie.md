---
id: T-20260808-trial-the-kit-on-one-unfamiliar-brownfie
title: Trial the kit on one unfamiliar brownfield polyglot project
epic: validation
tier: T2
blocked_by: T-20260808-record-how-a-task-was-executed-so-kit-wo,T-20260808-a-repeatable-trial-protocol-for-running-,T-20260808-adoption-paths-for-an-empty-folder-and-f,T-20260813-nine-criticals-predate-summary-and-canno
state: open
---

> **Fourth blocker added 2026-08-14.** §0's criticals gate stopped filtering by task state, and
> nine criticals that predate the `summary` column cannot be assessed — so the gate cannot reach
> zero until `T-20260813-nine-criticals-predate-summary-and-canno` lands, and this trial cannot
> honestly start. That was true the moment the gate widened and nothing recorded it: `kit-plan`
> went on offering this task as ready work. An approach reviewer noticed the edge was missing,
> not the tooling.

## Intent

Every measurement the kit has is from ONE greenfield TypeScript project, and its own record
says so: n=1 per cell, the whole sample is the kit's worst case, and the cost figures must not
be generalised to a brownfield repository without rerunning there. Brownfield is where the
co-change graph is not inert, where the tier floors meet paths that already exist, and where
the backlog arrives from somewhere other than this kit — none of which has ever been exercised.

The subject projects available are comprehensive and complex, several polyglot, several in
Rust, and each carries a roadmap document with child-level analysis and task-description
documents. That is the input the adoption path has to consume, and it is the first real test
of whether `ingest.tasks` and the task inventory hold up against a backlog the kit did not
author.

## The constraint that shapes this task

**The subject projects are real work and must not be destabilised.** The operator's condition,
stated 2026-08-08: do not try this while the kit is in an unstable state, and do not mess up
those projects. That is not a footnote; it decides the method.

- The kit is not stable enough today. Four T3 reviews on 2026-08-08 found two critical
  fail-opens, both in code written the same day, and both in the indexer.
- The first pass must be non-destructive: read the project, produce a task inventory and a
  report, and write nothing into the project's own history until a human has read it.
- `kit-guard.sh` blocks Write outside the project root but NOT Bash writes
  (`docs/MEASUREMENTS.md` §B, "Smaller"). Until that is closed, "non-destructive" is a
  procedure the operator enforces, not a property the kit guarantees. Say which it is.

## Acceptance criteria

- [ ] Run against a COPY or a read-only clone first, never the working repository, until the
      inventory has been reviewed by a human.
- [ ] The existing roadmap and its child documents become a task inventory: new tasks, tasks
      already finished before adoption, tasks no longer relevant, tasks not yet started. Each
      carries how it was executed, or `unknown` where nobody can say.
- [ ] Report which of the brownfield degradations actually bit, with numbers: over-tiering from
      an empty edge table, whether co-change produced a usable graph or withheld itself, and
      whether the planner's ordering was usable on a backlog it did not author.
- [ ] Report what the polyglot case did to accelerator binding. This is the evidence
      T-20260731-component-model-for-polyglot-and-moderni says it needs — its field names are
      "seeded, not earned" and are to be bound to a real polyglot project rather than to the
      design note.
- [ ] Every figure carries n and the unit, per the trial protocol. No figure from this project
      is generalised to another.
- [ ] The kit's own backlog gains the defects this finds, filed as tasks, before any of them is
      fixed. Filing before fixing is what makes the escape record real.

## Notes

Blocked by three things, and the order matters. Without
T-20260808-record-how-a-task-was-executed-so-kit-wo the trial produces data that cannot be
interpreted afterwards; without T-20260808-a-repeatable-trial-protocol-for-running- it is not
comparable to the next one; without
T-20260808-adoption-paths-for-an-empty-folder-and-f there is no written path to follow and the
trial would be measuring an improvised procedure.

T-20260731-run-one-real-task-with-the-model-in-the- should also land first. The kit has never
been driven through the harness end to end — only its scripts from bash — and every defect
found on 2026-07-31 lived in a path that had never been executed.
