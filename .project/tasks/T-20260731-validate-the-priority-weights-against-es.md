---
id: T-20260731-validate-the-priority-weights-against-es
title: Validate the priority weights against escape data
epic: measurement
tier: T1
state: open
---

## Intent


## Acceptance criteria

- [ ] enough vindicated escapes exist to test the ordering
- [ ] the current weighting is compared against at least one simpler alternative
- [ ] the chosen weights are recorded with the data that justified them

## Notes

From HANDOFF §8. `unblocks x3 + escapes x2 + tier` is defensible, not proven. It was
chosen before any escape data existed. Recalibrate once the findings table has enough
vindicated escapes to test whether the ordering it produces beats the alternatives --
including the null hypothesis that a simpler weighting does as well.


---

## Folded in 2026-08-11: a second routing axis (R-15)

Recalibrating the weights is one half. The other is that a single axis is currently doing two
jobs, which is why T3 gets over-selected.

Split them: **blast radius decides how much process** (which tier), **change type decides which
reviewers** (user-facing, developer-facing, architectural). `skills/tier-classify` implements the
first axis only.

Acceptance to add: the tier distribution shifts toward T1/T2 without a rise in findings escaping
to T3-worthy incidents. Both halves must be measured — a shift alone is just under-tiering.

Depends on the same evidence this task already waits for: enough vindicated escapes in the
finding table to tell calibration from wishful thinking.
