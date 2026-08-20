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

## A hand-run instance, 2026-08-20 — `docs/design-input/2026-08-20-retro-period-one.md`

The command does not exist, so period one was run **by hand**, deliberately before building it, so
the command has a target shape derived from a real period rather than an invented one. It is not
an acceptance criterion met; it is the specification earned.

**It produced a concrete change**, which AC1 requires of every retro:
`agents/implementation-reviewer.md` gains universal failure mode **(i) — a fix that closes a
finding at its SITE may leave its CONSUMER unchanged.** Earned from a measured instance this
period: a review said *"task-context step 4 has no miss path"*, a recovery command and a status
notice were built, the finding was marked fixed and the task closed — and step 4 still had no miss
path, found by a live session days later. Nobody checked the consumer.

**No change to the risk-tiering table**, and that is a finding rather than an omission: escape rate
needs escapes, and `event.kind='escaped'` has **0 rows and always has**. There is no calibration
evidence, and changing floors without it is what that table's own comment forbids.

**Both guard conditions evaluated:** no agent produced zero findings (all three reviewers raised
some), and no efficiency gain was claimed, so nothing to weigh escapes against.

**What the hand run taught the command**, beyond the ACs already listed:

- [ ] Report **disposition latency** — findings recorded versus dispositioned, and the interval.
      Not currently derivable, and it is the single number that would have surfaced this period's
      real problem: 351 findings recorded against 17 ever dispositioned before it.
- [ ] Say plainly that the retro **cannot see operator error**. Most of this period's lost time was
      mine — an in-flight suite reported as a result, a running script edited, `git checkout` over
      uncommitted work, scripted patches whose anchors silently missed — and no artefact the kit
      produces would catch any of it. A retro that measures only the pipeline reports a healthy
      period and implies coverage it does not have, which is the boundary discipline
      `security-reviewer` already applies to SCA, SAST and DAST.

## Notes

Filed 2026-08-11 from R-16, **scoped to wiring existing metrics** rather than building
measurement machinery, because most of it already exists unused.

The last acceptance criterion is not hypothetical: on 2026-08-10 the escape-rate report printed
`0 / 0 via:kit` across four tiers and 58 tasks with nothing saying the column was empty.
