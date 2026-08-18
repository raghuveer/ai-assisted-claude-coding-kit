---
id: T-20260808-cluster-packs-are-generated-and-read-by-
title: Cluster packs are generated and read by nothing, so context economics is unmeasured
epic: measurement
tier: T2
lang: bash
paths: tooling/kit-plan.sh, skills/task-context/SKILL.md
blocked_by: T-20260817-kit-index-deletes-the-plan-so-task-conte, T-20260817-one-shared-file-merges-two-whole-epics-s
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

---

## Folded in 2026-08-11: context economics is now the ROI case (R-13)

This task was housekeeping. It is now the kit's central ROI experiment, and should be treated as
the highest-value item on the register's list.

The claim to test, from an external account of enterprise context layers: giving an agent a map
instead of an open problem cut token usage sharply, because a high-agency model handed an
open-ended task *"will spawn a thousand subagents to go explore the entire world"* — and the
more capable the model, the worse the guzzling. A figure of ~75% was quoted. **Treat it as a
vendor number about a different product: a hypothesis to test, never a figure to repeat.**

The kit already has the mechanism. `kit-plan.sh` writes cluster packs from the co-change graph —
four exist in `.project/packs/default/` — and nothing measures whether they help.

The experiment: the same task, with and without the pack, measured against the `baseline/`
capture of 2026-07-29. Metrics that matter here are tokens per merged change and the
cache-read : cache-creation ratio.

Folded in from R-13, which also asked for an audit of the five documentation layers against four
behaviours — skills load on demand, agents isolate context, rules are always loaded so install
selectively, hooks run outside model context. Anything always-loaded that does not earn its
place should move. That audit belongs here because it is the same question: what is context
costing, and what is it buying.

---

## 2026-08-17: design pre-registered, and the experiment is blocked

`docs/EXPERIMENTS/2026-08-17-cluster-pack-roi.md` holds the arms, the unit, the decision rule and
the deletion list, all written before any data exists. **Nothing has been spent.** It awaits
operator sign-off on §3 (route), the AC2 amendment, the thresholds and a budget cap.

Pre-flight found five defects, now filed:
`T-20260817-kit-index-deletes-the-plan-so-task-conte` ·
`T-20260817-a-cluster-pack-file-list-ignores-declare` ·
`T-20260817-one-shared-file-merges-two-whole-epics-s` ·
`T-20260817-a-touches-edge-is-never-checked-against-` ·
`T-20260817-task-context-reads-the-task-spec-at-step`.

**`blocked_by` added for the first of them, and this is the one that matters:** `kit-index.sh`
deletes `plan_item`, and `skills/task-context` step 1 runs `kit-index.sh --if-stale` while step 4
reads `plan_item`. So Arm A loses its plan mid-session and silently becomes Arm B — the experiment
would report a null result it was guaranteed to report. It also means the mechanism has been
disabling itself on every ordinary session since it was built, which is the likely cause of
`docs/MEASUREMENTS.md` §F's "13 cluster packs generated, read by nothing".

**AC2 as written is amended in the design and needs sign-off**: two tasks in one cluster confounds
the arm with the task, so the same task runs in both arms from the same commit in separate
isolated copies, with n = pairs.
