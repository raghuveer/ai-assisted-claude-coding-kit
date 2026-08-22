---
id: T-20260813-nine-criticals-predate-summary-and-canno
title: Nine criticals predate summary and cannot be assessed, so the gate can never reach zero
epic: measurement
tier: T2
lang: sql
paths: .project/events.ndjson, tooling/kit-resolve.sh, tooling/kit-status.sh
state: completed
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

Until they are resolved one way or another, **three** tasks stay red at the trial protocol's §0
pre-flight gate for reasons nobody can read, which is a gate that blocks without informing —
the failure one step removed from the one just fixed.

> This said "four" when filed. The nine findings span five tasks, but two of those are `done`,
> and at the time the gate excluded anything not at `progress` — so only three blocked it. An
> approach reviewer caught the arithmetic a day later. The gate no longer filters by task state
> (closing a task was clearing it), so all five now count, which makes the original "four"
> wrong in both directions at once.

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
- [x] `kit-status.sh` reports unassessable findings as their own count. A repository with
      unassessable criticals never prints "none outstanding".
- [x] The unassessable route is unreachable for a finding that carries a summary. A fixture
      proves the refusal, not just the acceptance.
- [ ] The two indistinguishable `correctness` findings on
      `T-20260808-a-task-id-matching-no-task-file-is-count` are NOT linked to specific defects.
      If the design lets them be, the design lets a guess through.
- [x] TRIAL-PROTOCOL §0 states what an unassessable critical means for the gate — stop, or
      proceed with it recorded. A pre-flight box that a third state silently satisfies is the
      defect this whole chain exists to remove.

      **Done 2026-08-17.** §0 gains a box that calls `kit-preflight.sh --unassessable`, a new
      flag. The answer is **proceed, with the count recorded** — treating it as a stop would
      restore the permanently unsatisfiable gate the unassessable route exists to remove, since
      these nine can never be judged. Three conditions that ARE stops are named as judgement:
      the blind spot sitting on a task the trial will exercise, the count having gone UP since
      the last trial (a tenth means something is producing unjudgeable findings *now*, which is
      worse than the nine), and any mark carrying no reason. The §7 template and §6 now carry the
      count **and the previous trial's**, because stop 2 is unevaluable from one number.

      Verified rather than asserted: on a fixture, marking the only summary-less critical
      unassessable flips `--criticals` from exit 1 to exit 0 — the box passes — while
      `--unassessable` reports the id, its task and its reason. That flip is the defect, now
      visible. A conformance step asserts both halves and that `--unassessable` itself exits 0,
      since a non-zero would rebuild the gate this removes.

      **Still not done on this task:** the nine marks (operator), and the judgement about the two
      indistinguishable `correctness` findings (operator). This criterion was the only one of the
      five that was mine.

## Notes

Filed 2026-08-13 from executing the gate built by
`T-20260812-a-finding-cannot-be-marked-fixed-so-any-`. That task's acceptance criterion
predicted this: it asked for zero and said that a non-zero answer would itself be the finding.
The answer was 11, and nine of the eleven are this.

Related: the same bare-counter era is why `summary` became required
(`docs/LESSONS.md`), and why seven findings recorded on 2026-08-10 all read `fail-open|major|bash`
and could not be told apart.

## Chosen approach, 2026-08-16 — operator selected "make the gate count what it can act on"

Recorded before implementation, because the shape of this fix is the whole argument and a later
reader must be able to see what was rejected as well as what was built.

**The population, measured rather than assumed.** Cross-tab of the 17 unfixed criticals:

| | on a `done` task | on a `progress` task |
|---|---|---|
| has `summary` (assessable) | 6 | 2 |
| no `summary` (unassessable) | 2 | 7 |

So **only 9 are the policy question**. The other 8 are readable and decidable by ordinary review —
a backlog problem, not a gate problem, and they need no mechanism at all. Six of those sit on
`T-20260814-one-entry-mechanism-brownfield-is-the-ge`, which is closed.

**REJECTED — mark them `--fixed` with a note.** Clears the gate in one command and writes a false
statement into an append-only committed log. `--fixed` means *fixed*; using it for *unassessable*
is precisely the laundering this gate exists to prevent, and `kit-index.sh` would then report them
as addressed forever.

**REJECTED — a standing query exclusion** (`AND summary IS NOT NULL`). This was the first shape
proposed and it is wrong: it silently exempts **every future** critical that lacks a summary, so a
reviewer omitting the field would slip past the gate. It converts a bounded historical problem
into an unbounded hole, which is a strictly worse trade than the thing it fixes.

**CHOSEN — an explicit per-finding disposition.** Each of the nine is named individually and
deliberately, with a reason, by the operator. The gate then excludes only what was marked. This
keeps the exclusion bounded, auditable, and readable as what it is: a blind spot, not a clean bill.

Design, mirroring the `finding-fixed` path exactly rather than inventing a parallel one:

- `kit_findings.py` gains an `unassessable_event()` serialiser emitting
  `{"kind":"finding-unassessable","at":…,"finding":…,"reason":…,"actor":…}`. `--reason` is
  REQUIRED and non-empty — a disposition without a stated reason is the thing being avoided.
- `kit-resolve.sh --unassessable ID --reason TEXT`, alongside `--fixed`. Operator-invoked.
- `schema.sql` gains `unassessable_at` and `unassessable_reason`, derived from those events every
  rebuild, never written directly — same rule as `fixed_at`.
- `kit-preflight.sh --criticals` excludes `unassessable_at IS NOT NULL`. **The predicate has ONE
  home and the exclusion goes there**, per the comment already on it.
- `kit-status.sh` reports the count as a NAMED, PERMANENT blind spot — "N unassessable (predate
  the summary field)" — never folded into zero.
- `kit-event.sh` gains `finding-unassessable` to its refusal list, because it becomes a kind the
  indexer acts on. The check added on 2026-08-16 derives that list from the indexer, so omitting
  this turns conformance red rather than reopening the forge.

**Orthogonality, stated because two columns have already been conflated here.** `vindicated`
answers *was it real*; `fixed_at` answers *was it addressed*; `unassessable_at` answers *can it be
judged at all*. Three facts, three columns. Reusing `vindicated=0` would claim these nine were
refuted, which nobody established — the same error as filing not-relevant work as `abandoned`.

**What the agent may NOT do.** Build the mechanism, yes. **Apply the nine marks, no** — that is an
operator action for the same reason `--fixed` is, and a session clearing the gate that gates its
own work is the one certification that carries no information.

## Status 2026-08-16 — mechanism built, three criteria still open

**AC2 and AC3 are met.** `kit-status.sh` reports unassessable findings as their own count and a
repository holding them never prints a bare "none outstanding" — the notice sits OUTSIDE the
not-empty branch precisely so it appears when the list is empty, which is when it matters most.
AC3 was **not** met by the first implementation and is now: `kit-resolve.sh` refuses
`--unassessable` on any finding that carries a summary, and the conformance step proves the
REFUSAL as well as the acceptance. Without that the route was a general-purpose way to clear the
criticals gate rather than a narrow hatch for rows whose text does not survive — the laundering
this task exists to prevent, rebuilt by its own fix. Mutation-proven: making the refusal
unreachable turns the step red.

**AC1, AC4 and AC5 remain open, and two of them are the operator's.**

- **AC1** needs the nine marks applied, each visibly linked-or-unassessable per finding. The
  mechanism exists; recording them is an operator action for the same reason `--fixed` is.
- **AC4** — that the two indistinguishable `correctness` findings on
  `T-20260808-a-task-id-matching-no-task-file-is-count` are NOT linked to specific defects — is a
  judgement about which of two identical rows is which, and the design must keep refusing to
  guess. Nothing to build; something to check once the marks are applied.
- **AC5** — `TRIAL-PROTOCOL` §0 stating what an unassessable critical means for the gate — is
  mine and is not done. Note §0 currently calls `kit-preflight.sh --criticals` rather than
  restating the rule, which is why it did not go stale when the third state was added; the box
  still needs to say what the third state means for a trial.
