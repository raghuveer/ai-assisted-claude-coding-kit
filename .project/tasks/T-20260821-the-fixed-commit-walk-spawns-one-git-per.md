---
id: T-20260821-the-fixed-commit-walk-spawns-one-git-per
title: The fixed-commit walk spawns one git per mark and costs a quarter of every rebuild
epic: measurement
tier: T2
lang: bash
paths: tooling/kit-index.sh
state: open
---

## Intent

`kit-index.sh` re-verifies every `fixed_commit` on every rebuild — the right thing, and the only
evidence check the kit performs today. It does it in a `while` loop, one `git cat-file -e` per mark.

**Measured 2026-08-21 on this repository, not estimated:**

| | |
|---|---|
| full `kit-index.sh` rebuild | **39,249 ms** |
| the `fixed_commit` walk, 21 marks, looped | **9,432 ms** |
| share of the rebuild | **24%** |
| the same 21 through one `git cat-file --batch-check` | **1,930 ms** |
| saving | **~7,500 ms per rebuild, 4.9×** |

The cost is **subprocess spawn, not the check**. Three unrelated operations were timed at 100
iterations each and came out identical — `git cat-file -e` 376 ms, a `grep` of one file 379 ms,
`git rev-parse HEAD:path` 378 ms. Nothing about `git cat-file` is slow; starting a process is.

**It scales the wrong way.** The walk is O(marks), so the check gets more expensive exactly as the
findings record fills up — which is the direction the project is deliberately pushing. At 400 marks
the looped form projects to roughly 150 s on this machine; batched, to about 2–3 s.

This is a rebuild that `skills/task-context` step 1 runs at session start, and that
`kit-plan.sh` runs a second time after writing a plan.

## The change

`git cat-file --batch-check` reads refs on stdin and reports each as present or missing, in one
process. The loop becomes a pipe, and the per-mark result is still per-mark — this is a speed
change, not a semantics change, and that must stay true.

## Acceptance criteria

- [ ] The walk runs in **one** `git` invocation regardless of how many marks exist.
- [ ] **`finding_fix_commit_missing` counts exactly what it counted before.** A batched reader that
      miscounts is worse than a slow one: the count is what `kit-status.sh` reports and what tells
      an operator their evidence has left the history. Assert equality against the looped result on
      a fixture with both present and missing SHAs, not just a total.
- [ ] A SHA that is **malformed**, **empty**, or **ambiguous** is handled the way the loop handled
      it. `--batch-check` reports `<object> missing` on stdout rather than failing, so the exit
      status is no longer the signal — reading it as one would report every mark as present, which
      is the fail-open direction.
- [ ] `^{commit}` peeling is preserved. A `fixed_commit` naming a tag or a tree must not count as a
      commit merely because the object exists.
- [ ] Measured before and after on this repository, both numbers recorded on this task. A
      performance change with no measurement is a claim.
- [ ] Cost is checked on **CI as well as locally**. Spawn cost dominates on Windows and may be
      minor on ubuntu — ubuntu runs the whole 56-step suite in 40 s. If the saving is local-only,
      that is worth knowing and still worth having, but the task should say so rather than imply a
      universal win.

## Notes

Found 2026-08-21 while costing the options for ADR 0006, which needed to know what evidence
verification costs before choosing an evidence model. The answer reframed that ADR — the cheapest
option is the one that adds no per-item spawn at all — and surfaced this as an independent finding
about code that already exists.

**Not blocked by and does not block ADR 0006.** That decision removes the *superseded* citation
entirely; `fixed_commit` is untouched by it and keeps this walk either way.
