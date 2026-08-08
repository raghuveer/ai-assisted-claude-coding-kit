---
id: T-20260808-a-repeatable-trial-protocol-for-running-
title: A repeatable trial protocol for running the kit on an unfamiliar project
epic: validation
tier: T2
paths: docs/MEASUREMENTS.md
state: open
---

## Intent

The intent is to try the kit periodically on projects it has never seen, and to compare the
results. Comparison needs a fixed procedure decided BEFORE the first trial, not reconstructed
after the third.

What exists is `docs/MEASUREMENTS.md`: one n=1 record of one greenfield run. It carries a
section called "Methodology warnings for whoever repeats this", which is the seed of a
protocol and is not one — the warnings are attached to a specific run's story rather than
stated as a procedure someone can follow.

## Acceptance criteria

- [ ] A protocol document that a person can execute without having read the run it came from.
      What to record, what to vary, what to hold constant, and what makes a trial void.
- [ ] The unit is fixed and stated: billing-weighted input-token-equivalents (input x1,
      cache-write x1.25, cache-read x0.1, output x5), from the per-agent transcripts. NOT the
      harness's per-agent figure, which is final context size and differed from actual output
      work by 5-215x on a measured run. `docs/MEASUREMENTS.md`'s own table is in the wrong unit
      for exactly this reason and says so.
- [ ] The known-void traps are promoted out of the 2026-08-01 narrative into the procedure:
      - a worktree path in a prompt does NOT isolate a subagent; both agents found and read the
        live repo, and that comparison was void
      - reindex AFTER committing, or the escape mechanism reads as broken
      - registering a finding contaminates any later blind run; use a worktree at a commit
        predating the registration
      - permission denials inside a subagent degrade into partial reads
- [ ] It says what a trial must NOT do to the subject project. See the trial task's constraint:
      these are real codebases and the kit is not to put them in an unstable state.
- [ ] It says how work done during the trial is attributed, which is
      T-20260808-record-how-a-task-was-executed-so-kit-wo. A trial that cannot separate kit
      work from other work produces numbers nobody can interpret later.
- [ ] n is stated on every figure it produces, and a figure from one project is never
      generalised to another without saying so. The existing measurement is n=1 on greenfield
      and is explicitly not a rate card; the protocol must make that the default posture
      rather than a caveat someone remembers to add.

## Notes

Requested by the operator 2026-08-08: the kit is to be tried periodically on projects it has
never been run against, and those trials are expected to produce task inventories and work
carried forward. That makes the protocol a prerequisite rather than documentation of an
already-finished experiment.

Pairs with T-20260808-trial-the-kit-on-one-unfamiliar-brownfie, which is its first execution
and its first real test.
