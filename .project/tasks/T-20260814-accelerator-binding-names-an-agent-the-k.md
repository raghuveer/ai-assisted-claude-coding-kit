---
id: T-20260814-accelerator-binding-names-an-agent-the-k
title: Accelerator binding names an agent the kit does not ship
epic: agent-contracts
tier: T1
lang: bash
paths: docs/HANDOFF.md, agents, accelerators/industry
state: open
---

## Intent

`HANDOFF.md` §4.5 describes how accelerators bind to agents:

> `resolve --agent coder` returns the stack profile; **`--agent compliance-auditor` returns the
> industry obligations**; `--agent orchestrator` returns nothing.

The kit ships eight agents and **`compliance-auditor` is not one of them**: `adr-scribe`,
`approach-reviewer`, `coder`, `documenter`, `implementation-reviewer`, `researcher`,
`security-reviewer`, `tester`.

So the industry half of the accelerator model is documented against a consumer that does not
exist, which is why `accelerators/industry/bfsi.md` is loaded by nothing. The technology half
binds to `coder`, which is real, and works.

## Why it matters more than a stale sentence

The binding rule is the token lever — an accelerator is small at rest and large when loaded, and
`resolve --agent` is what keeps it out of the orchestrator window. A documented binding with no
agent behind it means the industry axis has never been exercised, and the first project that
declares a domain will discover that rather than being told.

It also leaves `domain` in the finding table feeding an accelerator nobody reads.

## The change

A decision, not a detail:

- **Ship the agent.** A compliance/obligations reviewer is a real reviewer role — read-only like
  the others, fired when a change touches regulated data, returning the same
  `verdict / narrative / findings` contract. It gives the industry accelerator a consumer and the
  `domain` axis a purpose.
- **Or bind the obligations to an agent that exists** — most plausibly `security-reviewer`,
  which already fires on high-stakes changes — and correct §4.5.

The second is smaller and the first is more honest to the design. Whichever is chosen, the
document and the shipped set must agree afterwards.

## Acceptance criteria

- [ ] No document describes a binding to an agent the kit does not ship.
- [ ] `accelerators/industry/bfsi.md` has a named consumer, or is marked as having none.
- [ ] A conformance step fails if any `--agent <name>` named in documentation or in accelerator
      binding has no corresponding file in `agents/`. The check is the point: this was prose
      agreeing with prose for four versions.

## Notes

Found 2026-08-15 by comparing the shipped agent set against the binding model, while reviewing
external reference material for ideas worth adopting. Nothing about the reference material is
required to fix it — the inconsistency is entirely internal and was visible the whole time.
