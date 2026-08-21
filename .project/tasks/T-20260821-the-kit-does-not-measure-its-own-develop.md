---
id: T-20260821-the-kit-does-not-measure-its-own-develop
title: The kit does not measure its own development because hooks are never registered
epic: measurement
tier: T2
lang: json
paths: .claude/settings.json, tooling/kit-spend.sh, tooling/kit-preflight.sh
state: open
---

## Intent

`hooks/hooks.json` invokes `bash ${CLAUDE_PLUGIN_ROOT}/tooling/kit-spend.sh`, and
`CLAUDE_PLUGIN_ROOT` is set **only under `--plugin-dir`**. Kit development does not run that way, and
there is no `.claude/settings.json` here. So during development the hooks are not quiet — they are
**not registered at all**.

Measured 2026-08-21 on this repository:

| | |
|---|---|
| `spend` rows in `.project/index.db` | **11, every one `scope=main`** |
| `scope=subagent` rows | **0** |
| date range of all 11 | `2026-08-14` → `2026-08-15`, nothing in the six days since |
| `.claude/settings.json` | **absent** |

**The cost is not hypothetical and it is large.** On 2026-08-21 a T3 review chain plus an ADR review
ran four subagents against this repository, together roughly **440k subagent tokens** — the most
expensive measurement opportunity the project has had — and produced **zero** spend rows. The
period-one retro had already recorded that *"the kit can measure this and does not, on itself"*; this
is that, with a number.

## Scoped to spend only. The guard is deliberately excluded.

`hooks.json` registers three things. This task registers **one**.

`kit-guard.sh` must NOT be self-hosted here, and the reason is a rule this project already learned:
**never read — or in this case, be governed by — a control you are still changing.** Registering it
would make `kit-guard.sh` guard the very edits that change `kit-guard.sh`. The session on
2026-08-21 edited `kit-index.sh`, `kit-resolve.sh` and `kit_findings.py` in sequence; under
self-hosting a bad intermediate save could refuse every subsequent write, or pass silently, and
the failure would look like the harness misbehaving.

`kit-spend.sh` does not have that shape. It **appends** on `SubagentStop`/`Stop`, it cannot refuse a
write, and a broken version loses telemetry rather than blocking work. That asymmetry is the whole
justification for the narrower scope, and widening it later needs its own argument.

## What this is NOT

- **Not a port, and not a step toward one.** This adds a 17th file to the **Claude adapter**
  (`T-20260819-the-claude-adapter-is-16-files-but-nothi` counts the current 16). It measures
  Claude-Code-developed sessions and nothing else. Codex is not a near-term target; the current
  goal is a working head start on Claude Code.
- **Not a substitute for plugin-mode testing.** Those are different configurations, and conflating
  them is what made this gap invisible. Loading the kit into a development session is
  *(agent=Claude Code, kit loaded, subject=the kit)*. The trial task's smoke tests are
  *(agent=Claude Code, kit loaded, subject=a throwaway repo)*. This task changes only the first.
- **Not retroactive.** Six days of development, a T3 chain and four agent runs are gone as far as
  the instrument is concerned. This starts the clock; it does not recover the period, and the next
  retro must say so rather than report a healthy period from a partial series.

## Acceptance criteria

- [ ] `.claude/settings.json` registers `kit-spend.sh` on `SubagentStop` and `Stop`, by a path that
      resolves without `CLAUDE_PLUGIN_ROOT`. **`kit-guard.sh` is not registered**, and the file says
      why, so the omission reads as a decision rather than an oversight.
- [ ] **Proven against a recorded zero**, the way the plugin smoke test was: capture the
      `scope=subagent` count before, run one subagent, capture it after. "The hook fired" is only a
      measurement against a baseline.
- [ ] `kit-preflight.sh --spend` reports live capture in this repository. It asks
      `events.ndjson` before the index, so "the hook never fired" and "the hook fired and nothing
      derived it" stay distinguishable.
- [ ] **It does not double-count under `--plugin-dir`.** A session run with both the local settings
      and `--plugin-dir` must not register the hook twice or write two rows per transcript.
      `spend` totals are cumulative per transcript with last-write-wins, so a duplicate may be
      invisible in the total and wrong per agent — check it, do not assume it.
- [ ] The churn is accepted deliberately: every development session now appends `spend` events to
      the **tracked** `.project/events.ndjson`. `merge=union` handles the merge; the commit noise is
      the cost of the measurement and is stated here so it is not rediscovered as a surprise.
- [ ] A check that can fail. Asserting the file exists is a source-text assertion and is vacuous —
      assert the **behaviour**: a fixture session with the settings registered produces a
      `scope=subagent` row, and one without produces none.

## Notes

Filed 2026-08-21 after the operator asked whether hooks were in place during kit development. They
are not, and the answer had been assumed rather than checked twice before in this project.

The naming trap that hid it: `docs/ADAPTERS.md` is about **ingest** adapters — data sources — not
coding-agent adapters. Nothing in it concerns hook registration, so reading it does not reveal
this gap.

Related and still untested: `kit-review-record.sh --cmd 'claude --plugin-dir …'` has **never
executed**. The four reviewers on 2026-08-21 were spawned through the harness Agent tool instead,
which is a second reason they produced no spend rows and is tracked on
`T-20260808-trial-the-kit-on-one-unfamiliar-brownfie`.
