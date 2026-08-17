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

---

## CLOSE-RECOMMENDATION — 2026-08-17, `006d81f`. The state stays `progress`.

**I am recommending, not deciding.** The task is not marked done and no finding is marked fixed;
both are the operator's, for the reason `.claude/CLAUDE.md` gives — a session certifying its own
output is the one signature that carries no information. What follows is the evidence to decide
on, including what is *not* done.

**Evidence base:** full conformance **81 passed, 0 failed over 53 steps** on a run with the tree
untouched throughout; CI green on all four jobs at `006d81f` (`trailers`, `structure`,
`conformance (ubuntu-latest)`, `conformance (macos-latest)`).

### The six acceptance criteria

| AC | State | Evidence |
|---|---|---|
| 1 — a plan survives a rebuild, asserted by a step not by hand | **met** | `plan round-trips identically…` asserts the rows are IDENTICAL, not merely present, and is mutation-proved: disabling the ingest turns it red while the table-enumeration step stays green |
| 2 — the fix is a decision, recorded | **met** | ADR 0004, now *Accepted — Option D*. A, B and D each rejected or chosen on stated grounds; the review forced D in and withdrew half the A rejection |
| 3 — a carried-forward plan can go stale and say so | **met, with a stated bound** | `#tasks_digest` → `plan_stale:<goal>` → a `kit-status.sh` notice; clears on replan. **The bound is real and is in the ADR:** the digest covers the task SET, not the ordering inputs — `escaped` events and `priority.w_*` / `cluster.hub_cap` reorder a plan that still reports fresh |
| 4 — orphaned packs cannot outlive their plan silently | **met, both directions** | packs-without-plan-rows *and* plan-rows-without-packs are both reported, the latter naming `kit-plan.sh --packs`. Verified firing in a clone and silent here |
| 5 — the step derives its expectation from the authority | **met** | table enumeration reads `CREATE TABLE` from `schema.sql` against the INSERT targets in `kit-index.sh`; it found `accelerator`/`accel_candidate` immediately, and their exemption asserts its own premise so it expires if anything ever writes them |
| 6 — `HANDOFF.md` §4.6 becomes true or is corrected | **met** | §4.6 rewritten, and it keeps the correction visible rather than quietly restating the guarantee |

### The T3 review chain — 35 findings, and where each stands

Implementation REVISE · approach REVISE (the only critical) · **security REJECT**. All three ran
concurrently against an empty finding table, so rung 5's blindness was structural.

| Disposition | n | Notes |
|---|---|---|
| **Fixed and verified** | **22** | incl. the critical and 16 of 21 majors |
| **Claim narrowed instead of widened** | 2 | the digest-coverage pair. Reviewers offered *"either widen the digest or narrow the claim"*; the claim was narrowed in `kit_plan_digest`'s docstring and the ADR. **Coverage is unchanged** |
| **Partially addressed** | 2 | see below — both are stated honestly rather than counted as done |
| **Not addressed** | 9 | 2 majors, 4 minors, 3 nits — listed below |

**The two partials, stated precisely rather than rounded up.**
`kit-index.sh:1296` — the staleness block still does **not** re-validate rows; it reads only
`#goal` and `#tasks_digest`. What *is* fixed is the consequence the reviewer named: a refused plan
is now recorded in `plan_refused` and rendered by `kit-status.sh`, so "the operator cannot learn
the plan is empty" no longer holds. The re-parse asymmetry itself remains.
`kit-init.sh:112` — the loose guard and the unconditional success message are fixed; the
**upgrade path is not**. An already-adopted repository never re-runs `kit-init.sh`, so the LF pin
never arrives there.

**The nine not addressed**, none of which I judge blocking, and the judgement is the operator's:

- **major** `SECURITY.md:41` — no trust-table row for `.project/plans/*.tsv`. ADR 0003's own
  convention requires one for a new untrusted input class. *This is the one I would fix first.*
- **major** `kit-plan.sh:343` — nothing checks the plan file is git-tracked. A `.gitignore`
  covering `.project/` silently returns the plan to machine-local state, which is the defect this
  task exists to fix, arriving through configuration instead of code. ADR 0003 already built this
  check for adapters.
- **minor** `schema.sql:207` `goal.state` has no text source and is reset every rebuild ·
  `kit-index.sh:1024` no format version and `#columns` never validated ·
  `kit-index.sh:1011` two files claiming one `#goal` still let glob order decide ·
  ADR team-cost note (a replan now dirties a tracked file needing a trailered commit)
- **nit** the spliced comment block · the no-op `DELETE` in section 3c · `SKILL.md:36` still
  describing clusters as grouped by declared dependency

### What I do NOT claim

- **Not that the ordering is any good.** `T-20260817-one-shared-file-merges-two-whole-epics-s`
  records 61 of 77 open tasks in one cluster. This task fixed where the plan lives, not what it says.
- **Not that the packs pay for themselves.** That is Gate B, still unrun and unsigned.
- **Not that reviewer read-only was enforced.** It is convention; `SECURITY.md` §3 says so.
- **Not that the recording path was clean.** The three replies reached `kit-finding.sh` through the
  orchestrator's context rather than `kit-review-record.sh --cmd`, so the unchanged-pipe guarantee
  did not hold. Findings were reproduced field for field; the narratives are condensations and each
  says so in its own first paragraph.

### Recommendation

**Close it**, with the nine open findings left on the record rather than folded in — they are
smaller than the task and two of them (`SECURITY.md`, the tracked-file check) deserve their own
task rather than a footnote here. If any of them should block instead, that is a defensible call
and the honest place to make it is before the mark, not after.

Unblocks `T-20260808-cluster-packs-are-generated-and-read-by-`, which `blocked_by` names.
