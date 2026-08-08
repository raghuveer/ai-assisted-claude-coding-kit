---
id: T-20260808-a-malformed-tier-rule-glob-silently-empt
title: A malformed tier.rule glob silently empties the task index
epic: validation
tier: T3
lang: bash
paths: tooling/kit-index.sh
state: open
---

## Intent

`globre` (`tooling/kit-index.sh:178`) turns a `tier.rule` glob into a regex by escaping
`[.^$+(){}|]`. It does not escape `[`, `]` or `\`. An unbalanced bracket or a `\(` therefore
compiles to an invalid regex, awk takes a **fatal** mid-pass, and the task-frontmatter
ingest dies part way through — leaving the tasks it had already emitted and dropping every
one after.

Reproduced on 2026-08-08. Profile with `tier.rule: src/[ab T3`, four task files each
declaring `tier: T3` and `paths: src/a.go`:

    exit=0
    awk: fatal: invalid regexp: Unmatched [ : /^src/[ab$/
    tasks indexed: 1   (4 expected)
    T-1|NULL|NULL      tier and floor both gone

**`kit-index.sh` exits 0.** The DB is written, its path is printed, and the run reads as a
success. The only signal is one line on stderr, and the conformance step that builds an index
discarded it with `2>&1` until this was found.

`globre` is only reached for tasks that declare `paths:`. Without that, the same typo is
quieter still: every task indexes, and every `tier_floor` is silently NULL — a floor that
does not apply rather than one that fails.

## Why this is T3 and not a papercut

The trigger is a typo in a documented config field, not an attacker. The consequence is that
the tier floor — the control that decides how many reviewers a change gets — stops applying,
and the backlog reads as shorter than it is. `docs/MEASUREMENTS.md` §B.4 already records that
two of three recorded tiers were too low and that under-tiering is the dangerous direction;
this makes the mechanism that was built to catch it fail open, without saying so.

`tooling/kit-index.sh` also carries a T3 floor of its own in this project's profile.

## Acceptance criteria

- [ ] A malformed glob cannot empty or truncate the index. Either escape the remaining regex
      metacharacters in `globre`, or validate the rule and skip it with a `kit_warn` naming
      the rule — but a rule the kit cannot compile must not take the ingest down with it.
- [ ] The task pass fails CLOSED. A non-zero awk exit in that pipeline must reach `kit_warn`
      and a non-zero script exit, the way `run_adapter` already does at `kit-index.sh:84-101`.
      Today the pipeline's exit status is discarded and the build reports success.
- [ ] A conformance step covers both: a profile with an uncompilable glob, asserting the
      index still contains every task and that the run says something. Assert on stderr, not
      only on the DB — the whole defect is that the DB looks fine.
- [ ] Check whether the same shape exists for the OTHER glob source: the shell-side floor loop
      at `kit-index.sh:661-677` feeds the same globs to SQLite's `GLOB`, which has different
      metacharacters and different failure behaviour. Report the answer either way.

## Notes

Found by `security-reviewer` (opus) during the T3 review of
T-20260808-kit-cfg-strips-space-and-tab-from-a-valu, and reproduced independently before
filing. It is pre-existing and was not introduced by that commit — but it sits inside the
function that commit edited, in the dimension that commit claimed to be strengthening, which
is how it came to light.

Recorded as `fail-open|critical` in the findings table.

The blind second reviewer found this and the first reviewer did not. That is the second
recorded instance of the T3 second reader behaving as a COMPLETENESS control rather than a
correctness one — the same result `docs/MEASUREMENTS.md` §C reports from the design-stage
comparison.
