---
id: T-20260817-a-touches-edge-is-never-checked-against-
title: A touches edge is never checked against the current tree so a pack names deleted files
epic: planning
tier: T3
lang: bash
paths: tooling/kit-index.sh, tooling/kit-plan.sh
state: open
---

## Intent

`touches` edges are derived from **full git history** on every rebuild (`kit-index.sh:645`, inside
the git pass at line 442: *"trailers are the state transitions, diffs are the touches edges"*).
Nothing ever checks the resulting path against the current working tree, and nothing needs to
prune — the index is rebuilt from scratch each time, so the edge is faithfully re-derived from a
commit that will remain in history forever.

The consequence, measured 2026-08-17 at `1f83fe8`: **1 of the 40 file rows in cluster 1's pack
names a file that cannot be opened.**

    tooling/__pycache__/kit_findings.cpython-314.pyc  (2 tasks)

That file is untracked and gitignored (`.gitignore:18-19`) and was removed at `8704290` — *"Stop
committing Python bytecode: one .pyc turned three CI jobs red"*. The pack still lists it, with a
task count, indistinguishable from the 39 rows that are real.

**This is AC4 of `T-20260808-cluster-packs-are-generated-and-read-by-` occurring already, with no
rename involved.** That criterion asks what happens when a pack is stale — *"written by a plan,
read by a task whose files have since moved. A pack that names files that no longer exist is a
confident wrong answer, which is worse here than no pack."* The condition does not need a plan to
go stale to arise: history is permanent and deletion is normal, so **every long-lived repository
accumulates these**. One in forty here, after four weeks. The rate on a four-year brownfield
subject is unknown and is the reason this is worth fixing before the brownfield trial rather than
after.

Scope note: this is about **presentation of derived paths**, not about pruning history. The edge
records something true — that commit did touch that file. What is wrong is emitting it into an
artifact an agent is told to trust without saying the file is gone.

## Acceptance criteria

- [ ] A pack does not present a path that no longer exists in the tree as though it did — removed,
      or marked, but not silently listed among live files.
- [ ] **Decide where the check belongs and record why.** In the indexer it is one existence test
      per path at build time and it fixes every consumer at once; in `kit-plan.sh` it is local to
      the pack and leaves blast radius (`skills/task-context` steps 5-6) still reporting the
      deleted path. The second is cheaper and narrower; the first is the one that stops this
      recurring in a consumer nobody has written yet.
- [ ] The blast-radius and co-change queries in `skills/task-context` are checked for the same
      exposure. If they also surface deleted paths, say so here rather than fixing one surface and
      declaring the class closed.
- [ ] A conformance step covers it: a commit that adds a file, a commit that deletes it, and an
      assertion that the derived artifact does not present it as current. It must fail if the
      check is removed.
- [ ] **Say what a rename does**, which is the case AC4 actually names. Git records it as a
      delete plus an add; the pack will drop the old path and the new one has no `touches` edge
      until the next commit against that task. Whether that is acceptable is a judgement to
      record, not an outcome to discover during a trial.

## Notes

Found 2026-08-17 pre-flighting the cluster-pack ROI experiment
(`docs/EXPERIMENTS/2026-08-17-cluster-pack-roi.md` §2(d)).

**Correction on the record.** This was first reported as *"a build artifact appears in the pack's
file list, unfiltered"* — implying the pack needs an ignore-rule for `__pycache__`. That was
wrong: the `.pyc` is already gitignored and was already deleted. Verification before filing found
the real mechanism, which is general rather than Python-specific and would not have been fixed by
an ignore-rule.

Useful to the experiment: `docs/EXPERIMENTS/2026-08-17-cluster-pack-roi.md` §9's Arm C now has a
**found** instance of a stale pack rather than only a synthesised one, which is better evidence
than a rename staged for the occasion.
