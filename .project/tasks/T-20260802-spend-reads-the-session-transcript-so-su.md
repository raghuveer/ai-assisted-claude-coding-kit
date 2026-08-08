---
id: T-20260802-spend-reads-the-session-transcript-so-su
title: spend reads the session transcript so subagent cost is not measured at all
epic: measurement
tier: T3
lang: bash
state: done
---

## Intent

0.6.0 added spend recording to make estimate-versus-actual computable, and the README
names accelerator amortisation as the one substantive open question. Observed while
running that test on a second project (Go load tester, greenfield, kit v0.7.0,
Windows/git-bash, Claude Code harness): the recorded data does not measure subagent cost,
and it is labelled in a way that makes it look as though it does.

Tier raised from T2 to T3 on discovery: this is not a bookkeeping defect, it is a
measurement that reports confidently wrong numbers -- the same failure class the kit's own
review vocabulary calls fail-open.

## The evidence

Every subagent received the SESSION's `transcript_path`. All nine spend events across a
full design stage carried one transcript id (`6f93ee858382adfc`). Cumulative `tok_out`:

    09:33  researcher          144493   <- arm A researcher stopped
    09:42  approach-reviewer   183077   <- delta 38584
    10:02  researcher          213852   <- an attempt that DIED mid-stream, delta 30775
    10:46  researcher          221301   <- arm B researcher stopped, delta  7449
    10:52  researcher          221301   <- unchanged across a 10KB file write

Against the harness's own per-agent accounting for the same runs:

    agent                 Agent-tool subagent_tokens   kit-spend delta
    arm A researcher                        20620      (no baseline)
    arm A approach-reviewer                 27057      38584
    arm B researcher                        37998       7449

The ordering is INVERTED. The agent that did the most work produced the smallest delta.

## Diagnosis

Subagents have their own transcript files -- the harness exposes one per agent. The hook is
being handed the session transcript, whose `usage` blocks are the MAIN LOOP's. So `tok_out`
has been tracking the operator's own output all along: the 144493 first attributed to
`researcher` was the operator writing a project profile and eight task files before that
agent ever spawned.

The `agent` field is populated from the hook payload and names whichever subagent last
stopped, so each row reads as per-agent data. That is what makes this fail-open rather than
merely incomplete: the table is populated, plausible, and wrong.

`kit-spend.sh`'s header anticipates the shared-transcript case and is honest about
overwriting. What it does not anticipate is that the shared transcript contains none of the
subagent's usage records at all, so neither the row nor a delta between rows carries
subagent cost.

## Acceptance criteria

- [x] Establish what the `SubagentStop` payload actually carries -- whether the subagent's
      own transcript path, an invocation id, or only the session's. This decides whether
      the defect is fixable in the hook or must be reported as a harness limitation.
      ANSWERED below: it carries `agent_id`, and per-subagent transcripts exist at a
      derivable path. The source is fixable; the aggregation is not yet trustworthy.
- [x] If the subagent transcript is reachable, read that instead and key rows on it.
      Keyed on `agent_id`, which is the transcript's identity and is opaque already -- the
      session row keeps the hashed path, because that one names the operator's directories.
- [x] If it is NOT reachable: stop writing per-agent rows. A row labelled with an agent
      name that holds main-loop cost is worse than no row, because it is silently believed.
      Either label it `main-loop`, or record nothing and say why.
      BOTH branches exist. The main loop is recorded and labelled `scope: main` with an
      empty agent; an agent whose transcript cannot be found writes a `spend-gap` event and
      no spend row, which `kit-status.sh` reports as "N subagent run(s) unmeasured".
- [x] Deltas are NOT an acceptable workaround and must not be documented as one -- they
      were tried on the observing project and reproduce the inversion above.
      No delta anywhere. Each row is that transcript's own cumulative total, replaced in
      place; distinct transcripts are summed and never subtracted.
- [x] `Stop` and `SubagentStop` must not both write for the same moment; nine events were
      written for four agent runs.
      They write disjoint keys, and a total identical to the one already recorded is not
      appended at all. Four firings over one agent and one session now produce two rows.
- [x] A subagent that dies on an API error still writes a row. Decide whether that is
      wanted; if it is, retries must be distinguishable from productive work, which the
      current schema cannot do.
      WANTED, and the sweep is what delivers it: a died agent never fires `SubagentStop`,
      so `Stop` sweeps the directory and records whatever transcripts exist. Its tokens were
      really spent and dropping them makes retried work look cheap. Retries are separate
      rows -- each invocation gets its own `agent_id` and its own file -- but WHICH row is a
      retry is not recoverable from the transcript: this dataset carries no error marker at
      all. Distinguishable, not labelled, and better not to claim more.
- [x] `docs/MEASUREMENTS.md` must state how its per-agent table was obtained. The kit
      cannot currently produce one, so anyone reproducing it will assume `kit-spend.sh`
      did and be wrong.
- [x] Whatever replaces this must be validated against a second, independent accounting
      before being trusted -- the inversion above was only visible because two existed.

## Verification, 2026-08-02 (kit repo)

Reproduced independently, which matters because the reporting project and this one are
different codebases on different work.

**The defect is confirmed.** This session spawned two subagents. Its session transcript holds
1708 assistant records and every one is `isSidechain: false` -- no subagent usage is present
at all. Reading it therefore measures the main loop, exactly as reported.

**Per-agent transcripts exist and are reachable.** The harness writes them alongside the
session transcript:

    <project>/<session-id>/subagents/agent-<agent_id>.jsonl
    <project>/<session-id>/subagents/agent-<agent_id>.meta.json

`SubagentStop` supplies `agent_id`, and the filenames match it exactly. The `.meta.json`
additionally carries `agentType`, `model`, `description` and `spawnDepth` -- which would give
the per-agent, per-model attribution the current schema fakes. So criterion 2 is achievable.

**But the totals do not reconcile, and criterion 8 already bites.** Two subagents given
identical prompts and the same model:

    agent                  in    out    cache_read  cache_write   in+out+cw   harness
    a9b9a166e7fa2227c      14    562        50948       140014      140590     43149
    abe3532578ab7728d      14  11269       162391        28740       40023     43125

The harness reports both at ~43k, which is what two identical prompts should produce. The
transcript sums differ 20-fold in `output_tokens` and no subset of the counters reproduces
the harness figure for both rows.

So reading the subagent transcript fixes WHICH ENTITY is measured -- unambiguously better
than attributing main-loop output to an agent -- but it does not yet produce a number that
survives comparison with a second accounting. Fixing the source without settling the
aggregation would replace a wrong number with an unvalidated one, which is a smaller lie of
the same kind.

Next step for whoever takes this: determine what the harness's `subagent_tokens` actually
counts before changing the reader. Until then criterion 3 is the honest position -- stop
writing rows labelled with an agent name.

## Outcome, 2026-08-08

Reworked once the telemetry spike answered what `subagent_tokens` counts. Doing it before
that answer would have swapped a wrong number for an unvalidated one.

**What is read.** `SubagentStop` resolves the stopping agent's own transcript from the
`agent_id` it carries, under `<session>/subagents/**/agent-<id>.jsonl`, and reads that.
`Stop` records the session transcript as `scope: main` and then SWEEPS the same directory,
which is what catches agents whose `SubagentStop` never fired -- workflow subagents, and
agents that died mid-stream. One awk process over every file rather than one per file: 105
transcripts, 5MB, 0.16s, because a hook that costs a second per turn end is a hook the
operator removes.

**What is stored.** The four counters raw, plus `scope`, `model`, `turns` and the final
context size. Not a weighted total: pricing belongs in `kit-status.sh`, where the
multipliers live in one place, and a committed log must not freeze a price list.

**What is reported.** Billing-weighted input-token-equivalents -- input x1, cache-write
x1.25, cache-read x0.1, output x5. Those ratios hold across the Claude family, so the unit
needs no rate card and no per-model configuration to go stale. Main and subagent totals are
printed apart, because the argument for a tiered review pipeline is that reviewers are worth
their tokens, and a single total lets an expensive review hide inside the work it checked.

**The three numbers, on the 105-subagent run this repo has on disk:**

    raw field sum        17,148,335   what the old reader would have priced
    harness aggregate     2,463,029   final context size, blind to work done
    summed output           169,383   work, but only the generated part
    BILLING-WEIGHTED      6,378,878   what was actually billed

**How criterion 8 was met.** Two accountings of the same 105 agents, sharing no code: the
awk reader inside `kit-spend.sh`, and a Python implementation using a real JSON parser and
the same weights `ccmetrics.py` uses. Compared per agent on all four counters and on model
-- 105 rows, **0 mismatches**. Separately, the `context` column sums to 2,462,727 against the
harness's 2,463,029, which is 0.012%: that is the check that we are reading the same records
the harness reads, and pricing them differently on purpose rather than reading a different
file. Both are in `tests/conformance.sh` in miniature, on a fixture whose session and agent
transcripts carry DIFFERENT numbers -- a reader that fell back to the session file would
pass a test that only counted rows.

**What is still not settled, and is not pretended to be.** The weighted figure has no second
accounting of its own; nothing else on this machine reports billed cost. What is validated is
the SOURCE and the arithmetic, not the price list. And the unit counts tokens, not money, so
a project mixing model tiers has its mix printed rather than averaged -- an opus token and a
haiku token are the same size and not the same money. Converting to currency needs a rate
card, which is exactly the thing that dates, so it is deliberately absent.

Rows written before this change are indexed as `scope: legacy` with their agent label
DROPPED. The cost is real; the attribution was the defect. Dropping the label loudly beats
keeping one that is believed.

## Notes

Consequence for the README's central claim: the accelerator amortisation test cannot be
settled on token cost until this is fixed. On the observing project the arms were compared
on verdict, finding count and finding content instead, which is a weaker but honest
substitute.

Supersedes the first version of this task, which diagnosed only the transcript KEYING
problem (rows overwriting each other) and proposed snapshot-deltas as the workaround. That
diagnosis was incomplete and the proposed workaround does not work. Recording the
correction here rather than rewriting history, because the first diagnosis is what the
evidence supported until the third data point arrived.

Filed from a second project rather than from this repo's own development, which is the
independence the amortisation test needs.

Renamed from `T-20260802-spend-rows-key-on-a-shared-transcript-so`, whose slug carried the
first, superseded diagnosis. Safe only because nothing referenced it yet: `kit-task.sh`
derives the id from the title at creation and offers no way to correct it afterwards, and
once a `Task-Id` reaches a pushed commit the id is permanent. That is a real papercut --
correcting a diagnosis is normal, and the id silently keeps the wrong one.
