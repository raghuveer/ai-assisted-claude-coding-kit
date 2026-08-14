---
id: T-20260814-a-deliberate-compromise-cannot-be-record
title: A deliberate compromise cannot be recorded so the next entry rediscovers it as a defect
epic: measurement
tier: T2
lang: sql
paths: tooling/schema.sql, tooling/kit-finding.sh, tooling/kit-status.sh, tooling/kit-task.sh
state: open
---

## Intent

The kit can record a **defect** — a finding, something wrong — and a **task** — something to do.
It cannot record a **compromise knowingly carried forward**.

Verified 2026-08-15: the words "technical debt" appear nowhere in the repository — not in the
docs, not in the schema, not in the finding vocabulary
(`fail-open race false-rationale perf compliance correctness style unclassified`) — and task
state is only `open / progress / started / done`. There is no way to say *"this is known,
deliberate, and here is why"*.

A defect is an escape. **Debt is a decision.** They need different handling and the kit models
only the first.

## Why this matters on the lifecycle, not just as a category

A project built with the kit becomes a brownfield project the moment it is maintained. If the
deliberate compromises taken during the build were never written down, the next entry —
possibly a different team, possibly without this kit — has to rediscover them from the code, and
the predictable error is reading a deliberate choice as an oversight and "fixing" it.

That makes debt recording part of what the next entry inherits, not housekeeping. The entry
mechanism (`T-20260814-one-entry-mechanism-brownfield-is-the-ge`) treats an undocumented choice
as a question rather than a defect; this task is what stops those questions being generated for
choices we made ourselves and could have recorded at the time.

## What this is not

**Not a claim that AI-assisted work is debt-free, and not a claim that hand-built work is.** Debt
accrues in both. What varies is whether it is handled contextually — per project and per stack,
by the people and the tooling together. The kit's job is not to judge whether a compromise was
right. It is to make sure a compromise that was known at the time is legible afterwards.

## The change

The shape is a decision. Two candidates, and they are not exclusive:

- **A task state or class for accepted debt** — distinct from `open`, because it is not queued
  work, and distinct from `done`, because nothing was resolved. Interacts with
  `T-20260808-task-state-cannot-express-no-longer-rele`, which needs a neighbouring state for a
  different reason; settle both together or they will contradict.
- **A finding class** for a compromise accepted with reasons. Cheaper, and wrong if it makes debt
  look like an escape in escape rate — which would corrupt the one metric the kit is built
  around. If this route is taken, debt must be excluded from escape rate and the exclusion
  counted, per the rule that an exclusion nobody can see is indistinguishable from a wrong count.

**Whichever is chosen, the durable record is an ADR.** A compromise the receiving team must
understand belongs in a decision record they can read without this kit; the kit's entry points at
it rather than replacing it. Anything that exists only in `index.db` fails the maintenance case
outright.

## Acceptance criteria

- [ ] A deliberate compromise can be recorded with its reasoning, and read back later.
- [ ] It is distinguishable from a defect. It does not appear as an escape.
- [ ] If it is excluded from any metric, the exclusion is counted beside the surviving number.
- [ ] The record survives without the kit — a person with the repository and no tooling can find
      the reasoning.
- [ ] Settled together with the "no longer relevant" state rather than added beside it.
- [ ] The entry mechanism can tell a recorded compromise from an undocumented choice, and raises
      a question only for the second.

## Notes

Filed 2026-08-15 from the observation that greenfield, brownfield and modernization are three
states of one project's life rather than three kinds of project — which makes what one state
records the input the next state inherits.
