---
id: T-20260811-run-the-review-chain-automatically-gate-
title: Run the review chain automatically gate on judgment
epic: agent-contracts
tier: T2
paths: skills, agents, hooks
state: open
---

## Intent

Reviews currently run because someone remembers to run them. That makes the tiering advisory:
a tier that names five reviewers and gets none is a label, not a control. It is also the open
`/goal` question — automate follow-through, or keep it manual.

The resolution: **automate the mechanical reviews, gate on judgment.** Automation applies to
running the chain; the human gate applies to the decisions that need taste or authority —
accepting a finding, closing a task, promoting an accelerator.

## The change

Run the review chain automatically, with composition tied to the risk tier: T1 runs a short
chain, T3 runs the full set including a blind second reader. Surface only what needs a decision.

**The mechanism is already proven.** On 2026-08-10 two reviewers ran as parallel headless
processes with read-only enforced by `--allowedTools`, launched together so the second was blind
to the first, each returning structured findings the recorder ingested without a human. What is
missing is the chain definition and the trigger, not the machinery — so this is cheaper than it
looks.

Two constraints that are settled and must not be re-litigated: reviewers keep `Read, Grep, Glob`
only, and the second reader must be spawned without sight of the first's findings.

## Acceptance criteria

- [ ] Chain composition is derived from the tier, and a T3 cannot run a T1 chain.
- [ ] Median human interventions per completed task falls, with no rise in escaped defects —
      both measured, not assumed. The second half is the guard: this is worthless if it trades
      quality for latency.
- [ ] The blind second reader is genuinely blind, asserted rather than intended.
- [ ] A reviewer that fails to return valid structured output is reported as a gap, not silently
      treated as a clean review.
- [ ] The human gate still fires for closing a task and accepting findings.

## Notes

Filed 2026-08-11 from R-12. Depends on the structured findings contract (`b1e13e4`) — an
automated chain that produced prose nobody recorded would be the open-circuit failure again, at
higher cost.

Interacts with the review split task: the compliance pass is a chain member and is eligible for
a cheaper capability.
