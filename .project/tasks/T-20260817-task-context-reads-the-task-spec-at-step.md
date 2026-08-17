---
id: T-20260817-task-context-reads-the-task-spec-at-step
title: task-context reads the task spec at step 3 then says to place the pack before it
epic: planning
tier: T2
lang: markdown
paths: skills/task-context/SKILL.md, tooling/kit-plan.sh
state: open
---

## Intent

`skills/task-context/SKILL.md` is a numbered procedure. Step 3 says:

> Read **only** the task's own file — the path is in `node.path`.

Step 4 then says of the cluster pack:

> Place it **early and verbatim**, before the task spec.

An agent executing the steps in order has already read the task spec when it reaches step 4, and
cannot retroactively place anything before it. The two instructions cannot both be followed.

The instruction is not decorative — it carries the stated cost rationale:

> It is frozen for the life of the plan and byte-identical across every session in the cluster, so
> an unmodified copy sits in the cached prefix and costs a fraction of a fresh read. Reformatting
> or summarising it breaks that and you pay full price in every sibling session.

So the ordering exists to put the pack in a cached prefix, and the step order defeats it.

**The underlying claim is separately doubtful and should be settled at the same time.**
`kit-plan.sh:308-309` asserts the pack *"belongs ABOVE the cache breakpoint and is served at 0.1x
instead of being re-read at full price in each session"*. As built, the pack arrives as a `Read`
tool result **inside** the conversation — below the breakpoint described in `docs/HANDOFF.md`
§4.6, and after step 1's index output and step 3's task file, both of which vary per task, so the
prefix has already diverged before the pack lands. Swapping steps 3 and 4 makes the procedure
self-consistent; it does not by itself make the pack cacheable across sessions.

## Acceptance criteria

- [ ] The skill's step order and its placement instruction agree. Simplest form: the pack is
      fetched before the task spec.
- [ ] **The cache claim is either substantiated or restated as what it actually buys.** If the
      pack cannot sit above the breakpoint as the harness assembles context, then the saving is
      avoided derivation and not a 0.1× cache rate, and both `kit-plan.sh:308-309` and the skill
      should say so. `docs/EXPERIMENTS/2026-08-17-cluster-pack-roi.md` §1 separates these as H1
      and H2 and the counters distinguish them — **do not settle this by argument when it is
      measurable**, and do not close this criterion on reasoning alone.
- [ ] A conformance step asserts the skill's step referring to the pack precedes the step reading
      the task file, so the two cannot drift apart again. Deriving the order from the document
      rather than restating it is the pattern already paying off elsewhere in the suite.

## Notes

Found 2026-08-17 pre-flighting the cluster-pack ROI experiment
(`docs/EXPERIMENTS/2026-08-17-cluster-pack-roi.md` §1). Proposed at T1 as a documentation-ordering
defect and **raised to T2 by the kit's own floor** — the declared `paths:` include
`tooling/kit-plan.sh`, and `tier.rule: tooling/** T2`. The measurement the second criterion depends
on belongs to `T-20260808-cluster-packs-are-generated-and-read-by-` and is not duplicated here.

Sequencing: fixing the wording is cheap and can land at any time, but the second criterion cannot
be closed until the experiment produces counters. Do not let that hold the first.
