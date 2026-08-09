---
id: T-20260809-a-claim-audit-before-a-task-closes-names
title: A claim audit before a task closes names the test that would fail
epic: feedback-loop
tier: T2
lang: markdown
paths: skills/claim-audit/SKILL.md, docs/HANDOFF.md
state: open
---

## Intent

Across four T3 review rounds on 2026-08-09, the defects were overwhelmingly the author's own
CLAIMS — sentences written confidently in comments and commit messages, never verified, each
surviving until a reviewer built the fixture nobody had:

- "constrained to hex by everything that writes it" — contradicted four lines later in the same
  comment block, and reachable through an ordinary commit.
- "Both writes are CHECKED" — checking reports the failure; it does not prevent it.
- "present in **By scope** and the per-model figures" — a NULL scope made the whole row NULL, so
  5.4M token-equivalents appeared in no figure at all.
- "an agent that QUOTES the format in prose is not harvested" — true only for the fixture's exact
  line arrangement.
- "kit-plan.sh needed no change and that was checked" — the check was of the wrong thing.

Each cost a review round. Reviewers are the expensive instrument, and they were spending their
budget on sentences a cheaper pass could have caught, instead of on the findings only they can
produce — a forged `commit_sha` reaching the report, a NULL-scope spend row vanishing.

## The skill

One pass over a task's diff, immediately before it is marked done. Two questions, no essay:

**1. For every behavioural claim in a comment, commit message or task file: name the test that
fails if this is false.** If no test can be named, the claim is either untested — write the test —
or unnecessary — delete the sentence. "It is obvious" is not a name.

**2. For every defect fixed: where else does this shape appear?** The sweep that did not happen.
A regex-metacharacter defect was filed at breakfast and rewritten twice by evening.

## Why a skill and not a hook

It needs judgement — deciding whether a sentence asserts behaviour or merely explains intent, and
whether a named test genuinely pins it. That is what a model is for, and it is the half of the
work that deterministic tooling cannot do. The mechanical half is filed separately as
`T-20260809-lint-the-kit-for-untrusted-text-interpol`, and the split is deliberate: models for
judgement, deterministic code for data.

## Acceptance criteria

- [ ] Runs against one task's diff and produces a list of claims, each with a named test or an
      explicit "untested" verdict. It must be usable in one pass; a skill that needs a
      conversation will be skipped on the busy tasks that matter, which is the failure mode the
      checkpoint hook already exists to avoid.
- [ ] It reports the second question separately: defect shapes fixed here, and where else they
      occur. A "none found" answer must be distinguishable from "did not look".
- [ ] It does NOT replace the tier's reviewers and must say so where a reader will see it. This
      catches cheap claims early; it does not build fixtures, and every defect a reviewer found
      on 2026-08-09 came from building one.
- [ ] Tested against a known-bad diff. Take the five false claims listed above, feed the actual
      commits that contained them, and assert the audit names them. A control that cannot fail is
      the defect this whole task is about — see `docs/LESSONS.md` §1.
- [ ] Decide where it is invoked from. `skills/checkpoint` is the obvious neighbour, but the
      audit belongs at CLOSE, not at every checkpoint, or it becomes noise and gets ignored.

## Notes

Filed 2026-08-09 alongside the lint, out of the retrospective in `docs/LESSONS.md`. Scoped
deliberately narrow: a general "periodic analysis" skill was considered and rejected, because an
analysis with no specific question produces prose rather than findings, and because a large new
subsystem is exactly what §5 of that document argues against.

Tier T2 rather than T1: it is a control over other controls, its failure mode is silent (claims
pass unexamined), and it changes the close ritual for every task that follows.
