---
id: T-20260811-a-scope-challenge-gate-before-the-adr-at
title: A scope challenge gate before the ADR at T2 and T3
epic: agent-contracts
tier: T2
paths: skills, agents
state: open
---

## Intent

The pipeline is engineering-complete but starts from an **accepted problem statement**. Nothing
interrogates the framing. Rework from building the wrong thing dwarfs every token optimisation
downstream, and no amount of review catches it: a flawless implementation of the wrong feature
passes every gate the kit has.

Verified absent — nothing in `skills/` or `agents/` challenges scope today.

## The change

A gate that runs **before** the ADR is written and asks: what is the actual pain, what is being
assumed, what are two cheaper alternatives, and what is the narrowest useful slice.

Adapt the framing to a services context: scope-and-assumption challenge against the engagement's
constraints, not product ambition. The founder-flavoured version this comes from asks whether an
idea is a ten-star product; the useful version here asks whether the client is paying for
something narrower than what is about to be built.

**Forbid it at T0 and T1.** A scope challenge on a one-line config change is a tax, and a gate
that fires on trivial work is a gate people learn to skip.

## Acceptance criteria

- [ ] The gate runs at T2 and T3 and is refused at T0/T1 — asserted, so it cannot creep.
- [ ] Its output is recorded where a later reader can find it: the alternatives considered and
      why the chosen slice was chosen.
- [ ] It can recommend "do nothing" or "do a smaller thing", and that outcome is a normal
      result rather than a failure.
- [ ] Rework attributable to changed requirements is tracked per engagement, so the gate's value
      is measurable rather than asserted.

## Notes

Filed 2026-08-11 from R-11. The register calls this the largest single waste reduction on its
list and I agree, with the caveat that its value is the hardest to measure — the counterfactual
is work that never happened.

The last acceptance criterion depends on the retro artefact existing; without it this gate's
benefit stays a belief.
