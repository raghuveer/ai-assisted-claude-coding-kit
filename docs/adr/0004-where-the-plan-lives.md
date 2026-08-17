# ADR 0004: Where the plan lives

- **Date:** 2026-08-17   **Status:** **Accepted — Option C**   **Supersedes:** —   **Related:** [[0003-whether-an-ingest-adapter-is-trusted]]

Serves AC2 of `T-20260817-kit-index-deletes-the-plan-so-task-conte`, which requires this to be a
recorded decision rather than a reflex, because three answers are live and they differ in what a
stale plan means.

## Context

`kit-index.sh` rebuilds into a fresh database from `tooling/schema.sql` and moves it into place.
`goal` and `plan_item` are the **only two tables written by a different tool** — `kit-plan.sh` —
and they are **not derivable from any text source**, so every rebuild drops them. The word "plan"
does not appear anywhere in `kit-index.sh`. The `meta` key `plan_withheld:<goal>` goes the same
way, and it is the only record of how many tasks a plan withheld and why.

Measured 2026-08-17 at `1f83fe8`, on a clean tree:

| Action | `plan_item` | `goal` | packs on disk |
|---|---|---|---|
| after `kit-plan.sh` | 77 | 1 | 11 |
| after one plain `kit-index.sh` | **0** | **0** | 11, orphaned |
| `--if-stale`, nothing changed | 77 | 1 | 11 |
| `touch` one task file, then `--if-stale` | **0** | **0** | 11, orphaned |

`skills/task-context/SKILL.md` step 1 is `kit-index.sh --if-stale` and step 4 reads `plan_item`.
Any task edit, event or commit makes the index stale, so **the skill's first step deletes what its
fourth step reads**, during ordinary work. The pack files are left on disk looking current and
nothing warns.

This falsifies `docs/HANDOFF.md` §4.6 — *"The plan is state, not context … survives `/clear`,
session end, or a crash"* — and is the most likely explanation for `docs/MEASUREMENTS.md` §F,
*"13 cluster packs generated, read by nothing"*. Not that nobody followed the skill: that there
was no row left to find.

**The ownership rule already exists and this violates it.** `docs/ADAPTERS.md` tells adapter
authors: *"Do not write to `plan_item` or `goal` — those belong to `kit-plan.sh`."* The indexer
does not write them either. It destroys them, which is the one operation the ownership rule never
contemplated.

## Options

**A — carry the two tables across the rebuild.** Copy `goal`, `plan_item` and the
`plan_withheld:` meta rows out of the old database before the swap and back in after.

Smallest diff, roughly fifteen lines, and no new file format. But it makes `index.db` the sole
home of state that exists nowhere else, and `index.db` is **gitignored and machine-local**: a
fresh clone, a new laptop or a `rm index.db` still loses the plan with nothing announcing it. It
also breaks the invariant `kit-task.sh` states in its own header — *"Tasks are FILES; the index is
derived from them. Nothing is ever written to the database directly."* A table that survives a
rebuild because it was copied forward is precisely a second source of truth.

**B — re-derive the plan during indexing.** Have `kit-index.sh` run the planner.

Removes the persistence question entirely. Rejected on two grounds. Planning is an explicit act
with its own weights and goal — `/goal` computes an ordering **once** — and re-deriving it on
every index would silently reorder live work whenever a task's tier or `blocked_by` changed
mid-session. It would also destroy pack byte-identity, which `kit-plan.sh:305-313` depends on:
the packs are *"written once per plan and byte-identical thereafter"*, and a plan recomputed on
every rebuild has no "thereafter".

**C — the plan is a text file, and the index is derived from it like everything else.**
`kit-plan.sh` writes `.project/plans/<goal>.tsv`; `kit-index.sh` reads it and populates `goal`,
`plan_item` and the withheld count on every rebuild.

Largest diff of the three. It is the only option that makes the documented guarantee true rather
than approximately true: the plan then survives a rebuild, a fresh clone, a deleted index and a
different machine, for the same reason task files do. It also puts the plan under the rule the
rest of the design already follows, so there is one answer to "where does truth live" instead of
two.

## Decision

**Option C.** The plan is text; the index is derived from it.

Concretely:

- `kit-plan.sh` writes `.project/plans/<goal-slug>.tsv` — a `#`-prefixed metadata header (goal,
  creation timestamp, withheld count, and a digest of the task set it was computed from) followed
  by one tab-separated row per plan item: `goal_id, task_id, layer, rank, score, cluster`.
- `kit-index.sh` gains section 3c, which reads those files and emits the `goal`, `plan_item` and
  `plan_withheld:` rows. It runs after the task and event sources and before derivation.
- The creation timestamp moves **into the file**. It was `strftime('now')` inside the emitted SQL,
  which would have re-stamped the goal on every rebuild and made "delete the index, rebuild,
  compare" false for a reason unrelated to the plan.
- `.project/plans/` is **tracked in git**, not gitignored. Packs are a rebuildable cache of the
  plan and stay ignored; the plan is the decision they are cached from. `.project/events.ndjson`
  is tracked for the same reason.

**The plan can now go stale, and that is the cost of this option.** Under the old behaviour a plan
never outlived its inputs because it never outlived anything. Carried forward, it can describe
tasks that have since closed, split or changed tier. So the header records a digest of the open
task set at plan time, the indexer recomputes it and stores `plan_stale:<goal>`, and
`kit-status.sh` reports a stale plan rather than serving it silently. **A carried-forward plan
that cannot say it is stale would be a worse defect than the one being fixed** — it would replace
a plan that visibly vanished with one that is confidently wrong, which is the same trade
`T-20260808-cluster-packs-are-generated-and-read-by-` AC4 refuses for packs.

## Consequences

- `docs/HANDOFF.md` §4.6 becomes true and is left standing. Until this lands it is a published
  guarantee the code does not keep.
- A conformance step asserts the round trip: plan, reindex, and the rows are identical — not
  merely present. Identity is what catches `kit-plan.sh`'s writer and `kit-index.sh`'s reader
  drifting apart, which is the failure this option introduces the possibility of.
- A second conformance step derives its expectation from the authority instead of restating it:
  every table in `schema.sql` must either be populated by `kit-index.sh` or restored from text.
  A seventh table added later is covered without anyone remembering to edit the test.
- `kit-status.sh` reports pack directories with no plan rows, so an orphaned pack cannot outlive
  its plan silently again.
- The plan is now shared through git, which is a behaviour change for a team: two people planning
  the same goal will conflict in `.project/plans/default.tsv`. That is a visible merge conflict
  over an ordering decision, which is the correct place for that disagreement to surface. It was
  previously invisible because neither person's plan survived their own next session.
- **Not addressed here:** whether the ordering itself is any good.
  `T-20260817-one-shared-file-merges-two-whole-epics-s` records that 61 of 77 open tasks currently
  land in one cluster. Persisting a degenerate plan faithfully is still persisting a degenerate
  plan, and this ADR fixes only where it lives.
