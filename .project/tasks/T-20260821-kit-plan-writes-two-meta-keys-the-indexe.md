---
id: T-20260821-kit-plan-writes-two-meta-keys-the-indexe
title: kit-plan writes two meta keys the indexer never re-derives so a reindex erases them
epic: planning
tier: T2
lang: bash
paths: tooling/kit-plan.sh, tooling/kit-index.sh, tooling/kit-status.sh
state: open
---

## Intent

ADR 0004 removed the second writer: `kit-plan.sh` produces the plan TEXT and `kit-index.sh` derives
`goal` and `plan_item` from it, so that nothing but the indexer writes the database. **Two writes
survived that change and nobody noticed**, because they are `meta` rows rather than table rows.

    kit-plan.sh:523  INSERT OR REPLACE INTO meta VALUES('cluster_largest_pct:<goal>', …)
    kit-plan.sh:536  INSERT OR REPLACE INTO meta VALUES('cluster_packs_withheld:<goal>', '1')
    kit-plan.sh:540  DELETE FROM meta WHERE key='cluster_packs_withheld:<goal>'

Both keys are **read by `kit-status.sh`** — the withhold notice and the cluster-distribution
notice — and **written by nothing in `kit-index.sh`**. Measured: `grep -c` for either key in
`kit-index.sh` returns **0**.

`kit-index.sh` builds into a fresh database from `schema.sql` and moves it into place, so **any
plain `kit-index.sh` after a plan silently erases both.** The withhold state then reads as absent,
and `kit-status.sh` reports withheld packs as merely *missing* — which is the wrong cause and the
wrong remedy, and is precisely the confusion `kit-plan.sh:537`'s own error string warns about.

This is the same class as the defect ADR 0004 was written to fix, one level down: derived state
with a writer other than the indexer, lost on rebuild.

## Acceptance criteria

- [ ] Both keys survive a plain `kit-index.sh`, or they stop being `meta` rows. The obvious shapes
      are to derive them from the plan file the way `plan_item` already is (the `#withheld` header
      is already written into the plan for exactly this reason), or to record them as events.
- [ ] Whatever lands, `kit-plan.sh` no longer writes to the database. One writer, one direction.
- [ ] `kit-status.sh` can still tell **withheld** from **missing**. Conflating them is the failure
      this protects, and a T3 security review already flagged that exact conflation once.
- [ ] A check that can fail in the shape the defect takes: plan a fixture whose clustering is
      degenerate, assert the withhold notice, run a plain `kit-index.sh`, and assert the notice is
      **still there**. A test that only runs the planner passes on the broken code.

## Notes

Found 2026-08-21 by an approach review of `docs/adr/0005`, which had asserted — in a table headed
*"verified rather than assumed"* — that exactly one direct store write remained. The reviewer
checked and found three. **The ADR's error and this defect are the same fact**: the claim was
written from memory of ADR 0004's intent rather than from the code.

Related: `T-20260820-kit-plan-computes-the-ordering-before-re` is also about `kit-plan.sh`
ordering-vs-index sequencing; this one is about what it writes.
