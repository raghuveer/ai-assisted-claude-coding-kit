---
id: T-20260812-commits-vanish-between-rev-list-and-the-
title: Commits vanish between rev-list and the trailer report with nothing saying so
epic: measurement
tier: T3
lang: bash
paths: tooling/kit-status.sh, tooling/kit-trailers.sh, tooling/kit-index.sh
state: open
---

## Intent

On a real adoption the trailer-discipline line and `git` disagree, and **nothing reports the
gap**. Measured 2026-08-12 on `sharkdp/fd`, 2005 commits:

| | |
|---|---|
| `git rev-list --count HEAD` | 2005 |
| `git rev-list --count --no-merges HEAD` | **1577** |
| trailer report: non-trivial | 1420 |
| trailer report: trivial, excluded | 53 |
| **accounted for** | **1473** |
| **unexplained** | **104** |

The report reads *"1420 of 1420 non-trivial commits carry no `Task-Id` (53 trivial commit(s)
excluded per `git.trivial_pattern`)"* — internally consistent, confidently worded, and it
silently omits 104 commits that `--no-merges` counted.

**This may not be a defect in the counting.** There are plausible innocent causes: commits
touching no indexed path, commits filtered by `paths_unusable`, an empty-tree commit, a
different revision range between the two readers. **The defect is that the number does not
reconcile and nothing says so** — a denominator that quietly loses 6.6% of its population is
the shape this repository has been bitten by repeatedly, most recently as `0 / 0 via:kit`.

## Why it matters

Trailer discipline is the adoption signal an operator reads first on a brownfield repo. If its
denominator is wrong, "1420 of 1420" is wrong in a way that looks precise. And the same
population feeds `commits_total` / `commits_untagged` in `meta`, so anything derived from those
inherits the discrepancy.

## The change

**Diagnose before fixing.** The first task is to account for the 104, not to make the numbers
match — forcing agreement without knowing the cause would hide it.

Then, whichever it turns out to be:

- if the omission is correct, the report **states the exclusion and its reason**, the way it
  already does for the 53 trivial ones;
- if it is not, the counting is fixed and a fixture pins it.

Either way the invariant holds: **every commit in the range is accounted for in exactly one
bucket, and the buckets sum to the range.**

## Acceptance criteria

- [ ] The 104 are explained, in the task, with the query that identifies them.
- [ ] `kit-status.sh` reconciles: counted + excluded (by named reason) = the range it walked,
      and it says which range that is.
- [ ] A fixture with a commit of each excluded kind — merge, trivial, no indexed path, whatever
      the diagnosis turns up — proves each lands in exactly one bucket. Not a total that happens
      to match; **each kind placed**.
- [ ] Removing any one exclusion reason makes the reconciliation fail. A sum that cannot fail
      is decoration.
- [ ] `meta.commits_total` and `commits_untagged` agree with the report, asserted.

## Notes

Filed 2026-08-12 from the first execution of the trial protocol
(`docs/TRIALS/2026-08-12-fd-throwaway.md`, finding T-5). Not found by three review rounds on the
protocol, nor by the kit's own conformance suite — the fixture has 28 commits and no merges, so
the discrepancy cannot appear there. **A 2005-commit subject surfaced it in one line of output.**
That is an argument for a fixture with merge commits regardless of what the diagnosis finds.
