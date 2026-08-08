---
id: T-20260808-the-readme-argues-zero-mcp-from-a-cost-m
title: The README argues zero MCP from a cost model that no longer holds
epic: portability
tier: T1
paths: README.md, docs/HANDOFF.md
state: open
---

## Intent

Two claims in `README.md` were wrong, and the correction is partly done in the same commit
that filed this. What remains is the measurement neither claim can be made honestly without.

**1. The MCP argument was factually stale.** It read: an MCP server "would charge tool
definitions on every request, forever." Claude Code now defers MCP tool schemas by default
— tool search is on, and only tool names plus server instructions stay resident. Anthropic
puts the saving at over 85% against a five-server setup that would otherwise cost ~55k tokens.
So the sentence the decision rested on stopped being true.

The DECISION is still right, on a better reason, and the README now says that reason: deferral
silently reverts to full upfront loading behind a non-first-party proxy, on some cloud
deployments, and when experimental betas are disabled — none of which a plugin controls. A
component that costs a few hundred tokens on one machine and tens of thousands on another is
one this kit cannot put a resident number on.

**2. The resident cost was an estimate presented as a measurement.** `~1,259` is a hand-built
table in `docs/HANDOFF.md`; the only tooling behind it is a flat `~100 tokens` per skill
heuristic in `validate.py:123`. It sat under a heading reading "Measured on a real greenfield
project, not estimated", and was divided by 220,336 to produce "0.57% of one task" — but
220,336 is context size, not billed cost, as this repository established on 2026-08-08. Two
units, so the ratio meant nothing.

## Acceptance criteria

- [ ] Measure the resident cost rather than estimating it. `claude --plugin-dir . plugin
      details coding-kit` and a `/context` reading are the obvious routes; `INSTALL.md` already
      points at the first. Record the method next to the number.
- [ ] Express it against something in the same unit. If it is compared to a task at all, the
      task figure must be billing-weighted, which the kit can now produce per agent.
- [ ] Re-check the MCP paragraph against the docs at the time of writing, and date it. The
      cost model moved once; it will move again, and an undated claim about a moving target
      is the thing that just went stale.
- [ ] Decide whether `validate.py`'s flat per-skill heuristic should stay. A number that
      exists only to be quoted, and is never checked against a real one, is the shape of the
      defect this task is about.

## Notes

Found by research on 2026-08-08, and worth recording that the kit's own work is what made it
detectable: the mixed-unit ratio was invisible until the spend rework established that the
harness per-agent figure is context size rather than cost.

The correction to both claims is already in the README as of the commit that filed this. What
is NOT done is the measurement, which is why this stays open rather than being filed closed.
