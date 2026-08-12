---
id: T-20260812-the-empty-spend-notice-asserts-a-cause-i
title: The empty spend notice asserts a cause it cannot know
epic: reporting
tier: T1
lang: bash
paths: tooling/kit-status.sh
state: open
---

## Intent

The empty-spend notice added in `2878e3e` says:

> **Not recorded — this is not a measurement of zero.** The `spend` table is empty, which
> **almost always means the kit's hooks were not active** for the work…

It cannot know that. An empty `spend` table has at least three causes:

1. the hooks were not active — the case it names;
2. **the project was just adopted and no work has happened yet** — the common case for a fresh
   `kit-init.sh`, where the message is simply wrong;
3. hooks fired but `kit-index.sh` has not run since, because rows reach `spend` only through
   the indexer (`kit-index.sh:772`) while `kit-spend.sh` writes to `events.ndjson`.

Cause 3 is the sharp one: it is the same mechanism that makes the trial protocol's §0 spend
pre-flight produce a false stop, and it means **a correctly instrumented project reads as
uninstrumented until a reindex.**

Flagged in review by reading, then **confirmed in the field**: the first brownfield trial
adopted a repository, ran no agents, and got a message telling it the hooks were probably not
active. Nothing had been asked of them.

## Why a wrong cause is worse than no cause

The notice exists because silence let "uninstrumented" read as "free". Replacing silence with a
confident wrong diagnosis trades one misleading output for another — and this one is worse in
one way, because it sends the reader to check hooks that are fine. `docs/LESSONS.md` §3: a claim
in prose that nothing verifies.

## The change

Say what is known, then **distinguish the causes the kit can actually tell apart** rather than
guessing between them:

- Are there `spend` events in `events.ndjson` that have not been indexed? Then the answer is
  *"recorded but not indexed — run `kit-index.sh`"*, which is checkable and actionable.
- Is `events.ndjson` free of spend events **and** the project has commits carrying `Task-Id`?
  Then work happened without instrumentation, which is the hooks case.
- Is it a fresh adoption — no tasks, no kit events at all? Then *"no work recorded yet"*, and
  that is not a problem.

The remedy line has the same flaw and must go with it: it prescribes
`kit-spend.sh --transcript`, which **writes a row into the table being measured** and flips the
report. A diagnostic that mutates the thing it diagnoses is not a diagnostic.

## Acceptance criteria

- [ ] The notice never asserts a cause the data does not distinguish. Where it cannot tell, it
      says the possibilities rather than picking the likeliest.
- [ ] A fresh adoption with no work does **not** read as "the hooks were not active".
- [ ] Un-indexed spend events produce the *"run `kit-index.sh`"* message, and a fixture proves
      it by writing an event and not indexing.
- [ ] The suggested remedy does not modify `spend`.
- [ ] All three branches are exercised, and a mutation collapsing any two of them turns the
      step red. One message for three causes is the defect being fixed.

## Notes

Filed 2026-08-12. Raised by the trial-protocol re-review and confirmed by
`docs/TRIALS/2026-08-12-fd-throwaway.md` finding T-3, one hour after the notice was written.

The underlying reporting fix — that an empty measurement must say so at all — was right and is
not in question here. What is wrong is the sentence explaining why.
