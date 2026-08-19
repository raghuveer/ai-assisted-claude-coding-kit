---
id: T-20260819-goals-are-the-milestone-mechanism-and-on
title: Goals are the milestone mechanism and only default has ever existed
epic: planning
tier: T2
lang: bash
paths: tooling/kit-plan.sh, tooling/kit-status.sh, skills/task-context/SKILL.md
state: open
---

## Intent

`goal` plus `plan_item.goal_id` **is** a milestone: a named subset of the backlog with its own
ordering and its own packs. Verified 2026-08-19 — the `goal` table holds exactly one row,
`default`, and it always has. The mechanism has never been used for the thing it is.

This matters now because ADR 0004 made it viable on 2026-08-17. Before that a rebuild deleted the
plan, so a second goal would have survived exactly as badly as the first. Durable, committed goals
are the precondition, and it has only just been met.

**MVP is one OPTIONAL use of this, not a stage every project passes through** (operator, 2026-08-18).
Some projects go straight to v1.0; a brownfield adoption may have no MVP; a modernization runs in
phases that are not "MVP" in any sense. The mechanism must carry any of those without privileging
one, and nothing in the kit should require a milestone to be named "MVP" to behave correctly.

**The greenfield→brownfield transition is computable and name-independent.** Greenfield has no
`touches` edges, an empty co-change graph, and no findings; when those fill, the project is
brownfield whatever the milestone is called.
`T-20260814-one-entry-mechanism-brownfield-is-the-ge` already argues brownfield is the general case
and the other two are its starting conditions — this is that same argument over time rather than
at adoption, and the kit currently decides entry mode once and never revisits it.

## Acceptance criteria

- [ ] A second goal can be planned, packed and worked without the first being disturbed —
      demonstrated, not asserted. Two goals sharing a task is the interesting case, and what
      happens then must be decided rather than discovered.
- [ ] `kit-status.sh` reports per goal. Today every figure is implicitly `default`, so a second
      goal would silently merge into aggregate counts and no one would see it.
- [ ] The **project's entry mode is derived, not fixed at adoption** — the predicate above run on
      current state, so a project that has become brownfield is reported as brownfield.
- [ ] Nothing requires a milestone to be called MVP, v1, or anything else. A naming convention
      that changes behaviour is a second vocabulary, and this repository has paid for those.
- [ ] `skills/task-context` step 4 resolves the pack for the task's **own** goal. It reads
      `goal_id` from `plan_item` already; confirm that survives a second goal rather than assuming
      it, since every existing execution has had exactly one to choose from.
- [ ] A check that can fail, with two goals in the fixture — every existing conformance step
      builds a single-goal fixture, so this whole surface is currently unexercised.

## Notes

Filed 2026-08-19 from an audit of `docs/design-input/2026-08-18-authoring-chain-and-review-economics.md`
§5 against the backlog, which found the section had no task.

**Unblocked, but low value until something needs two milestones.** The honest sequencing is that
this waits for a real project with phases — most likely the brownfield trial or a modernization
subject — rather than being built speculatively against an imagined second goal. Building it now
would mean inventing the two-goal semantics with no case to check them against.
