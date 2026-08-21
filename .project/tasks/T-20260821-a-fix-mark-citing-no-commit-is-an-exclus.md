---
id: T-20260821-a-fix-mark-citing-no-commit-is-an-exclus
title: A fix mark citing no commit is an exclusion with no evidence at all
epic: feedback-loop
tier: T2
lang: bash
paths: tooling/kit-resolve.sh, tooling/kit-index.sh, tooling/kit-status.sh
state: open
---

## Intent

`kit-resolve.sh` treats `--commit` as **optional** — *"Optional still; but if given, it must name a
commit in this repository."* The refusal it added was for a SHA that does not resolve, on the
grounds that *"a mark citing a SHA that does not exist reads as substantiated and is not."*

**A mark citing nothing at all reads as substantiated too, and there is no refusal for it.**
Measured 2026-08-21 on this repository: **40 of 61** fix marks carry no `fixed_commit`. Two thirds
of every exclusion from the criticals gate rests on nothing the kit can re-read.

The indexer already walks every non-empty `fixed_commit` and reports
`finding_fix_commit_missing` when the evidence has left the history. That walk cannot see these 40:
there is nothing to walk. **The strongest control the kit has over dispositions is applied to a
third of them.**

## Why this is filed rather than fixed

The obvious move — require `--commit` — is a **migration, not a bug fix**, and it is the reason
this is its own task:

- 40 existing marks become non-conforming retroactively. Refusing them at read time re-reds the
  gate for defects that were genuinely fixed.
- Some are legitimately commit-less. A finding against a *document* fixed in the same commit as
  ten others, a finding fixed by deletion, a finding whose fix predates the column.
- `--note` is the only evidence on those 40 and it is free text, so there is no automatic
  upgrade path.

## Acceptance criteria

- [ ] Decide, and record, whether a fix mark must cite evidence. If yes, `--commit` becomes
      required at the **writer** (`kit_findings.py`), so it binds for every caller — the split
      `kit-resolve.sh` already applies to `--reason` and `--by`.
- [ ] The 40 existing marks get a stated disposition: grandfathered and counted, or re-marked.
      Whichever it is, `kit-status.sh` reports the count, because an exclusion resting on nothing
      is exactly the kind of number this project refuses to fold into a total.
- [ ] `kit-status.sh` distinguishes **evidence resolves**, **evidence missing**, and **no evidence
      cited**. Today the middle one is reported and the third is invisible.
- [ ] A check that can fail: a fix mark with no commit, asserted against whatever the decision is.

## Notes

Found 2026-08-21 by an approach review of `docs/adr/0005`. The ADR argued that a superseded mark
whose evidence stops resolving must lapse from the gate, invoking the project's fail-closed rule.
The reviewer pointed out that the argument **does not discriminate**: applied consistently it
condemns these 40 marks and the 9 `unassessable` ones, which the ADR exempted by fiat. That is the
same non-discriminating-argument defect ADR 0004 had to have struck from it.

So the ADR's rule is either wrong or it applies here too, and that question cannot be answered
inside a document about supersession. It is answered here.
