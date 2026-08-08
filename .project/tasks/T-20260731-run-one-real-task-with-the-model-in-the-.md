---
id: T-20260731-run-one-real-task-with-the-model-in-the-
title: Run one real task with the model in the loop
epic: validation
tier: T1
state: done
---

## Intent

Load the plugin and take one task from tier-classify through to a trailered commit, so
the skills and agents are exercised through the harness rather than only their scripts
being exercised from bash.

Every defect found on 2026-07-31 lived in a path that had never been executed: the trailer
parser, the enforcement fail-open, four independent breaks in the findings pipeline. None
was found by reading. Until this task runs, the same is true of every skill and agent, and
everything in docs/DESIGN-NOTES.md is gated behind it.

## Acceptance criteria

- [x] `claude --plugin-dir .` loads with 5 skills and 8 agents listed
      Exactly five and exactly eight, all namespaced: `coding-kit:checkpoint`,
      `status-report`, `task-context`, `tier-classify`, `verify-ladder`; and
      `adr-scribe`, `approach-reviewer`, `coder`, `documenter`,
      `implementation-reviewer`, `researcher`, `security-reviewer`, `tester`.
- [x] `task-context` assembles context for a real task without hand-reading directories
      It ran `kit-index.sh --if-stale`, resolved the task path from the index, checked
      `plan_item` for a cluster pack, walked `edge` to depth 3 and joined `cochange` -- and
      when all of that came back empty it reported blast radius as UNKNOWN, NOT SMALL, and
      declined to guess a file, saying that reading the directory to get oriented "is the
      exact failure this skill exists to prevent". The skill held under the condition that
      would have tempted it most.
- [x] `tier-classify` assigns a tier and the assignment is defensible
      T2, on the ambiguity axis, with the reasoning stated: the correct behaviour for
      `attempts <= 0` was inferred rather than written down. It independently found that
      `tier.rule: src/** T2` sets the same floor, that the task was recorded T1 and therefore
      under-tiered, and that both ladder rungs are empty so `verify-ladder` will raise rather
      than waive. It also declined to edit the task file without approval.
- [x] a reviewer emits a `Findings (recordable)` block that `kit-finding.sh --batch` accepts unchanged
      **The loop closed.** `coding-kit:implementation-reviewer` emitted
      `unclassified|major|go|verify-before-ship`, which was piped into the recorder BYTE FOR
      BYTE -- verified with `cat -A` before piping -- and accepted: `recorded 1 finding(s)`,
      exit 0, indexed with class, severity, lang and pattern intact and domain correctly
      empty. This is the first time a finding has travelled from an agent to the table
      without a human retyping it.
- [x] the commit-msg hook accepts a well-formed trailer set and rejects a stranded one
      Under `enforce`: the stranded shape was rejected and the commit count did not move; the
      well-formed one was accepted. **Under the shipped default it is not** -- see the defect
      this run produced, T-20260808-a-freshly-adopted-repo-defaults-to-warn-.
- [x] `kit-index.sh` derives the resulting state without a warning
      Clean: exit 0, empty stderr, and the derived state is right -- task `done` at T2 with
      floor T2, one finding, two `touches` edges, and events `tiered`, `done`, `finding`,
      `checkpoint`, `spend`.

## Outcome, 2026-08-08

Run against a real adoption, not a fixture: a small Go project, `kit-init.sh`, a filled-in
profile with real `commands.*` and a `tier.rule`, one filed task carrying an actual defect
(`Do(fn, 0)` returned nil without calling fn), driven through `claude --plugin-dir` in
headless mode.

**The spend rework was validated live, which was not one of the criteria.** The hooks fired
on their own and recorded seven transcripts:

    scope     agent                                 model            turns  out
    main      (none)                                claude-opus-5    6..16  various
    subagent  coding-kit:implementation-reviewer    claude-sonnet-5  20     14631
    subagent  coding-kit:coder                      claude-sonnet-5  14      2363

Five main-loop rows with the agent field EMPTY, two subagent rows named from the agents
themselves, models recorded, zero `spend-gap` events. Before today those two rows would have
carried main-loop tokens under an agent name. It also confirms `docs/MODELS.md` is honoured
through the harness: the working tier ran on sonnet while the operator ran on opus.

**Three known gaps confirmed as real, in the live harness rather than by reading:**

- `implementation-reviewer` has no Bash and no git, so on an uncommitted change it reviewed
  the final file rather than the diff -- and said so, twice, unprompted. Exactly what
  `docs/MEASUREMENTS.md` B.1 records as "Not fixed: the toolset".
- The reviewer classified a missing-regression-test finding as `unclassified`, which is the
  instructed fallback and the correct behaviour, because the vocabulary still has no class
  for test-coverage defects. Confirms T-20260801-finding-vocabulary-has-no-class-for-test.
- On a freshly adopted repo `task-context` has almost nothing to assemble: no `touches`
  edges, no co-change, no plan. The brownfield degradation the indexer comments describe is
  real, and the skill reports it honestly instead of substituting a guess.

## Notes

