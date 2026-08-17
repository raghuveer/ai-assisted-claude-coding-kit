---
id: T-20260817-kit-index-deletes-the-plan-so-task-conte
title: kit-index deletes the plan so task-context step 1 destroys what step 4 reads
epic: planning
tier: T3
lang: bash
paths: tooling/kit-index.sh, tooling/kit-plan.sh, skills/task-context/SKILL.md, tooling/schema.sql
state: open
---

## Intent

`kit-index.sh` rebuilds into a fresh database from `tooling/schema.sql` (`rm -f "$NEW"`, then
`sqlite3 "$NEW" < schema.sql`, lines 1195-1196). `goal` and `plan_item` are the **only two tables
written by a different tool** — `kit-plan.sh` — and they are **not derivable from any text file**,
so the rebuild silently drops them. The word "plan" does not appear anywhere in `kit-index.sh`.

`skills/task-context/SKILL.md` **step 1** is `kit-index.sh --if-stale`. **Step 4** queries
`plan_item` for the cluster pack. So the skill's first step deletes what its fourth step reads,
on any session where a task file, event, commit or profile has changed — that is, during ordinary
work.

Measured 2026-08-17 on a clean tree at `1f83fe8`, twice:

| Action | `plan_item` | `goal` | packs on disk |
|---|---|---|---|
| after `kit-plan.sh` | 77 | 1 | 11 |
| after one plain `kit-index.sh` | **0** | **0** | 11, orphaned |
| `kit-index.sh --if-stale`, nothing changed | 77 | 1 | 11 |
| `touch` one task file, then `--if-stale` | **0** | **0** | 11, orphaned |

The pack files are left on disk looking current. Nothing warns, and `kit-status.sh` has no
section that would notice.

**This falsifies a documented guarantee.** `docs/HANDOFF.md` §4.6: *"The plan is state, not
context. `/goal` computes an ordering once, writes it to `plan_item`, ends. Each task session
reads one row (~20 tokens) … and survives `/clear`, session end, or a crash."* It survives all
three. It does not survive the next session's first step.

**It is the most likely cause of `docs/MEASUREMENTS.md` §F** — *"13 cluster packs generated, read
by nothing"*. Not that nobody followed the skill: that by the time anyone did, there was no
`plan_item` row to find. The mechanism has been disabling itself on every ordinary session since
it was built.

## Acceptance criteria

- [ ] A plan survives a rebuild. `kit-plan.sh`, then `kit-index.sh`, then a `plan_item` count
      equal to the one before — asserted by a conformance step, not by hand.
- [ ] The fix is a **decision, recorded**, not a reflex. At least these are live and they differ
      in what a stale plan means: carry `goal`/`plan_item` across the rebuild; re-derive the plan
      as part of indexing; or persist the plan to a text file that the indexer reads like every
      other source of truth. The third is the only one consistent with *"tasks are FILES; the
      index is derived from them"* (`kit-task.sh` header) — a table that cannot be rebuilt from
      text is already the second source of truth this design exists to avoid.
- [ ] **A carried-forward plan must be able to go stale and say so.** If the plan survives the
      rebuild it can now describe tasks that have closed, split or changed tier. Whatever is
      chosen must make a stale plan detectable rather than confidently wrong — the same
      requirement `T-20260808-cluster-packs-are-generated-and-read-by-` AC4 places on packs.
- [ ] Orphaned packs cannot outlive their plan silently. Either they are removed with it, or
      `kit-status.sh` reports pack files with no corresponding `plan_item` rows.
- [ ] The conformance step **derives** its expectation from the authority rather than restating
      it — the set of tables the indexer does not populate should come from `schema.sql` and the
      indexer's own INSERT sites, so a seventh table added later is covered without an edit.
- [ ] `docs/HANDOFF.md` §4.6 either becomes true or is corrected. A guarantee that the plan
      survives a crash, published while it does not survive the next session, is worse than no
      guarantee.

## Notes

Found 2026-08-17 while pre-flighting the cluster-pack ROI experiment
(`docs/EXPERIMENTS/2026-08-17-cluster-pack-roi.md` §2.1), after `plan_item` was found empty with
six orphaned packs on disk.

**It blocks that experiment.** Arm A needs a `plan_item` row to survive from setup to step 4; run
today it loses the plan mid-session and silently becomes Arm B, so the experiment would report a
null result it was guaranteed to report. The experiment's §12 now carries a VOID condition that
queries `plan_item` *after* each run for exactly this reason.

`plan_item.cluster` is also commented in `tooling/schema.sql` as *"connected component over the
dependency graph"*, which `kit-plan.sh:131-142` deliberately no longer does — a small correction
to make while in this file.
