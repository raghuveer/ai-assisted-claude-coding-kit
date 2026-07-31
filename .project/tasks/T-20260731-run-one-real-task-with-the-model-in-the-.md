---
id: T-20260731-run-one-real-task-with-the-model-in-the-
title: Run one real task with the model in the loop
epic: validation
tier: T1
state: open
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

- [ ] `claude --plugin-dir .` loads with 5 skills and 8 agents listed
- [ ] `task-context` assembles context for a real task without hand-reading directories
- [ ] `tier-classify` assigns a tier and the assignment is defensible
- [ ] a reviewer emits a `Findings (recordable)` block that `kit-finding.sh --batch` accepts unchanged
- [ ] the commit-msg hook accepts a well-formed trailer set and rejects a stranded one
- [ ] `kit-index.sh` derives the resulting state without a warning

## Notes

