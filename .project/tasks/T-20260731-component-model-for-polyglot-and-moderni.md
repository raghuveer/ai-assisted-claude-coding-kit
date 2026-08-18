---
id: T-20260731-component-model-for-polyglot-and-moderni
title: Component model for polyglot and modernization projects
epic: components
tier: T3
state: open
---

## Intent

An accelerator binds to an **agent**, which cannot work for a polyglot project:
`implementation-reviewer` reviews both a React UI and .NET services, so binding by agent either
loads every accelerator on every invocation or demands one reviewer per stack. A **component** is
the axis that actually carries a stack, a boundary and a migration story.

**Modernization is the case that makes this urgent, and the kit currently has nowhere to record
it.** Operator input, 2026-08-18, from project experience: modernization efforts tend to upgrade or
swap the *technology* while giving minimal attention to resolving the **business** pain points, and
that is why their success rate is poor. The approach worth supporting instead is a conscious
per-component disposition — **re-use what is valid, improve where warranted, re-architect from
scratch where that is the right answer** — held throughout against **data-migration** consequences,
and settled as a **mutual agreement with the client team**.

The artifact none of the kit's mechanisms produces today is that per-component disposition. It is
what turns "we agreed to keep the billing service" from a conversation into something a reviewer
can check, an ADR can cite, and a later session can be held to.

Full account: `docs/design-input/2026-08-18-authoring-chain-and-review-economics.md` §6.

## Acceptance criteria

- [ ] an accelerator binds to a component, not only to an agent
- [ ] migration relationships express eliminated and newly-introduced, not just source/target
- [ ] field names are taken from a real polyglot project rather than from the design note
- [ ] existing single-stack projects are unaffected
- [ ] a component carries a **disposition** — reuse / improve / re-architect — and the disposition
      is recorded with its **reason** and its **data-migration consequence**, not as a bare label.
      A disposition without a consequence is the decision this task exists to stop being verbal.
- [ ] the disposition vocabulary is **earned, not seeded**. This task's own Notes already refuse
      invented field names, and the three values above come from one architect's experience — the
      same source the Notes caution about. Bind them to the first real modernization project, or
      record that they survived it unchanged.
- [ ] **something checks that the business pain is addressed, not only the technology.** A plan in
      which every component's disposition is "reuse" or "improve" and no stated pain point is
      resolved is the documented failure mode, and it currently passes every gate the kit has.
      `T-20260811-a-scope-challenge-gate-before-the-adr-at` asks "what is the actual pain"; this is
      the check that the answer survived into the plan.

## Notes

Designed in docs/DESIGN-NOTES.md §1 and deliberately not built. The accelerator binding
axis is the agent, which cannot work for a polyglot project: implementation-reviewer
reviews both a React UI and .NET services, so binding by agent either loads every
accelerator on every invocation or demands one reviewer per stack.

Field names are seeded, not earned -- from two described projects and one architect's
experience, not from a project this kit has run. Bind them to the first real polyglot
project rather than to the note.

Additive, not breaking: kit-index.sh reads frontmatter by key lookup and ignores unknown
keys, so an optional `component:` is MINOR.

