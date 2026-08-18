---
id: T-20260818-nothing-reviews-the-plan-so-a-wrong-orde
title: Nothing reviews the plan, so a wrong order survives until a human asks
epic: planning
tier: T2
lang: bash
paths: tooling/kit-plan.sh, tooling/kit-status.sh, skills/task-context/SKILL.md
state: open
---

## Intent

The kit has five verification rungs and eight agents, and **every one is scoped to a change** — a
design document or a diff. `approach-reviewer` asks whether an approach is right,
`implementation-reviewer` whether the code is, `verify-ladder` whether a change has been verified
deeply enough for its tier.

**Nothing asks whether it is the right next change.** The plan is the only artifact the kit
produces that no reviewer reads and no rung covers — and ADR 0004 has just made it durable,
committed and derived-from-text, so it is first-class in every respect except that.

Full argument, evidence and four candidate mechanisms:
`docs/design-input/2026-08-18-the-plan-is-the-unreviewed-artifact.md`.

**Observed 2026-08-17/18.** In one session the agent recommended a next task three times; each
time the operator asked for a re-check, and each check refuted the recommendation — a `depends_on`
edge unaccounted for, a premise carried into a context where it did not hold, and an ordering that
was backwards because the artifact it optimised had degraded since the figure was taken. **None of
the three was caught by anything in the kit.** All three were caught by a human asking, at exactly
the right three moments.

**Why it is cheap today and expensive later.** The operator is currently the sequencing reviewer
and a wrong recommendation costs one exchange. Auto-mode removes that prompt, and the failure mode
becomes thrash: start task N, discover mid-implementation that M should have come first, abandon or
rework. The cost is tokens and wall clock, and a contaminated record — a task showing `progress`
with abandoned work behind it, which spend and escape-rate then attribute to the wrong thing.

**It is the same lesson the reviewer agents already encode, one level up.** Those exist because a
coder's judgement of its own output is the signature that carries no information. The agent that
chose the order is the worst judge of whether the order is right.

## Acceptance criteria

- [ ] **Measure before building.** Thrash rate is derivable from data already recorded — tasks that
      moved `progress` → `open`, plan top-N churn between `kit-plan.sh` runs, commits against a
      task later found blocked, `blocked_by` edges added after work began on the dependent. Report
      it. **This criterion comes first deliberately**, and the argument is the kit's own: building
      a sequencing control without it repeats `T-20260808-cluster-packs-are-generated-and-read-by-`
      exactly — a mechanism wired at both ends, documented, and never measured.
- [ ] **"The thrash rate is low, build nothing" is a legitimate and preferred outcome**, recorded
      with its number. Closing this line cheaply beats four mechanisms nobody can evaluate.
- [ ] If the measurement justifies it, the **undeclared-dependency lint** is the first thing built,
      because it is the cheapest and needs no agent spend: a task file, ADR or design doc naming
      another task id in prose must either declare it in `blocked_by` or carry an explicit
      "not a blocker, because…". **Demonstrated already:** declaring the clustering task moved it
      from plan rank 49 to rank 5 and pushed the dependent into layer 1 — the ordering three
      retellings of prose had failed to produce arrived the moment it was declared.
- [ ] Any lint must handle the false positive it will produce — a task that legitimately *mentions*
      another without depending on it. An exemption marker is part of the design, not an
      afterthought, or the check gets disabled the first week.
- [ ] **Scope holds: support kit, not agent framework.** Each candidate is a lint, a rung, a skill
      or a reviewer definition. A mechanism that selects the next task and acts on it without the
      operator is out of scope however well it would work.
- [ ] Whatever ships has a check that can fail, and the failure is demonstrated by mutation rather
      than asserted.

## Notes

Filed 2026-08-18 at the operator's prompting, after the third reversal in one session, with the
explicit question: how does this lesson improve the kit strategically rather than being re-learned
per session.

**Not started, and deliberately not designed further here.** The design input names four candidates
(measurement, dependency lint, premise re-derivation, plan-review gate) and recommends the
measurement first. Tiering and the decision between them belong in review, not in this note.

The premise re-derivation candidate composes with ADR 0004's digest work — same shape: record what
a claim was computed from, recompute it, report the delta — so if that one is chosen, read
`kit_plan_digest` first rather than inventing a second mechanism for the same job.
