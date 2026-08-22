---
id: T-20260822-every-stop-fires-a-spend-gap-whose-agent
title: Every Stop fires a spend gap whose agent id has no transcript
epic: measurement
tier: T2
lang: bash
paths: tooling/kit-spend.sh, hooks/hooks.json
state: created
---

## Intent

**First measured plugin-mode session, 2026-08-22.** The hooks fire and the recorder works — this
task is about what the working recorder revealed.

Five `spend-gap` events against **one** successful `scope=subagent` row, every gap reading
`no per-agent transcript found for this agent`:

    09:50:17  spend main   +  spend-gap
    09:55:38  spend main   +  spend-gap
    09:58:52               +  spend-gap
    10:00:54  spend main   +  spend subagent (Explore)
    10:00:55               +  spend-gap
    10:01:14               +  spend-gap

The gap carries `agent_id: a240795311a2caf47`. The only per-agent transcript on disk for that
session is `agent-a15dbae039b783dc2.jsonl`. **The id the hook passes is not the id of any
transcript that exists.**

## Why this matters more than a noisy log

`kit-spend.sh` locates numbers at `<project>/<session>/subagents/**/agent-<id>.jsonl`, because no
hook payload carries token usage. If the id does not resolve, there is nothing to cost.

The recorder is behaving **correctly**: it records a gap rather than costing zero, which is the
distinction `docs/TRIAL-PROTOCOL.md` §3 exists to preserve — *"a reviewer that returns nothing
may not have reviewed nothing."* A cost figure with five uncounted firings beside it is honest;
the same figure with them silently dropped would not be.

But for a trial that reports cost, five uncosted firings per one costed subagent is not a usable
signal, and it is the **only** measurement plugin mode adds over the portable path.

## What is NOT yet known, and must not be assumed

- Whether the extra firings are real subagents whose transcripts had not been flushed when the
  hook ran, or firings for something that never had a transcript at all. These have different
  fixes: a timing problem is a retry, a phantom id is a filter.
- Whether the ratio is characteristic or an artefact of three short sessions. **n is 1 session.**
- Whether `Stop` is invoking the recorder twice — once for the main loop, once with an agent id.
  Both a `spend main` and a `spend-gap` land within a second of each other at 09:50 and 09:55,
  which is suggestive and not conclusive.

## Acceptance criteria

- [ ] The cause is established by measurement, not inference: for each gap, whether a transcript
      for that `agent_id` appears on disk LATER. That single check separates timing from phantom.
- [ ] If timing: the recorder tolerates a not-yet-written transcript without either costing zero
      or losing the firing. If phantom: the firing is not recorded as a gap at all, because a gap
      that is always present is a warning people learn to skip.
- [ ] The gap count appears beside any cost figure the kit reports, so a reader can see the
      denominator is incomplete. It must never be possible to read a cost total without it.
- [ ] A check that can fail: a fixture firing the hook with an `agent_id` having no transcript,
      asserting a gap is recorded AND that a later-arriving transcript is picked up.
- [ ] `n` is stated wherever this ratio is quoted. One session is an anecdote.

## Notes

Found 2026-08-22 in the first session ever to run this kit as a plugin. Until then
`CLAUDE_PLUGIN_ROOT` had never been set here and `installed_plugins.json` listed only
`rust-analyzer-lsp`, so no hook had ever fired and `scope=subagent` had **zero** rows all-time.

**This is a prerequisite for the brownfield trial's cost half**, which is the entire delta plugin
mode adds — `docs/TRIALS/2026-08-12-fd-throwaway.md` ran portable and produced no cost data at
all. It is deliberately NOT added to the trial task's `blocked_by`: the trial can run and report
its census, co-change and inventory findings with cost marked UNAVAILABLE, which is what the fd
trial did honestly. It is the cost figures specifically that this gates.
