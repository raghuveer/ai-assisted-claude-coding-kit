---
id: T-20260822-legacy-state-spellings-in-task-files-sho
title: Legacy state spellings in task files should drain to canonical
epic: planning
tier: T1
paths: .project/tasks, tooling/kit-status.sh
state: created
---

## Intent

ADR 0008 replaced the state vocabulary and **migrated nothing**. Legacy spellings stay valid
input forever and resolve through `state_alias` when the index is built, so no file had to
change and none is broken today.

That was the right call — it removed a 130-file migration from a T3 change — but it leaves a
debt, and a debt nobody counts is a debt nobody pays. `kit-status.sh` reports it:

    - 132 task file(s) still write a legacy state name: 117x open->created, 15x done->completed
      resolved on read (ADR 0008)

**Nothing here is an error and no work is required for correctness.** This task exists so the
number is owned rather than tolerated, and so it visibly falls.

## Why it is worth draining at all

- **A file says one thing and the system means another.** A reader opening a task file sees
  `state: open` for a task the index calls `created`. That gap is exactly the confusion
  `T-20260822-derived-owner-flips-to-whoever-committed` describes for `owner`, one field over.
- **The alias table is load-bearing while any file relies on it.** It cannot be simplified, and
  its conformance assertions cannot be relaxed, until the last legacy writer is gone.
- **It is a measured example for an adopter.** A brownfield project adopting the kit will carry
  its own legacy vocabulary; how this repository drains its own is the worked example.

## What must NOT happen

- **Do not remove the aliases when the files are clean.** 127 commits carry
  `Task-Status: started|progress|done` in immutable history, and `kit-index.sh` derives state
  from them. The alias table serves git history, not just task files, and history never drains.
- **Do not rewrite git history** to canonicalise trailers. That is the trade ADR 0008 explicitly
  refused: deleting readable history to gain a tidier word.

## Acceptance criteria

- [ ] Task files carry canonical states. `open -> created`, `done -> completed`, mechanically,
      in one commit with no other change, so the diff is reviewable at a glance.
- [ ] The count in `kit-status.sh` reads zero for FILES afterwards, and the report still says
      why the alias table remains — because git history still needs it.
- [ ] A conformance assertion that a legacy spelling is STILL accepted after the drain. The
      risk in a cleanup like this is silently tightening the input contract while removing the
      last input that exercised it, which would break every adopting project's history.
- [ ] `templates/task.md` emits a canonical state, so new files never add to the count. Check
      whether `kit-task.sh` does too — it writes `state:` at creation.

## Notes

Filed 2026-08-22 on the operator's request, while ADR 0008 was being implemented: *"done is old
status know. you are keeping it for backward compatibility? if yes, do log, so we can remediate
later."* The logging landed in the same change; this is the remediation half.

**Not a blocker for `T-20260808-trial-the-kit-on-one-unfamiliar-brownfie`** and deliberately not
added to its `blocked_by`. Nothing about the trial depends on which spelling a task file uses.
