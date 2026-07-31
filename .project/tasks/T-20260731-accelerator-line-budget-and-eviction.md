---
id: T-20260731-accelerator-line-budget-and-eviction
title: Accelerator line budget and eviction
epic: accelerators
tier: T2
state: open
---

## Intent


## Acceptance criteria

- [ ] each accelerator declares a line budget and the tooling reports when it is exceeded
- [ ] eviction order is refuted -> stale -> lowest occurrence
- [ ] the size of a version is visible before a project pins it

## Notes

From HANDOFF §8. Every accelerator mechanism currently only adds. An accelerator that
grows monotonically eventually costs more per invocation than the defects it prevents,
multiplied across every project that pins it, and nothing in the system would say so.

docs/DESIGN-NOTES.md §3 makes this a prerequisite for the versioned accelerator library
rather than a follow-up: a central library that improves continuously grows continuously,
so every new project would start heavier than the last.

