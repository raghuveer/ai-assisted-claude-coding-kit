---
id: T-20260808-shrink-the-embedded-awk-surface-by-movin
title: Shrink the embedded awk surface by moving parsing into SQL
epic: portability
tier: T3
lang: bash
paths: tooling/kit-index.sh, tooling/kit-status.sh
state: open
---

## Intent

Fourteen awk programs are embedded in single-quoted shell strings across `tooling/` and
`tests/`. Each is three traps at once, and this repository paid for all three in a single day.

**A quoting trap.** An apostrophe inside the program closes the shell string. Hit twice on
2026-08-08; the second time it took the conformance suite from 27 passed to 13 passed / 12
failed, with `bash -n` blaming a line seventy below the cause.

**A dialect trap.** gawk, BSD awk and one-true-awk differ on hex escapes — already a filed
task, because macOS one-true-awk does not interpret them and that broke the index build
outright — on CR handling, and on whether a regex `.` matches a byte or a character. The
`?`-versus-SQLite-`GLOB` divergence came from exactly that last one.

**An idiom trap.** `index(HAYSTACK, " " x " ")` reads as set membership and is substring
matching. That shipped as a critical: it admitted `kit agent` and `manual unknown` into a
closed four-value vocabulary.

SQLite is already a hard dependency, already does the aggregation, and has none of the three.

## Scope, narrow on purpose

This is NOT a rewrite and NOT a language change. An earlier framing recommended considering a
Python port; the evidence did not support it — only 4 of 13 fixes that day were purely
attributable to shell, and the real concentration was one file, which is
T-20260808-decompose-kit-index-along-the-seam-it-al. This is the smaller, safer half: move
work awk does badly into the engine already present.

Candidates, in rough order of payoff:

- Aggregation and grouping done in awk that SQL does natively.
- Vocabulary membership tests. `IN (...)` is exact by construction, which is precisely what
  `index()` was not.
- Any awk program that exists only to reshape rows before they reach sqlite3.

Explicitly NOT candidates: reading git output, task frontmatter, or agent transcripts. Those
are text streams before any database exists, and awk is the right tool for them.

## Acceptance criteria

- [ ] Count the embedded programs before and after; the number is the metric. Fourteen today.
- [ ] Behaviour byte-identical, proven by the fixture fingerprint — same bar as the
      decomposition task.
- [ ] Each program removed is removed for a stated reason, not to move the count. One that
      becomes harder to read as SQL has made things worse.
- [ ] Nothing moves into SQL that would need string interpolation of user-authored text to get
      there. That trades an awk trap for an injection surface, and the same day produced `fl`
      reaching a SQL literal unescaped.

## Notes

Ordered AFTER the decomposition task, not before. Splitting the file first makes each awk
program's responsibility legible; shrinking first would move code between responsibilities
that have not been separated yet.

Recorded T3, not the T2 it was filed at: it declares `tooling/kit-index.sh`, which `tier.rule`
floors there, and the kit reported `recorded T2, floor T3` on the next reindex. That is the
third time in one day the floor caught a task filed a tier low.
