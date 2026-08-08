---
id: T-20260808-verify-the-plugin-surface-exposes-trustw
title: Verify the plugin surface exposes trustworthy per-subagent token telemetry
epic: measurement
tier: T2
lang: bash
state: open
---

## Intent

The kit's defensible product is the economics layer -- risk-tiered review priced against
real spend (see docs/COMPETITIVE-LANDSCAPE.md §3). That layer is only as trustworthy as the
per-subagent token numbers it reads. Open question #3 from the 2026-08-08 landscape research:
does the Claude Code plugin surface actually expose per-subagent token/cost telemetry that
survives a second, independent accounting?

The evidence so far says no. The filed spend defect
([[T-20260802-spend-reads-the-session-transcript-so-su]]) found the harness reporting two
identical subagents at ~43k each while their own transcripts differ ~20x, and no subset of
the counters reproduces the harness figure for both rows. Until a subagent-attributed number
can be cross-checked against a second source and agree, the economics layer rests on a number
we cannot defend -- and a populated, plausible, wrong table is worse than an empty one.

This is a spike: determine whether trustworthy per-subagent attribution is *obtainable* at
all from the surfaces available (SubagentStop `agent_id`, per-agent
`subagents/agent-<id>.jsonl` + `.meta.json`, harness `subagent_tokens`). The answer gates
whether forecast/tier-floor economics can be more than coarse alerting.

## Acceptance criteria

- [ ] Enumerate every surface that reports subagent token/cost, and what each actually counts
- [ ] Produce, for one real multi-subagent session, two independent accountings of the same
      subagent's tokens and state whether they agree within a stated tolerance
- [ ] Decide and record: is per-subagent attribution trustworthy enough to price reviews on?
      If not, define the fallback (e.g. session-level budget alerting only)
- [ ] Cross-reference the outcome into docs/COMPETITIVE-LANDSCAPE.md §4 risk #1

## Notes

Do not "fix" kit-spend.sh to read the subagent transcript until this spike settles what
`subagent_tokens` counts -- swapping a wrong number for an unvalidated one is a smaller lie
of the same kind. The acceptance bar is two accountings that agree, not one that looks
plausible.
