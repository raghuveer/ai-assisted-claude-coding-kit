---
id: T-20260812-an-uninstrumented-project-reports-the-sa
title: An uninstrumented project reports the same cost as a free one
epic: measurement
tier: T2
lang: bash
paths: tooling/kit-status.sh
state: open
---

## Intent

`kit-status.sh:315` gates the whole `## Spend` section on `[ "${SPENT:-0}" -gt 0 ]` with **no
else branch**. When the `spend` table is empty the section does not print at all — so a project
where the hooks never fired and a project that genuinely cost nothing produce **byte-identical
reports**, and neither says which it is.

This is the `0 / 0 via:kit` family: silence read as a result. It is arguably worse, because that
one at least printed zeroes a reader could question.

**Measured here, not theorised.** This repository has **0 spend rows** after twelve days of
heavy use, and `STATUS.generated.md` contains **zero mentions of cost** — no section, no
warning, nothing to notice.

## What this is NOT

**The recorder is not broken.** That was the first hypothesis and it is wrong. Verified by
invoking it directly on a fixture: `kit-spend.sh --transcript … --agent-id A1` recorded one
correct row with all four counters (`10 / 400 / 1000 / 200`) on the first try.

The zero here has a mundane cause: this repository is developed with plain Claude Code and has
no `.claude/settings.json` loading the plugin, so the `SubagentStop` and `Stop` hooks never
fire. **That is expected. The defect is that nothing says so.**

## Scope — one section, not seventeen

`kit-status.sh` has 17 sections gated on a count or a non-empty string. **Sixteen are warnings**,
and a warning that does not fire when there is nothing to warn about is correct behaviour:
unresolved ids, orphan escapes, finding gaps, below-floor, untagged-commit threshold, and so on.

**`Spend` is the only MEASUREMENT among them**, and measurements must report their own absence.
The escape-rate section (line 194) is ungated and always prints, which is precisely why its
empty denominator was visible enough to be found and fixed. Spend has no such luck.

`EST` (line 362) is nested inside the spend block and is correctly conditional on spend
existing; it needs no change.

## Acceptance criteria

- [ ] With an empty `spend` table the report **states that cost was not recorded**, and says the
      likely cause is that the hooks were not active — not merely "0".
- [ ] It distinguishes *uninstrumented* from *measured as zero*. If a reader cannot tell those
      apart from the output alone, the fix has not landed.
- [ ] With a non-empty `spend` table the output is **byte-identical to today's**. Asserted, not
      eyeballed — this is a reporting change and the regression risk is entirely in the path
      that already works.
- [ ] A conformance step covers both branches, and a mutation that removes the empty-case
      message turns it red. A check that only exercises the populated branch cannot fail for
      the defect being fixed.
- [ ] The sweep is recorded: the other sixteen gated sections are warnings and are deliberately
      left alone. State that in the code so the next reader does not "fix" them.

## Notes

Filed 2026-08-12, found while revising `docs/TRIAL-PROTOCOL.md` — the protocol's §0 pre-flight
requires proving spend capture is live before a trial starts, and writing that rule is what
prompted checking whether this repository had any. It did not.

Directly gates the brownfield trial: a trial cannot produce cost figures if the instrument is
silently absent, and the protocol's pre-flight is a procedural workaround for exactly this
defect. Fixing it makes the pre-flight a double-check rather than the only line of defence.

Related: `T-20260812-status-has-no-time-dimension-so-daily-ac` touches the same reporter.
