---
id: T-20260815-an-empty-tracked-file-is-reported-as-bin
title: An empty tracked file is reported as binary
tier: T2
lang: bash
paths: tooling/kit-entry.sh, tests
state: open
---

## Intent

`kit-entry.sh` classifies a file as binary with `grep -qI . -- "$f"`, which needs a line containing
at least one character. An empty file, or one of only blank lines, produces no match and is counted
under `skipped binary` with no row in `entry-facts.tsv`.

An empty `__init__.py`, a `.gitkeep`, a placeholder module -- all are tracked files that vanish from
the census under a label saying they were unreadable. The reconciliation still balances, which is
what makes it quiet.

Found by the final implementation review, 2026-08-15.

## Acceptance criteria

- [ ] A zero-byte tracked file gets a census row with `lines 0` and is not counted as binary.
- [ ] A file of only blank lines does the same.
- [ ] A genuinely binary file is still detected and counted.

## Notes

Filed 2026-08-15. The test for binary should be the presence of a NUL byte, not the presence of a
matching line: `grep -qI` conflates "no text" with "not text".
