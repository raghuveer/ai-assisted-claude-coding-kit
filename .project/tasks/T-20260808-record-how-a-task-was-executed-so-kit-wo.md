---
id: T-20260808-record-how-a-task-was-executed-so-kit-wo
title: Record how a task was executed, so kit work and other work are distinguishable
epic: measurement
tier: T3
lang: bash
paths: tooling/schema.sql, tooling/kit-index.sh, tooling/kit-status.sh, tooling/kit-task.sh
state: open
---

## Intent

Nothing in the kit records HOW a task was done. `task` carries tier, state, epic, lang and
owner; `event` carries actor; `finding` carries agent and model. None of them answers "did
this project's own review pipeline run on this work, or did a human do it, or did a coding
agent do it without the kit."

Two things depend on that answer and neither can be given today.

**The value question.** Whether the kit pays for itself is comparative by nature — kit-run
work against work done the other ways — and a comparison needs the two populations labelled.
This is the measurement the README's central bet rests on.

**Escape rate, which is already wrong in a way nobody sees.** `kit-status.sh` computes escape
rate by tier over EVERY task, regardless of whether the review pipeline ever ran on it. On a
brownfield adoption most tasks are pre-existing or hand-done, so from the first day the
headline metric that the whole tiering design rests on is diluted — and diluted in the
direction that makes tiering look ineffective. A metric that cannot distinguish "reviewed and
nothing escaped" from "never reviewed" is the same open-circuit failure the findings loop had.

## Acceptance criteria

- [ ] A task records how it was executed, from a CLOSED vocabulary, defaulting to unknown.
      Proposed: `kit` (this project's pipeline ran), `agent` (a coding agent, no kit), `manual`
      (a human), `unknown`. Unknown must be a real value that reports as unknown, not a silent
      third meaning for one of the others.
- [ ] It is recorded the way state already is — a `Via:` trailer validated by the same hook
      that validates `Task-Id` and `Tier`, and a frontmatter key for tasks that never reach a
      commit. One vocabulary, defined in ONE place, asserted by a test. The finding vocabulary
      drifted across four locations once; this must not become the fifth.
- [ ] Every derived metric that mixes the populations either filters by it or prints the mix.
      Escape rate by tier is the one that matters; spend and the tier-floor report should be
      checked for the same shape.
- [ ] A task with no value recorded is visibly absent from a comparison rather than counted
      into one — the same rule spend already follows for unattributed rows.
- [ ] The human gate is preserved. A model may propose the value; a human confirms it, exactly
      as `kit-task.sh` requires for a task itself. A self-reported `via: kit` from the agent
      that did the work is the one value nobody should take on trust.

## Notes

Confirmed with the operator 2026-08-08 as required, not optional: model identification with a
human gate is wanted.

`unknown` is load-bearing on a brownfield adoption, where most of the backlog will be
back-filled from an existing roadmap and nobody will remember how each item was done. The
honest default is unknown, and the honest report says how much of the sample it covers.

Blocks T-20260808-trial-the-kit-on-one-unfamiliar-brownfie: a trial without this produces
data that cannot be interpreted afterwards.

Recorded T3, not the T2 it was proposed at: it touches `tooling/kit-index.sh`, which carries a
T3 floor, and the kit reported `recorded T2, floor T3` on the next reindex. Raised before the
work rather than after, which is the only order in which a tier is a control.
