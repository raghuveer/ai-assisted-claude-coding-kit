---
id: T-20260820-kit-plan-computes-the-ordering-before-re
title: kit-plan computes the ordering before rebuilding the index so the first run is wrong
epic: planning
tier: T2
lang: bash
paths: tooling/kit-plan.sh
state: open
---

## Intent

`kit-plan.sh:23` checks that `.project/index.db` **exists** and refuses if it does not. It never
refreshes it. The ordering is computed from whatever that database already held, the plan file is
written, and only then — at line 454 — does the run rebuild the index from the file it just wrote.

So the plan is derived from the backlog **as of the previous `kit-index.sh` run**, not as of the
task files on disk. Any edit made since that run is invisible to the ordering, and the ordering is
what gets committed.

`score = wu*unblocks + we*escapes + wt*tier`, so the input this most often loses is `blocked_by` —
which is the one field an operator edits *specifically* to change the ordering.

## Reproduced 2026-08-20 in an isolated clone, not argued

A clone with its remote removed, planned twice first so the baseline was settled and
`plan_stale:default` was clear. One `blocked_by:` line was then added to a task pointing at a
probe task, and `kit-plan.sh` was run **once**, as an operator would:

| step | probe task | `plan_stale:default` |
|---|---|---|
| baseline, settled | score 2.0, rank 71 | clear |
| add `blocked_by` → run `kit-plan.sh` once | **score 2.0, rank 71 — unchanged** | **1** |

The edge did not count. A second run converges.

**Found on the live repository first**, where it mattered: the fifth blocker was added to
`T-20260808-trial-the-kit-on-one-unfamiliar-brownfie`, and
`T-20260819-a-finding-whose-subject-no-longer-exists` planned at **score 2.0, rank 27** — an
`unblocks` count of zero for a task another task was, by then, waiting on. The second replan put
it at **score 5.0, rank 4**. Two invocations, no edit in between, two different committed plans.

## It is not silent, and the notice is not a fix

`#tasks_digest` is stamped from the pre-rebuild database; the rebuild recomputes it from the
post-edit one; the mismatch sets `plan_stale:default`, and `STATUS.generated.md` says *"The plan
for `default` was computed from a different backlog… Re-run `kit-plan.sh` to refresh it."*

That notice is correct and its remedy works. **The defect is that it is only ever reached by
writing a wrong plan first.** A staleness notice exists for a plan that has gone stale since it
was computed — using it to report a plan that was stale *at the moment it was computed* makes the
signal mean two different things, and the one it was built for is the weaker of the two.

An earlier draft of this task described the defect as silent. That was wrong, and the correction
is the reason the severity here is what it is.

## Acceptance criteria

- [ ] The ordering is computed from the current task files. The obvious shape is to rebuild before
      planning, the way line 454 already rebuilds after.
- [ ] One invocation converges. After a task edit, a single `kit-plan.sh` produces the same plan
      that a second consecutive run would, and `plan_stale` is clear afterwards.
- [ ] **The rebuild-before cannot silently be skipped.** Line 454's rebuild is checked and aborts
      the run on failure; a rebuild that fails before planning must do at least as much, since
      planning would otherwise proceed against a database known to be wrong.
- [ ] `plan_stale` keeps meaning only *"the backlog moved after this plan was computed."* Whatever
      lands must not leave the notice as the mechanism by which a first run is corrected.
- [ ] A check that can fail, in the shape this defect actually takes: settle a fixture, edit one
      `blocked_by`, run the planner **once**, and assert the edge counted. A test that runs the
      planner twice passes on the unfixed code and is vacuous.
- [ ] `--packs` is unaffected. It deliberately does not replan and must not start rebuilding
      anything before reading the plan file, or it stops being the non-destructive recovery path
      that `T-20260820-task-context-has-no-branch-for-a-missing` depends on.

## Notes

Found 2026-08-20 while validating the ordering before starting
`T-20260819-a-finding-whose-subject-no-longer-exists`, after the same task's rank moved 27 → 4
across two replans with no edit between them.

Adjacent but different: `T-20260818-nothing-reviews-the-plan-so-a-wrong-orde` is about nobody
*reading* the ordering. This is about the ordering being wrong before anyone reads it.
`T-20260801-kit-plan-has-no-notion-of-prerequisite-w` is about the scoring having no notion of
prerequisite work at all; this one is about the scoring not seeing the prerequisites it does
model.
