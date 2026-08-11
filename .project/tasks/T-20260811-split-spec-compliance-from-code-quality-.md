---
id: T-20260811-split-spec-compliance-from-code-quality-
title: Split spec compliance from code quality in review
epic: agent-contracts
tier: T2
paths: agents/implementation-reviewer.md
state: open
---

## Intent

`implementation-reviewer` is asked two different questions at once: *is this what we agreed*
and *is this good code*. They fail differently, and a reviewer holding both tends to answer only
the second — code quality is concrete and in front of it, while compliance requires holding the
agreed design in mind and noticing an absence.

Absences are the expensive defects. A missing acceptance criterion produces no bad line to point
at.

## The change

Split into a spec-compliance pass and a quality pass. Mostly a prompt split; the compliance pass
is eligible for a cheaper capability because it is comparison rather than judgement.

Evidence for the split from 2026-08-10: two reviewers with genuinely different lenses, run blind
on the same change, produced **one overlapping finding out of twelve**. Diverse lenses find
disjoint defects; redundant ones find the same defect twice. That is the argument for splitting
by question rather than adding another general reviewer.

## Acceptance criteria

- [ ] Compliance findings and quality findings are separately countable in the finding table —
      which means the split must reach the recorded data, not just the prompt.
- [ ] A change that is good code but does not do what the task asked is rejected by the
      compliance pass. Prove it with a fixture that the current single reviewer passes.
- [ ] The compliance pass names the acceptance criterion it is judging against, per finding.
- [ ] Total review cost for a T2 does not rise: the split pays for itself by running the
      compliance pass at a lower capability.

## Notes

Filed 2026-08-11 from R-10. Depends on the structured findings contract (`b1e13e4`) to be
countable at all — before it, findings carried no field that could distinguish the two.

Interacts with the review-chain automation task: chain composition decides which passes run at
which tier.
