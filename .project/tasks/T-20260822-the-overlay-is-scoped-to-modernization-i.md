---
id: T-20260822-the-overlay-is-scoped-to-modernization-i
title: The overlay is scoped to modernization in section 4 but is required for all three starting conditions
epic: components
tier: T2
paths: docs/DESIGN-NOTES.md, docs/design-input
state: created
---

## Intent

`docs/design-input/2026-08-16-artifact-model-and-distribution.md` §4 sequences the solution
overlay as a **modernization** prerequisite, with greenfield as the place to prove it:

> Modernization runs through three unbuilt things in order: the solution overlay, then
> `T-20260731-component-model-for-polyglot-and-moderni`, then the modernization delta.

and §4.2 calls brownfield *"finished except for one thing"* — the entry wiring, since closed.

**That scoping is wrong, and two documents already contradict it.**

## Why brownfield needs it too — structurally, not merely usefully

**1. Accelerator selection depends on the overlay, and accelerators are not modernization-only.**
`docs/DESIGN-NOTES.md` §2, which scopes the overlay to nothing at all:

> The overlay names the chosen stack and industry, and that choice is what selects which
> technology and industry accelerators apply.

And design-input §2.2 makes it the head of the import chain:

> Solution overlay names which accelerators apply → `project-profile.md` binds them to paths and
> agents → subsequent changes are recorded as ADRs.

A brownfield project with no overlay therefore has **no defined way to select an accelerator**.
The chain has no head.

**2. A census can describe but not evaluate.** `kit-entry.sh` produces facts anchored to files.
Whether a fact is a *finding* depends on what the target shape is — the baseline design patterns,
the confirmed stack, what the team can maintain. All of that is what the overlay carries (§1.1:
"the overlay is a route, not only a destination"). Without it the census reports what exists and
nothing can say whether it should.

**3. Brownfield is the GENERAL case, so it cannot need less than the special ones.**
`T-20260814-one-entry-mechanism-brownfield-is-the-ge` is completed and its title is the claim:
brownfield is the general case and the other two are its starting conditions. §4 treats the three
as needing different inputs, which is the framing that task rejected.

## What this does NOT change

**§4's ordering argument still stands and is still right.** Prove the overlay against greenfield
first, because greenfield has no derived context — the overlay is the *entire* input, with no
census noise and no argument about whether a finding came from the code or the constraints. That
is about where to DEBUG the mechanism, not about who needs it.

So the correction is narrow: the overlay is a **general prerequisite** whose proving ground is
greenfield, not a modernization-specific artefact.

## Acceptance criteria

- [ ] The overlay's applicability is stated in ONE place and covers all three starting conditions.
      `DESIGN-NOTES.md` §2 already implies this by scoping it to nothing; saying so explicitly is
      what stops §4's reading from being inherited again.
- [ ] The consequence for brownfield is named: what a census can and cannot conclude without an
      overlay, and what an adopter should do when no architect has supplied one — which will be
      the common case, and "then you get no accelerators" is a real answer if it is the true one.
- [ ] Wherever the sequencing is restated, greenfield remains the proving ground and the reason
      is preserved. Losing that would be a worse error than the one being fixed.
- [ ] If §4 is amended rather than superseded, the amendment is visible in the document rather
      than silent — design inputs are dated records of a session, and rewriting one to look
      always-correct is the failure ADR 0005 and 0006 were kept, unedited, to avoid.

## Notes

Raised by the operator 2026-08-22: *"solution overlay is required for brownfield too, as that
gives inputs on what is there, then to understand further by studying code, docs."* Checked
against `DESIGN-NOTES.md` §2 and design-input §2.2 before filing; both support it.

**Blocks nothing yet, and is not added to any `blocked_by`.** The brownfield trial can run without
an overlay — it will simply produce a census that describes rather than evaluates, which is worth
knowing as a trial finding rather than treating as a prerequisite.

The overlay itself is still unbuilt (`DESIGN-NOTES.md` §2 marks it proposed) and remains the
largest unstarted component in the programme.
