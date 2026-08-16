---
id: T-20260815-candidate-and-kit-task-line-counts-can-b
title: Candidate and kit-task line counts can balance across sections
tier: T2
lang: bash
paths: tooling/kit-entry.sh, tests
state: open
---

## Intent

`kit-entry.sh --check` compares two counts so every candidate carries the literal `kit-task.sh`
line an operator would run. Both are unscoped: `ncand` counts every `- [ ]` after the candidate
heading, including ones in later sections such as `## Could not determine`; `nlines` greps the whole
file for `kit-task.sh --title`, including lines outside the candidate section.

So the equality can BALANCE ACROSS SECTIONS. A candidate missing its command line and a stray
command line elsewhere cancel out, and the check passes on a proposal wrong in both places.

Found by the final implementation review, 2026-08-15.

## Acceptance criteria

- [ ] Both counts are scoped to the candidate section.
- [ ] A proposal with a checkbox in a later section is refused, and one with a stray `kit-task.sh`
      line outside the section is refused -- asserted SEPARATELY, since the defect is two wrong
      numbers agreeing and a fixture with one of each would pass a naive fix.

## Notes

Filed 2026-08-15.
