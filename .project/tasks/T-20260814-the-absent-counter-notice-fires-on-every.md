---
id: T-20260814-the-absent-counter-notice-fires-on-every
title: The absent-counter notice fires on every repo with no event log and prescribes a rebuild that cannot help
epic: measurement
tier: T3
lang: bash
paths: tooling/kit-index.sh, tooling/kit-status.sh, tests/conformance.sh
state: open
---

## Intent

`kit-status.sh` prints, on a freshly built index:

    > **Mark-failure counters are ABSENT from this index, not zero.** It was built
    > before they existed, so whether any mark failed to apply is unknown here. Delete
    > `.project/index.db` and run `kit-index.sh`.

The index was built seconds earlier by the current indexer. **The stated cause is false and the
prescribed fix cannot work** — deleting and rebuilding produces the same absent keys.

`finding_orphan_marks`, `finding_id_collisions` and `finding_ambiguous_marks` are written in the
awk `END` block at `kit-index.sh:903-905`, which sits inside

    if [ "$SRC_EVENTS" = ndjson ] && [ -f "$EV" ]; then

so a repository with no `.project/events.ndjson` never gets them. That is **every fresh
adoption**, and the notice is therefore guaranteed on first run. Observed 2026-08-14 on aeon.

## This is a regression, and its shape is already filed twice

Introduced 2026-08-13 fixing the opposite defect: those counters were read with `${x:-0}`, so a
stale index asserted that no mark had failed to apply. Distinguishing absent from zero was
right. Asserting WHY it is absent was not — the code cannot know, and it guessed the one cause
that makes an adopter delete a good index.

`T-20260812-the-empty-spend-notice-asserts-a-cause-i` is the same defect in the spend notice.
This is the second instance, written by the same hand after that one was filed, which makes it
a pattern rather than a slip: **a notice may report what is missing; it may not narrate why.**

## The change

Two candidate shapes, and they are not exclusive:

- **Write the counters unconditionally.** They are counts of events processed, and zero events
  processed is a true zero — not an absent value. This is the smaller change and it makes the
  notice unreachable on a fresh adoption without weakening the stale-index case, which is what
  the guard was actually for.
- **Say only what is known.** If the keys really are missing, report that they are missing and
  what that means for the numbers above. Do not name a cause, and do not prescribe a rebuild
  unless the rebuild would change something.

Prefer the first if the second is only reachable through the first being wrong.

## Acceptance criteria

- [ ] A fresh adoption with no event log does not tell the operator their index is stale.
- [ ] A genuinely stale index — one built before these keys existed — is STILL reported. The
      fix must not restore the fail-open it replaced; a fixture proves both directions.
- [ ] No notice in `kit-status.sh` asserts a cause it cannot compute. Sweep the file rather than
      fixing this instance: LESSONS §4, and this is the second occurrence of the shape.
- [ ] Whatever is printed, following its instruction changes the output. A remedy that leaves
      the message identical is not a remedy.

## Notes

Filed 2026-08-14 from the analysis-only pass on aeon, in the same forty lines as
`T-20260814-a-fresh-adoption-reports-none-outstandin`. The pass wrote nothing to the subject.

The wider lesson is about where this was found. Five review rounds on the code that produced
this notice — two implementation, two approach, and the fixture work between them — did not see
it, because every one of them read the repository the kit was built in, where
`events.ndjson` has existed since day one. **Running it somewhere else found it in twenty
minutes.** That is the argument for the trial chain, made by the cheapest possible version of a
trial.
