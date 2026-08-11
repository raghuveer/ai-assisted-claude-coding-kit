---
id: T-20260811-a-retro-artefact-that-closes-the-kaizen-
title: A retro artefact that closes the Kaizen loop
epic: reporting
tier: T2
lang: bash
paths: tooling/kit-status.sh
state: open
---

## Intent

The improvement loop exists as an intention. There is no artefact that closes it: nothing
periodically asks *which agents earned their cost, where did rework come from, is the tier
distribution calibrated.*

Most of the inputs already exist and are unused. `kit-status.sh` produces escape rate by tier
over two provenance populations. The `finding` table now carries a `summary`, so a finding can
be read rather than counted. `ccmetrics.py` and a 2026-07-29 `baseline/` capture sit in the
workspace wired to nothing.

## The change

A retro command producing a periodic summary — per project and, later, across projects — of
tier distribution, findings by agent, rework, and cost signals.

**The kit collects no cost data.** It reads what the harness or the operator's own tooling
already exports and correlates it with kit-side events: tier chosen, agents run, findings
raised. If that export is unavailable the retro **degrades to kit-side data rather than
failing** — a retro that refuses to run without telemetry is a retro that never runs.

Adopt the register's two guard conditions as policy rather than prose:

- **No efficiency gain is accepted if escaped defects rise.**
- **Any agent producing zero findings across a full retro period is a candidate for removal**,
  not for a better prompt.

## Acceptance criteria

- [ ] Each retro produces at least one concrete change to an agent prompt or the risk-tiering
      table — a retro that changes nothing is a report, not a loop.
- [ ] It runs and produces a useful artefact with no external telemetry present.
- [ ] Every figure carries its n, and a figure from one project is never silently combined with
      another's.
- [ ] The two guard conditions are checked mechanically, not remembered.
- [ ] A period with no data says so, rather than printing zeroes that read as measurements —
      the `0 / 0 via:kit` defect must not be reproduced here.

## Notes

Filed 2026-08-11 from R-16, **scoped to wiring existing metrics** rather than building
measurement machinery, because most of it already exists unused.

The last acceptance criterion is not hypothetical: on 2026-08-10 the escape-rate report printed
`0 / 0 via:kit` across four tiers and 58 tasks with nothing saying the column was empty.
