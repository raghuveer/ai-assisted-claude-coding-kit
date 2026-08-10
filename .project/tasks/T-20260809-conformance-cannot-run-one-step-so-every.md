---
id: T-20260809-conformance-cannot-run-one-step-so-every
title: Conformance cannot run one step so every mutation proof costs a full suite
epic: validation
tier: T1
lang: bash
paths: tests/conformance.sh
state: done
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

- [x] A single step can be selected and runs in seconds rather than minutes.
- [x] A filtered run is UNMISTAKABLE for a full one: the tally says so, the exit code stays
      meaningful, and the FINGERPRINT section either does not print or prints as not-computed. A
      partial run that looks like `35 passed, 0 failed` is a worse defect than the slowness it
      cures — see `docs/LESSONS.md` §1.
- [x] A pattern matching no step FAILS rather than passing vacuously with zero steps run. The
      obvious implementation returns success for "nothing ran", which is the exact shape this
      repository keeps shipping.
- [x] Steps that depend on a shared fixture built by an earlier step either still work under
      filtering, or are named as unfilterable. Silent breakage under `--only` would make the
      feature a liar in the one place it is trusted.
- [x] CI keeps running the full suite. The filter is a development-loop tool, not a CI mode.

## What was built

`step` became a selector rather than a printer: each body is wrapped `if step "name"; then …
fi`, so an unselected step costs nothing. The step list is read back out of the file by a sed
self-parse rather than kept in a table beside it, because a second copy is a copy that drifts.

Steps that share a fixture carry a chain name as `step`'s second argument — `spend` (two steps)
and `fixture` (the nine from `deterministic fixture` to `FINGERPRINT`). Selecting a chain member
runs that chain from its start through the selected step and announces how many were pulled in,
so nothing runs without the fixture it reads.

A new step, **the step filter cannot report a vacuous pass**, asserts the filter's own
guarantees in CI: no-match exits 2, `--list` names the steps, a filtered run says PARTIAL and
never prints the full run's tally line, two patterns select two steps, and an unknown argument
exits 2. Criteria 2 and 3 are the "green that means nothing" shape, so they are checked rather
than trusted.

## Measured

Full run on this laptop: **241 s / 42 checks** (the 8-10 min in the Intent was 2026-08-09 under
load; 4.0 min is what it costs today, and the ratio is the point either way). Single steps:
9 s (`via vocabulary`), 29 s (`unknown blocker`), 35 s (`a failed build`). The nine-step fixture
chain via `--only FINGERPRINT`: 42 s.

The fixture fingerprint did not move: `d923228d…`, head `ff40e675…`, byte-identical before and
after, and identical again when produced by the chain alone rather than the whole suite.

## Verified

Six mutations, each red in its own check and green elsewhere:

1. vacuous-match guard removed → no-match run exits 0 with nothing run (2 checks red).
2. PARTIAL tally replaced by the full-run tally → 2 checks red.
3. chain expansion disabled → the subagent step runs without the fixture the spend step
   builds, and fails. This is what makes criterion 4 a claim rather than a hope.
4. unknown-argument guard removed → `--bogus` ignored, 1 check red.
5. a step line the strict parser misses → the parser cross-check refuses the run, exit 2.
6. the nesting sentinel, proved positively by the SKIP it produces.

Two defects were found and fixed during the work, both by the mutations rather than by reading:

- The `--bogus` check was an unfiltered nested run. With guard 4 mutated away it became a full
  suite that re-entered the step that spawned it — an unbounded fork bomb, which is what hung
  the first mutation attempt. Fixed by pairing it with `--only` and by a `KIT_CONFORMANCE_NESTED`
  sentinel that makes a nested run skip the step outright.
- The two-pattern check counted `=== ` headers, which the FILTERED and PARTIAL banners also
  match, so it passed at four when it meant two. It now asserts the selection line.

The mutation harness itself reported all six as SURVIVED on its first run, because `timeout`
resolved to the Windows built-in and no mutant ever started. It now treats "no check ran" as a
harness error rather than a survival — the same lesson as §1, one level up.

## Notes

Filed 2026-08-09 from the session cost review. Not a correctness defect — the suite is right, it
is just all-or-nothing — but the highest-leverage change to the development loop itself, because
it makes the mutation discipline cheap enough to use routinely rather than in batches.

Deliberately T1: additive, revertible, and it changes no derived number.
