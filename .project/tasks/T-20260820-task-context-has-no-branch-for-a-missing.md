---
id: T-20260820-task-context-has-no-branch-for-a-missing
title: task-context has no branch for a missing pack and the obvious recovery destroys the plan
epic: planning
tier: T2
lang: markdown
paths: skills/task-context/SKILL.md, tooling/kit-plan.sh
state: open
---

## Intent

`skills/task-context/SKILL.md` step 4 covers exactly two cases: **no plan row** — *"skip the pack,
do not invent one"* — and a pack that looks **stale** — *"re-run `kit-plan.sh`"*.

It has no branch for the case that a fresh clone produces **every time**: a plan row exists and the
pack does not. `.gitignore` excludes `.project/packs/` while `.project/plans/*.tsv` is committed
(ADR 0004), so a clone arrives with plan rows in the index and no packs on disk. That is not an
edge case; it is the guaranteed state of every clone, every new machine, and every deleted cache.

**The dangerous half is that the obvious recovery is the wrong one.** The skill's only mention of
repair is *"re-run `kit-plan.sh`"* — which **recomputes the ordering and overwrites the committed
plan with a new digest**, discarding the very plan the clone was carrying. The correct command is
`kit-plan.sh --packs`, which rebuilds from the plan already on disk without replanning, and **the
skill never mentions it.** An agent following step 4 literally is one plausible guess away from
destroying the artefact it was trying to load.

## Reproduced 2026-08-20 in a live plugin session, not argued

A subject repo was adopted, planned, committed, then cloned with `--no-hardlinks` and its remote
removed. After `kit-index.sh`: **3 plan rows, 0 packs**, and `kit-status.sh` correctly reported
*"Plan row(s) with no cluster pack on disk"*.

A session run under `--plugin-dir` was asked to follow the skill exactly. It reported:

> *"Reading it failed — the entire `.project/packs/` directory did not exist… Step 4 covers
> exactly two cases… Neither branch applies, and the skill never mentions `--packs` or the
> gitignored-cache/committed-plan split that guarantees this state on every fresh clone."*

**It recovered correctly, and how it did so is the argument for fixing the skill rather than
trusting the recovery.** It checked `meta` for `cluster_packs_withheld:default` first — to
distinguish *missing* from *deliberately withheld*, since rebuilding a withheld pack would
re-create what the planner intentionally removed — then chose `--packs` over bare `kit-plan.sh`
*"precisely because that would replan and discard the committed plan"*, and verified
`git status --porcelain` clean afterwards.

None of that came from the skill. It came from reading `kit-plan.sh:29-35`. A session that did not
go source-diving would have skipped the pack silently or run the destructive command.

It also classified the result as **degraded, not complete**, and held the line that blast radius
was *"unknown, not small"* — so the reporting discipline survived; only the recovery guidance is
missing.

## Acceptance criteria

- [ ] Step 4 names the **third case** — row present, pack absent — separately from "no row" and
      "stale", because the three have different causes and different remedies.
- [ ] It names `kit-plan.sh --packs` and says **why not bare `kit-plan.sh`**: the bare form
      recomputes the ordering and discards a committed plan. A remedy given without its
      counter-indication is how the wrong one gets chosen under time pressure.
- [ ] It distinguishes **missing** from **withheld**. `cluster_packs_withheld:<goal>` in `meta` is
      the discriminator and a session found it unaided; the skill should not require that. A
      withheld pack must NOT be rebuilt — that would re-create precisely what the planner removed
      for being degenerate.
- [ ] The reader is told what to do when neither applies: proceed **with the context degraded and
      said so**, never silently. The session already does this correctly on blast radius; the same
      rule should be explicit for the pack.
- [ ] A check that can fail. The conformance step for `--packs` recovery asserts the mechanism; it
      does not assert the skill documents it. Deriving the assertion from the flag list, as the
      TRIAL-PROTOCOL step already does, keeps a renamed flag from silently orphaning the guidance.

## Notes

Found 2026-08-20 while exercising the plugin paths the earlier smoke test did not reach, on
`T-20260808-trial-the-kit-on-one-unfamiliar-brownfie`.

**This is the residue of the design review's critical.** `T-20260817-kit-index-deletes-the-plan-so-task-conte`
closed *"packs are a rebuildable cache of the plan is false"* by adding `--packs` and making the
state discoverable in `kit-status.sh`. Both were necessary. Neither reached the **consumer**: the
skill that dereferences the pack still has no miss path, which is exactly what the reviewer wrote
— *"task-context step 4 has no miss path"* — and only the recovery half was fixed.

**Do not solve it by making the skill run `--packs` automatically.** A skill that repairs state as
a side effect of reading it is a write nobody asked for, and it would mask the missing-pack
condition that `kit-status.sh` was just taught to report.
