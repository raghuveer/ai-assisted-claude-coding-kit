---
id: T-20260802-record-spend-per-task-so-estimate-can-be
title: Record spend per task so estimate can be compared to actual
epic: measurement
tier: T2
state: open
---

## Intent

The kit records defects and state but never cost. Event kinds are checkpoint, finding and
vindication; the schema has no token or duration column. So the one number a delivery
estimate is judged against -- did this cost what we said it would -- cannot be computed from
anything the kit stores.

Cost is a function of tier and tier is assigned before spawning, so a tiered backlog is
already a forecast. The forecast side exists; the actual side does not.

## Acceptance criteria

- [ ] a spend event records tokens per agent invocation, with agent, model and task
- [ ] the index derives cost per task and per tier from those events
- [ ] status-report shows estimated against actual for the open backlog
- [ ] a task with no spend recorded is visibly absent rather than counted as zero
- [ ] recording is a side effect of work already being done, not a separate ritual

## Notes

The last criterion is the one that decides whether this survives. Trailer discipline works
because recording status is a side effect of the commit you were making anyway. A spend
record that requires someone to remember will be missing exactly on the busy tasks that
matter most, and a partial cost table is worse than none -- it reads as cheap work rather
than as unmeasured work, which is the same failure the escape rate had when the findings
loop was open circuit.

Tier accuracy is a prerequisite, not an adjacent concern. Two of three recorded tiers
measured too low, both in the direction that under-predicts, because the backlog was tiered
from finding severity and never checked against tier.rule floors. A forecast on those tiers
reads low and then overruns. See T-20260801-validate-a-task-s-recorded-tier-against-.

Measured baselines to forecast against, from docs/MEASUREMENTS.md: T2 task 220,336 including
review; T3 design stage 196,060 for researcher plus two reviewers. Both n=1, both on a
greenfield project, so they are a starting point rather than a rate card.
