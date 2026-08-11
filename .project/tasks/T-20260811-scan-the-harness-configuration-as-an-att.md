---
id: T-20260811-scan-the-harness-configuration-as-an-att
title: Scan the harness configuration as an attack surface
epic: validation
tier: T2
lang: bash
state: open
---

## Intent

`security-reviewer` and the compliance work cover the code under development. Nothing covers the
**configuration the harness itself runs on**: agent prompts, hooks, MCP entries, tool
permissions, and secrets in settings files.

For BFSI, GovTech and healthcare engagements this is the difference between a productivity tool
and a tool that can pass a client security review — likely the strongest commercial
differentiator available.

## The change

A scan of harness configuration as an attack surface, runnable as a pre-commit or pre-share step
on the kit and on any project overlay.

**Build it as a SEPARATE tool, not a kit feature.** It scans harness configuration generally —
nothing about the job is specific to this kit — and building it inside makes the kit responsible
for a surface it does not own. The kit's interest is consuming its verdict.

**Scope it against what already exists**, because a scanner that re-reports covered ground
teaches people to ignore it. Already covered: `validate.py` checks agent frontmatter, that hooks
use `${CLAUDE_PLUGIN_ROOT}`, and that every tooling script is `100755` in the git index;
conformance asserts no agent is told to run a tool it does not have, and lints the finding
vocabulary against the recorder. **Genuinely new: secrets in settings, the tool-permission
surface, and MCP server entries.**

## Acceptance criteria

- [ ] The kit ships a clean scan report, produced by the tool rather than by hand.
- [ ] A project overlay with a failing scan cannot be synced.
- [ ] The scan detects a planted secret, an over-broad permission and an unexpected MCP entry.
      All three proved by planting them.
- [ ] It reports nothing that `validate.py` or conformance already covers — no duplicate
      findings competing for attention.
- [ ] It runs without network access and without a model.

## Notes

Filed 2026-08-11 from R-14, and answers the register's own open question 4 in favour of a
separate tool.

Note the kit currently declares zero MCP servers, so the MCP half is prospective — worth
building anyway, because the day one is added is the day nobody re-reads the scanner.
