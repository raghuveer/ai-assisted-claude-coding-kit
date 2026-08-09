---
id: T-20260809-conformance-cannot-run-one-step-so-every
title: Conformance cannot run one step so every mutation proof costs a full suite
epic: validation
tier: T1
lang: bash
paths: tests/conformance.sh
state: open
---

## Intent

`tests/conformance.sh` runs all 35 steps or nothing. Proving that one control can fail — the
discipline this project relies on — therefore costs a full run.

Measured on 2026-08-09: **8-10 minutes per run on this laptop, roughly fifteen runs in one day,
about 2.5 hours of pure waiting** to prove twelve controls across two tasks. The session's own
figures make the split plain: 16.5 hours wall against 4 hours of API time. Most of that gap was
not thinking or reviewing. It was waiting for steps 1-34 to pass again so step 35 could be
observed failing.

The cost is wall-clock rather than tokens — the suite is bash, not a model — but it changes
behaviour, and that is the real damage. Mutation proofs get batched into overnight runs instead
of taken one at a time, guards get written hastily because a mistake costs ten minutes to
discover, and two mutations were mis-written on 2026-08-09 in exactly that way: one skipped its
run silently, one ran an UNMUTATED suite to a green result that read as proof.

## The change

A way to run one step, or a named subset, by name or pattern:

    KIT=$PWD WORK=$W bash tests/conformance.sh --only 'a reviewer.s findings reach'

Everything else stays. The full run remains what CI executes and what the fingerprint is computed
from — a filtered run must never be mistakable for a whole one.

## Acceptance criteria

- [ ] A single step can be selected and runs in seconds rather than minutes.
- [ ] A filtered run is UNMISTAKABLE for a full one: the tally says so, the exit code stays
      meaningful, and the FINGERPRINT section either does not print or prints as not-computed. A
      partial run that looks like `35 passed, 0 failed` is a worse defect than the slowness it
      cures — see `docs/LESSONS.md` §1.
- [ ] A pattern matching no step FAILS rather than passing vacuously with zero steps run. The
      obvious implementation returns success for "nothing ran", which is the exact shape this
      repository keeps shipping.
- [ ] Steps that depend on a shared fixture built by an earlier step either still work under
      filtering, or are named as unfilterable. Silent breakage under `--only` would make the
      feature a liar in the one place it is trusted.
- [ ] CI keeps running the full suite. The filter is a development-loop tool, not a CI mode.

## Notes

Filed 2026-08-09 from the session cost review. Not a correctness defect — the suite is right, it
is just all-or-nothing — but the highest-leverage change to the development loop itself, because
it makes the mutation discipline cheap enough to use routinely rather than in batches.

Deliberately T1: additive, revertible, and it changes no derived number.
