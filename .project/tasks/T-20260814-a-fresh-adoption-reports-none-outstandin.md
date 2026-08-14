---
id: T-20260814-a-fresh-adoption-reports-none-outstandin
title: A fresh adoption reports none outstanding, all marked addressed, having recorded nothing
epic: measurement
tier: T2
lang: bash
paths: tooling/kit-status.sh, tests/conformance.sh
state: open
---

## Intent

On a repository that has recorded no findings at all, `kit-status.sh` prints:

    ## Outstanding criticals

    - none outstanding (0 critical finding(s) recorded, all marked addressed)

Nothing was addressed. Nothing was ever recorded. The sentence is vacuously true and reads as
reassurance about work that did not happen — on the **first run**, which is the one impression
an adopter forms before they have any reason to distrust the output.

Observed 2026-08-14 by running an analysis-only pass over a real unfamiliar repository (aeon,
617 tracked files, 18 commits) with nothing but the template profile copied in. It is in the
first forty lines of what that repository's owner would see.

## Why it matters

The section exists BECAUSE an empty rendering reads as clean — that is written in its own
comment. It was built so that "no criticals" and "not measured" could not be confused, and it
confuses a third state with both: **nothing has ever been recorded here**. A repository with no
findings and a repository whose findings were all fixed are not the same claim, and the second
is the one being printed.

It is the same family as the escape rate reporting `0 / 0` as a clean result, which this project
already fixed by naming the absent denominator instead of dividing by it.

## The change

Three states, not two, and the third said plainly:

- findings recorded, none outstanding → *none outstanding* (as today)
- findings recorded, some outstanding → the list (as today)
- **no findings recorded at all** → say that, and do not describe them as addressed

Consider whether the trailer-discipline notice already at the bottom of the file is the right
place to say it, since the two have the same cause on a fresh adoption: nothing has been fed in
yet. Two notices saying that separately is worse than one saying it once.

## Acceptance criteria

- [ ] A repository with zero findings does not read as one whose findings were addressed.
- [ ] A repository whose findings were genuinely all marked addressed still says so — the fix
      must not collapse the distinction in the other direction.
- [ ] A fixture covers all three states. The empty case is the one that regressed; the other two
      are what stop the fix over-reaching.
- [ ] The wording is checked by asserting the OUTPUT, not the branch. Two mutations in this
      area have already survived by changing behaviour the test did not read.

## Notes

Filed 2026-08-14 from the analysis-only pass on aeon. That pass wrote nothing to the subject:
a `--no-hardlinks` clone with its remote removed, verified by `kit-preflight.sh --isolated`
before anything ran. See also `T-20260814-the-absent-counter-notice-fires-on-every`, found in
the same forty lines.
