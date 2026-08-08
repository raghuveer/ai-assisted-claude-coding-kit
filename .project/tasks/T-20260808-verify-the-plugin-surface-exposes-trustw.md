---
id: T-20260808-verify-the-plugin-surface-exposes-trustw
title: Verify the plugin surface exposes trustworthy per-subagent token telemetry
epic: measurement
tier: T2
lang: bash
state: done
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

- [x] Enumerate every surface that reports subagent token/cost, and what each actually counts
- [x] Produce, for one real multi-subagent session, two independent accountings of the same
      subagent's tokens and state whether they agree within a stated tolerance
- [x] Decide and record: is per-subagent attribution trustworthy enough to price reviews on?
      If not, define the fallback (e.g. session-level budget alerting only)
- [x] Cross-reference the outcome into docs/COMPETITIVE-LANDSCAPE.md §5 risk #1

## Findings (spike, 2026-08-08)

Dataset: the 105-subagent deep-research workflow run in this same session
(wf_128d8237-f93). Method in scratchpad/reconcile.py; raw transcripts under
`<session>/subagents/workflows/<run>/agent-<id>.jsonl`.

### The four surfaces, and what each actually counts

1. **Main session transcript** (`<session-id>.jsonl`) -- per-turn `usage` blocks. This is
   what kit-spend.sh reads. **It contains ZERO subagent records** (0 of 347 records are
   `isSidechain`, 124 carry usage, all the main agent's). Subagent cost is structurally
   invisible here. This is the filed defect
   [[T-20260802-spend-reads-the-session-transcript-so-su]], now proven, not inferred.
2. **SubagentStop hook payload** -- carries `agent_id`, `agent_type`, `session_id`,
   `transcript_path`, but NO token usage. Confirmed against kit-spend.sh's own docstring.
3. **Per-agent transcripts** `subagents/.../agent-<id>.jsonl` (+ `.meta.json`) -- the ONLY
   place subagent work is recorded, one file per agent keyed by agentId. Full per-turn
   `usage`. `.meta.json` gives `spawnDepth` and a GENERIC `agentType`
   (`"workflow-subagent"`), not the real role -- so role attribution is lost here.
   All 105 files carry the SAME `sessionId` as the main session (attribution is by
   filename/agentId, not by session).
4. **Harness aggregate** `subagent_tokens` (task-notification) = exact sum of the per-agent
   harness `tokens` field.

### Two+ independent accountings of the same 105 subagents -- they do NOT agree

| Surface / method | Total tokens | What it really measures |
|---|---|---|
| harness `subagent_tokens` | 2,463,029 | final **context size** per agent, summed |
| transcript last-context, summed | 2,462,727 | same thing (matches harness to **0.012%**) |
| transcript **output_tokens**, summed | 169,383 | actual generated **work** |
| kit-spend.sh sum(in+out+cr+cw) | 17,148,335 | cumulative incl. per-turn cache re-reads |

Per-agent spread of harness/output ratio: **5.1x - 215x** (median 14.7x). Agents where
harness == output: **0/105**. Within any sane tolerance, **no two surfaces agree**.

### The revelation

`subagent_tokens` is NOT cost and NOT work -- it is each subagent's **final
context-window size** (input + cache), dominated by cache reads. This is why the original
defect saw two identical-prompt agents both reported at ~43k despite 20x different output:
they ended at ~the same context size. **The harness number is blind to work done.**

### Decision

- Per-agent attribution is **structurally obtainable** (surface 3), but **no off-the-shelf
  number is trustworthy for pricing reviews**: the surfaces measure three different things
  and disagree by up to 215x. `subagent_tokens` must never be treated as spend.
- The only unambiguous, reconcilable per-agent quantity today is **output_tokens** from the
  per-agent transcript.
- **Correct path to real cost**: compute per-agent from surface 3 by weighting each usage
  field by its billing rate (cache_read x0.1, cache_write x1.25, input x1.0, output x~5,
  per model), NOT by summing raw fields (overcounts ~7x vs harness, ~100x vs output) and
  NOT via `subagent_tokens`.
- **Fallback if per-agent cost proves unreliable in practice**: session-level cost from the
  main transcript (complete for the main agent) + coarse budget ALERTING, and use
  `subagent_tokens` only as a context-pressure signal.

### What kit-spend.sh must change (follow-up, do not do blind)

(a) It reads the wrong file -- the session transcript, which holds no subagent data; it must
read the per-agent `agent-<id>.jsonl` files. (b) Even then it must store the weighted cost,
or the raw fields WITH their rates, never a raw field-sum labelled "cost". Feeds
[[T-20260802-spend-reads-the-session-transcript-so-su]].
