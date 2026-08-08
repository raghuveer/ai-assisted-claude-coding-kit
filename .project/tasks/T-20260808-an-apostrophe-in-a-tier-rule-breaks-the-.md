---
id: T-20260808-an-apostrophe-in-a-tier-rule-breaks-the-
title: An apostrophe in a tier.rule breaks the task INSERT and the next run hides it
epic: validation
tier: T3
lang: bash
paths: tooling/kit-index.sh
state: open
---

## Intent

Two defects that compound, both in `tooling/kit-index.sh`.

**1. `fl` is the only value on the task `INSERT` not passed through `q()`** (`:213`):

    printf "...VALUES('%s','%s','%s','%s','%s','%s',%s);\n", q(id), q(v["epic"]), q(st),
           q(v["tier"]), q(v["lang"]), q(v["blocked_by"]), (fl == "" ? "NULL" : "\047" fl "\047")

`fl` is the tier from a profile `tier.rule`. An apostrophe in it ends the SQL literal early.
The parallel shell-side floor path at `:661-662` already escapes with `sed "s/'/''/g"`, so
this is an omission rather than a decision. Measured with `tier.rule: src/** T3','x`:

    Parse error near line 3: 8 values for 7 columns
    exit 1, warning printed
    index.db PERSISTS, with every task tier=NULL and floor=NULL

The failing statement aborts but the surrounding transaction still commits, so a
plausible-looking index with an empty tier column is written to disk.

**2. The warning does not survive one run.** `--if-stale` (`:110-134`) compares the DB's mtime
against its sources. The half-written DB is now newer than the profile, so the next
invocation — which is what fires at session start — declares it fresh:

    run 1 (full)       -> exit 1, "kit: index build failed; index.db may be incomplete"
    run 2 (--if-stale) -> exit 0, prints .project/index.db, NO warning
                          index still: every tier NULL

One announcement, then silence, over an index whose tier column is empty. Everything
downstream — escape rate by tier, the below-floor report, the planner's ordering, spend
forecasting — reads that as a backlog with no tiers rather than as a build that failed.

## Acceptance criteria

- [ ] `fl` goes through `q()` like every other value on that statement.
- [ ] Audit the rest of the generated SQL for the same omission rather than fixing the one
      instance. Every interpolated value that originates in user-authored text is in scope.
- [ ] A failed build cannot be reported as fresh by the next run. Record the failure in `meta`
      or leave the DB older than its sources — a warning that fires once and then goes quiet
      is worse than one that persists, because the quiet run is the one an agent reads.
- [ ] A conformance step covers both halves: a profile value containing an apostrophe, and a
      second `--if-stale` run after a failed build asserting that it still says so.

## Notes

Found by `security-reviewer` (opus) during the T3 review of
T-20260808-kit-cfg-strips-space-and-tab-from-a-valu, mapped to ASVS V5.3.4. Pre-existing,
not introduced by that commit. Recorded as `correctness|major` in the findings table.

Not a privilege-escalation finding: `ingest.tasks: <path to executable>` already means a
committed `.claude/project-profile.md` is arbitrary code execution by design, so the profile
is inside the trust boundary. Whether THAT trust model is right for a plugin that runs at
session start in cloned repositories is a program-altitude question the reviewer explicitly
declined to settle from a diff, and it is not this task.
