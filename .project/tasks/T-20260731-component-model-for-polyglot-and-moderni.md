---
id: T-20260731-component-model-for-polyglot-and-moderni
title: Component model for polyglot and modernization projects
epic: components
tier: T3
state: open
---

## Intent


## Acceptance criteria

- [ ] an accelerator binds to a component, not only to an agent
- [ ] migration relationships express eliminated and newly-introduced, not just source/target
- [ ] field names are taken from a real polyglot project rather than from the design note
- [ ] existing single-stack projects are unaffected

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

