---
name: tier-classify
description: Assign a review tier T0-T3 to a change before spawning any reviewer subagent, based on blast radius, reversibility and ambiguity. Use whenever work is about to start and no tier has been declared, or when a change turns out larger than assumed.
---

# tier-classify

Tiering is the cost lever. Every reviewer spawned without a declared tier is either
wasted spend or a missing control, and you cannot tell which afterwards.

## Axes

Classify on three axes, then take the **highest** tier any axis produces. Tiers do not
average.

- **Blast radius** — how far the change reaches, from `task-context` step 4.
  Unknown radius is not low radius. Unknown reads as at least T2.
- **Reversibility** — can this be undone by a revert alone? Anything touching
  persisted data, published contracts, or auth decisions cannot.
- **Ambiguity** — is the correct behaviour stated in the acceptance criteria, or
  is it being inferred? Inferred behaviour is ambiguity, however confident it feels.

## Tiers

| Tier | Meaning | Verification |
|---|---|---|
| T0 | Mechanical, revertible, single file, stated behaviour | deterministic gates only |
| T1 | Local, revertible, stated behaviour | gates + tests |
| T2 | Cross-module, or reversible only with effort, or partly inferred | gates + tests + wiring proof + one adversarial reviewer |
| T3 | Irreversible, or security/data-integrity relevant, or contested behaviour | all of T2 + independent second reviewer, spawned without sight of the first's findings |

## Project overrides

Read `.claude/project-profile.md`. Repeated `tier.rule:` lines take the form
`<path-glob> <tier>` and set a **floor**, never a ceiling. If the project imports an
accelerator, read the file named by `accelerator.technology:` or `accelerator.industry:`
and apply its floors too. Absent an accelerator, use the table above unmodified.

## Output

Declare the tier, name the axis that produced it, and record it. The `Tier:` trailer on
the resulting commit is what makes escape rate measurable per tier — omitting it does
not save work, it destroys the only evidence that the tiering is calibrated.
