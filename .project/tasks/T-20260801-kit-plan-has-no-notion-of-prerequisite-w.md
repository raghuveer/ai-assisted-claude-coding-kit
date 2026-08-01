---
id: T-20260801-kit-plan-has-no-notion-of-prerequisite-w
title: kit-plan has no notion of prerequisite work on a greenfield repo
epic: planning
tier: T1
state: open
---

## Intent

On a greenfield project with 22 open tasks, `kit-plan.sh` produced two layers: 20 tasks in
layer 0, 2 in layer 1. The scaffold task -- which creates the toolchain every other task
needs in order to be verified at all -- ranked ELEVENTH, behind ten T3 tasks.

Topologically correct, practically wrong. `depends_on` comes only from hand-declared
`blocked_by`, and the co-change extractor that would narrow it needs git history over real
code. Greenfield has neither: 2 declared edges across 22 tasks, and an empty co-change
graph.

Compounding it, the priority score is effectively a proxy for tier -- T3s scored 3.0, T2s
2.0, T1s 1.0, with a bonus for blocking others. So the plan says "do the riskiest work
first" at exactly the moment the verification ladder reports rungs unavailable and every
tier is inflated. The ordering inverts what the profile's own reasoning implies.

The README documents the `depends_on` limit honestly. What is not documented is that on a
greenfield repo the planner's output is close to "sorted by tier descending", and that
this is its worst case rather than a typical one.

## Acceptance criteria

- [ ] a task that establishes verification capability is not ranked below work that cannot
      be verified without it
- [ ] the plan states when it is running with a near-empty dependency graph, rather than
      presenting a confident ordering built from two edges
- [ ] the greenfield case is documented in known limits alongside the existing
      `depends_on` note

## Notes

The narrow fix is a `blocked_by` on each task that needs a toolchain, which is manual and
does not generalise. The broader question is whether the planner should know that ladder
availability is a precondition, given the profile already records which rungs are
unavailable -- that information is present and unused.

Related: [[T-20260801-validate-a-task-s-recorded-tier-against-]], since the scores that
drive this ordering are computed from tiers that were themselves unvalidated.
