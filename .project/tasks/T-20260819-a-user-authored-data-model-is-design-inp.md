---
id: T-20260819-a-user-authored-data-model-is-design-inp
title: A user authored data model is design input nothing requires reviewing or detects changing
epic: agent-contracts
tier: T2
lang: markdown
paths: agents/approach-reviewer.md, agents/researcher.md, templates/project-profile.md
state: open
---

## Intent

`paths.design_input` exists (ADR 0001) and a user-authored data model has a home there. Two things
are missing, and both are silent.

**Nothing requires it to be reviewed.** `approach-reviewer` reviews a design-input document when it
is invoked on one. A data model the architect wrote and dropped in the directory is design input by
any reasonable reading, and no gate notices whether it was ever read.

**Nothing detects that it changed.** A data model is not written once — it moves as the design
settles. A design reviewed against version 1 and implemented against version 3 is the failure the
whole authoring chain exists to prevent, and it would leave no trace.

**Operator input, 2026-08-18:** user-authored data models are not expected on every greenfield, are
likely on brownfield, and are near-certain on legacy modernization — where the data model *is* the
migration problem. That distribution is the argument for handling it: the projects where it matters
most are the ones the kit is least proven on.

## Acceptance criteria

- [ ] A design-input artefact the operator authored is **distinguishable from one an agent
      produced**. They carry different authority — the kit's own trust table classes agent output
      as untrusted and the operator as the only party that may close a task — and today both are
      just files in a directory.
- [ ] Whether it has been reviewed is **recorded**, so "no review" is distinguishable from "reviewed
      and found sound". That is the same distinction the assurance-cadence task requires of its
      layers and the empty-review rule requires of a reviewer, and it fails the same way when
      absent.
- [ ] A change to it after review is **detected and reported**. The shape already exists in
      `kit_plan_digest`: record what a claim was computed from, recompute, report the delta. Read
      that before inventing a second mechanism for the same job.
- [ ] Staleness is a **notice, not a block**. ADR 0004 settled the same trade for plans — a
      carried-forward artefact that cannot say it is stale is worse than one that visibly
      vanished, and a hard block on a moving design would simply be routed around.
- [ ] A check that can fail, covering the quiet direction: an unchanged model must not report
      drift, or the notice becomes the always-on warning people learn to skip.

## Notes

Filed 2026-08-19 from an audit of
`docs/design-input/2026-08-18-authoring-chain-and-review-economics.md` §6, which named the gap in
prose and had no task.

**Scope: the kit does not validate the model.** Whether a schema is correct is the architect's
judgement and a reviewer's, not a script's. What is in scope is that the artefact is identified,
its review state is recorded, and its drift is visible — the kit's habitual posture of stating
precisely how little it covers rather than implying more.

Related: `T-20260731-component-model-for-polyglot-and-moderni` carries the modernization case and
the per-component disposition, of which data migration is the consequence half. A data model that
changed after a disposition was agreed is exactly the case that task's "mutual agreement with the
client team" depends on noticing.
