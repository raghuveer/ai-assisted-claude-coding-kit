---
id: T-20260801-trailer-discipline-warning-counts-commit
title: Trailer discipline warning counts commits the hook exempts
epic: reporting
tier: T3
lang: bash
state: done
---

## Intent

`git.trivial_pattern` decides which commits need not carry `Task-Id`/`Tier`. Only
`kit-trailers.sh` read it. `kit-index.sh` counted every commit toward
`commits_untagged`, so a repository following the rule exactly still tripped the 20%
threshold and printed **Trailer discipline degraded** forever.

Observed on a real project: 8 commits, 5 of them `chore:`/`docs:` that the commit-msg
hook had deliberately waved through, 3 non-trivial commits all correctly tagged. The
report read "4 of 8 commits carry no Task-Id" and told the operator their derived status
was under-reporting when it was not.

A warning that is always on is one people stop reading -- and this one guards the signal
that makes escape-rate-by-tier meaningful.

## Acceptance criteria

- [x] the counter and the commit-msg hook apply the same `git.trivial_pattern`
- [x] the denominator is commits that were REQUIRED to carry a trailer
- [x] exempt commits still have their trailers indexed -- a `chore:` that does carry a
      `Task-Id` keeps its events
- [x] the excluded count is shown, so the number is legible rather than just smaller
- [x] a stale index written before `commits_exempt` existed degrades to the old behaviour
      rather than dividing by a wrong denominator
- [x] `tests/conformance.sh` still passes

## Notes

Tier T3 by the kit's own floor: `tier.rule: tooling/kit-index.sh T3`.

`commits_total` keeps its meaning (all indexed commits). `commits_exempt` is new, and
`commits_untagged` now means "required a Task-Id and lacked one", which is the only
reading that makes the ratio useful.

Deliberately not widened: `kit-trailers.sh` also exempts `Revert`, `fixup!` and
`squash!` subjects. `kit-index.sh` runs with `--no-merges` so merges never reach the
counter, but those three still would. Left alone rather than silently changing more than
the reported defect.

Verified on a real repo: 8 total, 5 exempt, 0 untagged, warning gone. Conformance 17/17.
