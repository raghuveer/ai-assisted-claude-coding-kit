---
id: T-20260817-a-cluster-pack-file-list-ignores-declare
title: A cluster pack file list ignores declared paths so it is empty before work starts
epic: planning
tier: T3
lang: bash
paths: tooling/kit-plan.sh, tooling/kit-index.sh
state: open
---

## Intent

A cluster pack's *"Files this cluster touches"* section is built from one source and one only:

    JOIN edge e ON e.src=p.task_id AND e.rel='touches'      -- kit-plan.sh:351

`touches` edges have exactly one origin — commit diffs carrying a `Task-Id`
(`kit-index.sh:645`, the only `touches` INSERT in the file; there are three edge INSERTs total
and the other two are `depends_on` and `regressed`). So **the pack can only describe work that
has already been committed**, and the pack is read when *starting* a task, which by definition
has no commits yet.

Measured 2026-08-17 at `1f83fe8`:

- **19 of 77** open tasks carry any `touches` edge.
- **42 of the 61** tasks in cluster 1 have none.
- **10 of 11** packs therefore print *"none recorded yet — no commits touch these tasks"*.
- **82 of 104** task files declare a non-empty `paths:` in frontmatter.

**The kit has already met and fixed this exact gap one file over.** `kit-index.sh:206-213`, on
tier floors:

> Files a task has already touched come from the edge table — but **7 of 8 open tasks in a real
> backlog had no touches edges**, because nothing is committed against a task until work begins.
> A floor that only sees touched files therefore passes silently on every task that has not
> started, which is exactly when the tier still matters. So a task may also declare `paths:` in
> its frontmatter.

The floor reads two sources. The pack reads one. The declared paths are sitting in 82 task files,
already parsed by the indexer, and the pack query never looks at them.

The consequence is that the pack's most load-bearing section — the one
`skills/task-context/SKILL.md` step 7 tells the agent not to re-derive (*"The pack already named
the cluster's files — do not re-derive them"*) — is empty for three quarters of the backlog, and
an agent told not to re-derive an empty list has been told to work blind.

## Acceptance criteria

- [ ] The pack's file section draws on declared `paths:` as well as `touches` edges, and a task
      with no commits and a declared `paths:` contributes files to its cluster's pack.
- [ ] **The two sources stay distinguishable in the pack.** A file a task has actually changed
      and a file it *says* it will change are different claims, and merging them silently turns a
      declaration into evidence. Mark them, or the pack's confidence is unearned.
- [ ] **Glob expansion is handled, and this is why the change is not a one-liner.** `paths:`
      values are globs; `node.id` values are literal `f:<path>`. `kit-index.sh:253-265` already
      refuses `[`, `]` and `?` in a glob, with measured reasons (SQLite `GLOB` treats `[ab]` as a
      character class and `?` as a character while the awk side matches a byte). Whatever expands
      globs here must agree with the floor path or be the same code — **two expanders that
      disagree is the defect that section was written about.**
- [ ] A conformance step proves it with a task that has a declared `paths:` and no commits, and
      it fails if the pack's file section comes back empty for that task.
- [ ] Say what happens when a declared glob matches nothing — a pack naming a path that does not
      exist is the failure `T-20260817-a-touches-edge-is-never-checked-against-` is about, and
      this change can introduce it from a second direction.

## Notes

Found 2026-08-17 pre-flighting the cluster-pack ROI experiment
(`docs/EXPERIMENTS/2026-08-17-cluster-pack-roi.md` §2(a)).

**Without this, that experiment has no population.** 58 of 77 open tasks can never receive a pack
carrying any file information, so an arm drawn from them measures nothing about the file list at
all. It is the reason route R1 in that document is restricted to cluster 1.

Verified before filing at the operator's request; this one survived checking unchanged, other
than the glob caveat above, which was missing from the first statement of it.
