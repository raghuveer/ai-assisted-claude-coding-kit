---
id: T-20260808-cluster-packs-are-generated-and-read-by-
title: Cluster packs are generated and read by nothing, so context economics is unmeasured
epic: measurement
tier: T2
lang: bash
paths: tooling/kit-plan.sh, skills/task-context/SKILL.md
state: open
---

## Intent

The mechanism for holding context across a GROUP of tasks already exists, on both sides, and
has never once been exercised.

`kit-plan.sh` writes cluster packs to `.project/packs/<goal>/c<n>.md`. `skills/task-context`
instructs an agent to load the pack for its cluster and says explicitly: *the pack already
named the cluster's files — do not re-derive them.* `docs/MEASUREMENTS.md` §F lists the result
under "Still untested": **13 cluster packs generated, read by nothing.**

So the kit's answer to "review the group once instead of re-deriving per task" is built,
documented, wired at both ends, and has zero evidence behind it. That is the same shape as
every defect found on 2026-07-31 — a path that had never been executed — and it sits on the
lever the whole design claims is the largest available. `skills/checkpoint` states it plainly:
the context read at the start of every turn tends to dominate spend.

## Acceptance criteria

- [ ] A pack is loaded by a real agent on a real task, and the fact that it was loaded is
      observable rather than assumed. "The skill says to read it" is not evidence that it was
      read.
- [ ] Measure both arms in the same unit the spend work settled on — billing-weighted
      input-token-equivalents from the per-agent transcripts. Two tasks in one cluster, one arm
      with the pack and one without, and report the difference with n stated.
- [ ] Report the QUALITY side too, not only the tokens. The claim is that a pack removes
      repeated derivation without removing review depth; a cheaper arm that finds less has
      disproved the claim rather than supported it. Compare findings, not just cost.
- [ ] Say what happens when the pack is STALE — written by a plan, read by a task whose files
      have since moved. A pack that names files that no longer exist is a confident wrong
      answer, which is worse here than no pack.
- [ ] If the packs turn out not to pay for themselves, say so and stop generating them. A
      generated artifact nothing reads is resident cost with no return, and the kit's own
      argument is that the cost lever is deliberate spending, not accumulation.

## Notes

Surfaced 2026-08-08 while reviewing the backlog against the operator's intent to hold context
for a group of tasks rather than per task, to avoid repeating review while keeping quality.
The instinct is exactly what this mechanism was built for — which is why it is worth
measuring rather than rebuilding.

Related: T-20260731-accelerator-line-budget-and-eviction is the same economics question one
layer up, on what an accelerator is allowed to cost.
