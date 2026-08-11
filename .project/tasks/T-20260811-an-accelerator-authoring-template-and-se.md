---
id: T-20260811-an-accelerator-authoring-template-and-se
title: An accelerator authoring template and self check
epic: accelerators
tier: T1
paths: templates, agents
state: open
---

## Intent

Several technology and industry accelerators are wanted up front, then improved iteratively.
Written by different people months apart with no shared shape, they will not be
interchangeable, and the promotion ladder will be sorting apples from prose.

`templates/` currently holds `task.md`, the profile and the CLAUDE template — nothing for
authoring an accelerator.

## The change

A template with required sections, plus an authoring agent that drafts against it and runs a
self-check before the draft is offered for review.

The self-check is the part that matters. A template alone is a suggestion; a template with a
check that refuses a draft missing its evidence section is a contract.

**An accelerator entry must carry its evidence**: which project it came from, what it claimed,
and what confirmed it. The README already warns against inventing scar tissue, and an authoring
agent is exactly the thing that would invent it fluently if the template did not demand
provenance.

## Acceptance criteria

- [ ] Two accelerators written months apart by different people are structurally
      interchangeable — same sections, same order, same required fields.
- [ ] The self-check refuses a draft with no evidence section, and refuses one whose claimed
      confirmations do not resolve to real projects. Prove both by writing bad drafts.
- [ ] The authoring agent produces a draft, never a promoted entry: promotion stays human-gated.
- [ ] The template states the line budget, so an accelerator cannot quietly become a context tax.

## Notes

Filed 2026-08-11 from R-08. Interacts with the promotion ladder folded into
`T-20260731-cross-project-accelerator-aggregation` and with
`T-20260731-accelerator-line-budget-and-eviction`, which owns the budget the template must cite.

Sequencing caution recorded in the register and worth keeping: do not mass-produce accelerators
before there is an eval that can tell a good one from a plausible one.
