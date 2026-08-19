---
id: T-20260819-legacy-candidate-selection-is-unresearch
title: Legacy candidate selection is unresearched so no modernization subject can be chosen
epic: components
tier: T1
lang: markdown
paths: docs/TRIAL-PROTOCOL.md, docs/design-input
state: open
---

## Intent

`docs/design-input/2026-08-16-artifact-model-and-distribution.md` §6 lists five open decisions.
Four have tasks — overlay form and location, unattended fan-out, the nine pre-summary criticals.
The fifth, **"legacy candidate selection, once availability has been researched"**, has none.

It blocks something concrete. The kit claims to serve three project types, and modernization is the
one it has never seen: `T-20260731-component-model-for-polyglot-and-moderni` says in its own Notes
that its field names are *"seeded, not earned — from two described projects and one architect's
experience, not from a project this kit has run"*, and the instruction is to bind them to a real
one. The disposition vocabulary added on 2026-08-18 — reuse / improve / re-architect — carries the
same caveat. **None of that can be earned without a subject, and no subject can be chosen without
this.**

## Acceptance criteria

- [ ] Candidate subjects are enumerated with what makes each suitable or not: language mix, size,
      commit count, age of history, whether the business pain is articulable, and whether anyone
      can answer questions about it.
- [ ] **Availability is established, not assumed.** A subject nobody can grant access to, or whose
      owner has not agreed, is not a candidate — `docs/TRIAL-PROTOCOL.md` §0 already requires the
      owner's agreement, and discovering its absence after selection wastes the selection.
- [ ] The choice states what it will and will not exercise. A subject with no data-migration
      dimension cannot earn the disposition vocabulary; one with no articulated business pain
      cannot exercise the check that pain was addressed rather than technology swapped.
- [ ] An open-source candidate is considered alongside any client one, and the trade recorded: a
      public subject can be written about and re-run by others; a client subject is realistic and
      unpublishable. The kit's own evidence discipline is worth more when the evidence can be
      shown.
- [ ] The outcome is a **decision with a named subject or a recorded conclusion that none is
      available yet** — the second is a legitimate result and must not be left as an empty
      criterion that looks like work in progress.

## Notes

Filed 2026-08-19 from a sweep of every ADR and design document against the backlog, which is where
this surfaced — it had been sitting in a §6 list since 2026-08-16 with nothing pointing at it.

Tiered T1: it is research and a decision, touching documentation. What it unblocks is expensive;
the task itself is not.

Sequencing: this is **not** urgent before the brownfield trial, which needs an unfamiliar polyglot
subject rather than a legacy one, and is separately blocked. It becomes the critical path the
moment modernization support is worth building rather than describing — which is the state the
component-model task is currently in.
