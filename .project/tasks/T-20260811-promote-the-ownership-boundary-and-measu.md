---
id: T-20260811-promote-the-ownership-boundary-and-measu
title: Promote the ownership boundary and measurement guards
epic: measurement
tier: T1
paths: README.md, templates/project-profile.md, docs
state: open
---

## Intent

Two pieces of the recommendations register are **policy, not plan**, and policy left in a
document that is about to be demoted will be lost:

1. **The ownership boundary table** — what belongs to the harness and whatever endpoint it is
   configured against (model hosting, model identity, allowed-lists, failover, cost telemetry)
   versus what belongs to the kit (capability needed, which tier a task deserves, agent prompts,
   pipeline shape) versus the project repo (task state, decisions, status). This is the line the
   kit crosses most easily by accident.
2. **Two guard conditions on measurement**: no efficiency gain is accepted if escaped defects
   rise; any agent producing zero findings across a full retro period is a candidate for
   removal, not for a better prompt.

Neither is written down anywhere the kit enforces or even states.

## The change

Move the boundary table into the README or `docs/`, and the two guards into
`templates/project-profile.md` where they are inherited by every adopting project.

A one-line framing worth adopting alongside it: **performance is a function of intelligence and
context — the kit supplies the context, the harness supplies access to the intelligence.** It
explains the scope boundary in a sentence, which the README currently takes several paragraphs
to do less clearly.

## Acceptance criteria

- [ ] The boundary table lives in the kit, not in a workspace document, and names the three
      owners.
- [ ] The two guard conditions appear in `templates/project-profile.md` so an adopting project
      inherits them.
- [ ] The README states the boundary in one sentence rather than by implication.
- [ ] No claim is added that the kit does not do today — the adoption rewrite of 2026-08-08
      found two claims this repo had just made false, and this is the same hazard.

## Notes

Filed 2026-08-11. Prerequisite for demoting `kit-recommendations.md` from a plan to a sources
document: everything worth keeping must live in the kit first.

Deliberately T1: documentation and one template, revertible, changes no derived number.
