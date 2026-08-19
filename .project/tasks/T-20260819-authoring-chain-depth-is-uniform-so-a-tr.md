---
id: T-20260819-authoring-chain-depth-is-uniform-so-a-tr
title: Authoring chain depth is uniform so a trivial change pays for a full research pass
epic: agent-contracts
tier: T2
lang: markdown
paths: agents/researcher.md, agents/approach-reviewer.md, agents/adr-scribe.md, skills/verify-ladder/SKILL.md
state: open
---

## Intent

The agreed authoring chain is
**research → ADR → approach-review → breakdown (human-confirmed) → sequence-review → implement**
(`docs/design-input/2026-08-18-authoring-chain-and-review-economics.md` §1), re-entered on a new
feature, a feature change, or an unplanned deviation found during implementation.

**Nothing scales it.** `verify-ladder` already scales *verification* by tier — rungs 1-2 at T0/T1,
3-4 at T2, 5 at T3 — on the principle that depth should follow risk. The authoring half has no
equivalent, so a one-line fix and a new subsystem are entitled to the same research pass, ADR and
design review.

**That is the same waste the sequencing work exists to prevent, arriving from the other side.**
Thrash spends tokens re-doing work in the wrong order; uniform ceremony spends them producing
artefacts nobody needed. In unattended operation both compound silently.

`agents/researcher.md` already gestures at this — *"Do NOT use for bug fixes, CRUD, or changes with
one obvious approach"* — but it is a judgement in prose addressed to whoever invokes it, and the
tier is already computed sitting right there unused.

## Acceptance criteria

- [ ] Chain depth is a function of tier, declared where `ladder.*` already lives, so the two
      halves of the kit's economics are configured in one shape rather than one being mechanical
      and one being prose.
- [ ] **A skipped stage is DECLARED, never silently absent** — the rule `verify-ladder` already
      follows for an unavailable rung, which raises the tier rather than lowering the bar. "No ADR
      was written for this" must be readable afterwards as a decision, not inferred from absence.
- [ ] Cost is stated rather than assumed. The reviewer half is measured (134,882 / 140,718 /
      106,119 tokens for one T3 change on 2026-08-17); **the authoring half is unpriced**, and a
      policy that trades depth for tokens without knowing either number is a guess. Measure a
      researcher and an adr-scribe run before setting thresholds.
- [ ] The escape hatch works in the expensive direction: a task may be *raised* into a deeper
      chain, and doing so is recorded. Tier floors already raise and never lower; this must not
      become the one control that only ever reduces.
- [ ] A check that can fail, covering both directions — a T0 change must not invoke the full
      chain, and a T3 change must not be able to skip it.

## Notes

Filed 2026-08-19 from an audit of the design input against the backlog. Recorded in that document's
§8 as *"not that chain depth should be uniform — tying it to tier, as verify-ladder already ties
verification depth, is the obvious economy and is untested."*

**Depends on nothing, but is worth little before the chain runs for real.** Nothing has yet
exercised the full authoring chain end to end on a genuine feature, so the thresholds would be set
against zero observations. Sequence it after the first real run rather than before, or it becomes
another seeded value the kit's own doctrine says must be earned.
