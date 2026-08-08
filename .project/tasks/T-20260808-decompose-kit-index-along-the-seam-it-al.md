---
id: T-20260808-decompose-kit-index-along-the-seam-it-al
title: Decompose kit-index along the seam it already documents
epic: portability
tier: T3
lang: bash
paths: tooling/kit-index.sh
state: open
---

## Intent

One file concentrates the defects. Measured over 2026-08-08, a day of thirteen substantive
fixes and four criticals:

    fixes touching tooling/kit-index.sh     10 of 13
    criticals found in it                    4 of 4

It is roughly 900 lines carrying fourteen embedded awk programs, and it is simultaneously the
ingest seam, the git trailer parser, the task frontmatter parser, the co-change builder, the
SQL generator and the state derivation layer. `tier.rule` already floors it at T3 on the
grounds that the indexer is where a silent wrong answer is most expensive — which the day's
evidence confirms rather than merely asserts.

**The seam to split along is already written in the file's own comments.** Sections 1-3 turn a
SOURCE into SQL; section 4 derives current state from that SQL and knows nothing about where
it came from. The file says that split is what makes an alternative backend a matter of
replacing one producer. The boundary is real, documented and load-bearing — it just is not a
file boundary.

## Why this is worth doing, stated honestly

Not because the file is long. Because every defect class that hurt today crossed the seam:

- The `?` and `core.quotepath` defects were INGEST producing names the DERIVATION could not
  match. Two halves of one file disagreeing about what a path is.
- The tier.rule arity bypass was a VALIDATOR checking a different token than the CONSUMERS
  used — again two halves of one file, with a `sed` between them nobody accounted for.
- The provenance critical was a WRITER guarded while the DERIVATION was not.

Each is the same shape: two parts of one file holding different assumptions, with no interface
between them to state the assumption once.

## Acceptance criteria

- [ ] Split along the documented seam, not by line count. Ingest producers on one side,
      derivation on the other, with the SQL text as the interface — which it already is.
- [ ] Behaviour is byte-identical, proven by the fixture fingerprint. `EXPECT_HEAD` and
      `EXPECT_SEED` are the strongest asset this repository has for a change of this kind:
      the derived index must not move by a single byte. If it moves, the decomposition changed
      something, and that must be found rather than re-pinned.
- [ ] Each part gets its own `tier.rule` floor. Today the whole file is T3, which means a
      typo in a comment carries the same ceremony as the derivation. Floors that reflect the
      real risk are cheaper to live with and therefore more likely to be honoured.
- [ ] The conformance suite still passes on all three platforms, and CI is green BEFORE and
      AFTER, so the comparison is against a known-good baseline. It first went green on all
      three at `de2e1d6`.
- [ ] No behaviour change is smuggled in. If a defect is noticed during the split, file it and
      fix it separately — a refactor that also fixes things cannot be verified by fingerprint.

## Notes

This replaces an earlier and worse framing. The first analysis concluded the problem was the
implementation language and recommended considering a Python port; checking the classification
properly showed only 4 of 13 fixes were purely attributable to shell, while 10 of 13 were in
this one file regardless of language. The concentration is the signal. A port would move the
defects, not reduce them, unless the decomposition happens first.

Do not start until CI has been green at least once on the commit being built from, for the
reason above.
