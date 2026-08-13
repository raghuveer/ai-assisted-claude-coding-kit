---
id: T-20260813-nine-criticals-predate-summary-and-canno
title: Nine criticals predate summary and cannot be assessed, so the gate can never reach zero
epic: measurement
tier: T2
lang: sql
paths: .project/events.ndjson, tooling/kit-resolve.sh, tooling/kit-status.sh
state: open
---

## Intent

`finding.fixed_at` exists now, so "is there an open critical on this task" is computable and
`kit-status.sh` reports it. Running it on this repository gave **11 outstanding of 18**. Seven
were marked fixed against the commit that did each; two were re-read and confirmed genuinely
open. **The remaining nine cannot be assessed at all**, and they are the subject here.

They were recorded before the `summary` column existed. Each row carries only class, severity,
task, agent, model and a timestamp — the bare-counter shape the findings contract was written
to abolish. Nobody can say what the defect WAS, so nobody can say it was fixed:

    2026-08-08T05:35:10Z:2422e188  fail-open    kit-cfg-strips-space-and-tab-from-a-valu      security-reviewer/opus
    2026-08-08T09:35:14Z:887148f7  fail-open    an-apostrophe-in-a-tier-rule-breaks-the-     security-reviewer/opus
    2026-08-08T15:45:58Z:7f54f11b  correctness  record-how-a-task-was-executed-so-kit-wo     implementation-reviewer/sonnet
    2026-08-08T15:46:02Z:b52b8441  fail-open    record-how-a-task-was-executed-so-kit-wo     security-reviewer/opus
    2026-08-09T09:38:54Z:62e67aa9  correctness  a-task-id-matching-no-task-file-is-count     implementation-reviewer/sonnet
    2026-08-09T09:38:55Z:6fb10b86  correctness  a-task-id-matching-no-task-file-is-count     implementation-reviewer/sonnet
    2026-08-09T18:10:16Z:da4daf17  correctness  nothing-invokes-kit-finding-so-the-findi     implementation-reviewer/sonnet
    2026-08-09T18:16:06Z:e789d333  fail-open    a-task-id-matching-no-task-file-is-count     security-reviewer/opus
    2026-08-09T18:20:02Z:04160de8  fail-open    nothing-invokes-kit-finding-so-the-findi     security-reviewer/opus

Until they are resolved one way or another, four tasks stay red at the trial protocol's §0
pre-flight gate for reasons nobody can read, which is a gate that blocks without informing —
the failure one step removed from the one just fixed.

## Why this is tractable, and where it stops being tractable

The prose is not lost. Every one of those review rounds wrote its findings into the **task
file**, under a named section, and those files are committed. The rows and the prose describe
the same events; only the link between them is missing.

Measured rather than assumed — `(task_id, class)` identifies exactly one of the nine in **eight**
cases. One group does not:

    T-20260808-a-task-id-matching-no-task-file-is-count  correctness  2

So eight can in principle be matched to a named defect in a task file with a rule, and two are
mutually indistinguishable from the record alone. **That last pair is the honest limit of this
task, and the temptation to close it by picking one is the thing to refuse.** A wrong link is
worse than a missing one: it makes a specific claim that a specific defect was fixed.

## The change

The shape is a decision and belongs to whoever takes this. Two candidates, and they compose:

- **Back-fill by evidence.** For each of the eight, find the defect named in the task file's
  review section, record it — a `summary` cannot be added to an append-only event, so this
  means either a `finding-fixed` carrying the reasoning in `--note`, or a superseding event
  kind. Whatever is chosen, the link must be *stated with its evidence*, not asserted.
- **A third state for the pair.** `fixed_at IS NULL` currently means OUTSTANDING, which for
  these two is a claim the record cannot support either. An `unassessable` state would let the
  gate distinguish "open" from "unknowable".

**The second is dangerous and must be designed as such.** A state that removes a finding from
the gate is a state that makes the gate green, and the pressure to reach for it will be
strongest exactly when the gate is inconvenient. If it exists it needs to be counted and
NAMED separately in `kit-status.sh` — never folded into "none outstanding" — and it must not
be reachable for any finding recorded after the contract, where a summary is required.

## Acceptance criteria

- [ ] Each of the nine is either linked to a named defect with the evidence for the link, or
      recorded as unassessable — and which of the two is visible per finding, not aggregated.
- [ ] `kit-status.sh` reports unassessable findings as their own count. A repository with
      unassessable criticals never prints "none outstanding".
- [ ] The unassessable route is unreachable for a finding that carries a summary. A fixture
      proves the refusal, not just the acceptance.
- [ ] The two indistinguishable `correctness` findings on
      `T-20260808-a-task-id-matching-no-task-file-is-count` are NOT linked to specific defects.
      If the design lets them be, the design lets a guess through.
- [ ] TRIAL-PROTOCOL §0 states what an unassessable critical means for the gate — stop, or
      proceed with it recorded. A pre-flight box that a third state silently satisfies is the
      defect this whole chain exists to remove.

## Notes

Filed 2026-08-13 from executing the gate built by
`T-20260812-a-finding-cannot-be-marked-fixed-so-any-`. That task's acceptance criterion
predicted this: it asked for zero and said that a non-zero answer would itself be the finding.
The answer was 11, and nine of the eleven are this.

Related: the same bare-counter era is why `summary` became required
(`docs/LESSONS.md`), and why seven findings recorded on 2026-08-10 all read `fail-open|major|bash`
and could not be told apart.
