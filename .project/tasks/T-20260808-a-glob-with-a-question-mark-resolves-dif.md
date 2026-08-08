---
id: T-20260808-a-glob-with-a-question-mark-resolves-dif
title: A glob with a question mark resolves differently on the two floor paths
epic: portability
tier: T3
lang: bash
paths: tooling/kit-index.sh
state: open
---

## Intent

A tier floor is derived twice, from two engines, and they are supposed to agree: `globre` in
`tooling/kit-index.sh` turns a `tier.rule` glob into an awk regex for the DECLARED-`paths:`
source, and the shell loop near the end of the same file hands the same glob to SQLite `GLOB`
for the TOUCHED-files source.

`globre` maps `?` to `.`. This awk matches `.` as a **byte**; SQLite `GLOB` matches `?` as a
**character**. So the two disagree on any non-ASCII path:

    tier.rule: src/?.go T3
    T-1  declares  paths: src/é.go   ->  floor NONE     (awk regex path)
    T-2  touched          src/é.go   ->  floor T3       (SQL GLOB path)

    'f:src/é.go' GLOB 'f:src/?.go'      -> 1
    "src/é.go" ~ globre("src/?.go")     -> 0

Established by differential fuzzing, not by inspection: `globre` extracted verbatim and run
against SQLite `GLOB` over 3,615 globs × 111 subjects — **401,265 pairs, zero disagreements**
— then one 2-byte subject added, producing **96 disagreements, every one of the `?` shape**,
in both directions (`?` under-matches a multi-byte character, `??` over-matches it).

## Why it matters more on the declared-paths side

`kit-index.sh` argues that the declared-`paths:` floor exists because 7 of 8 open tasks have
no `touches` edges yet — before work begins, the declared floor is the ONLY one available.
That is the side that fails here. `src/?.go` under-tiers a task, it gets one fewer reviewer,
and nothing says so.

It is also platform-split: a UTF-8-aware awk answers differently from this one, so two
developers derive different floors from the same profile. Same family as the CRLF findings
already recorded here.

## Acceptance criteria

- [ ] `?` resolves the same way on both paths, or it is refused the way `[` and `]` are.
      Refusing is the cheaper answer and matches the precedent already set — a floor that
      means two things is worse than one that is missing and announced — but it removes a
      documented glob character, so decide deliberately rather than by default.
- [ ] Whichever is chosen, the comment at `globre` stops claiming agreement it does not have.
      It currently carries an explicit ASCII-only caveat pointing at this task; that caveat is
      the interim honesty and must not outlive the fix.
- [ ] A conformance case with a non-ASCII path defends the claim, so the next reader is not
      relying on prose. Note that `core.quotepath` must be false for the touched-files half to
      reproduce — git renders a non-ASCII path as `"src/\303\251.go"` by default, which is a
      THIRD way these two sources can disagree and is worth checking while you are here.

## Notes

Found by `security-reviewer` (opus) in the T3 review of
T-20260808-a-malformed-tier-rule-glob-silently-empt, by fuzzing the two engines against each
other rather than reading them. The commit under review had claimed the two paths now agree;
that claim was true for `\` — which the same fuzzing confirmed across 401,265 pairs — and not
true in general. Recorded as `fail-open|major`.

Pre-existing: `globre` has mapped `?` to `.` since it was written. What the review changed is
that the divergence is now known and stated rather than assumed away.

Recorded T3, not the T2 it was filed at. `tier.rule` puts a T3 floor on
`tooling/kit-index.sh` and the kit reported `recorded T2, floor T3` on the next reindex --
the under-tiering control catching the task that was filed to fix an under-tiering control.
