---
id: T-20260808-an-apostrophe-in-a-tier-rule-breaks-the-
title: An apostrophe in a tier.rule breaks the task INSERT and the next run hides it
epic: validation
tier: T3
lang: bash
paths: tooling/kit-index.sh
state: done
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

- [x] `fl` goes through `q()` like every other value on that statement.
      Done. The first version of this note claimed the escaping was unreachable defence behind
      the tier refusal; **the review disproved that by mutation** — reverting `q(fl)` alone,
      with the refusal intact, reproduced the original parse error in full, because the
      refusal validated a different token than the consumers used. After the arity fix below,
      `fl` is drawn from a field matched against `^T[0-3]$`, a closed set of four values, so it
      is defence again — by construction, which is a proof and not a test, and is stated as
      such rather than credited to the conformance step.
- [x] Audit the rest of the generated SQL for the same omission rather than fixing the one
      instance. Every interpolated value that originates in user-authored text is in scope.
      29 SQL-emitting `printf`s audited. `fl` was the only omission. Everything else is either
      `q()`-wrapped inside awk, escaped shell-side with `sed "s/'/''/g"` (the floor loop and
      the adapter fingerprints), or a number under `%d`. The parallel floor path had been
      escaping correctly all along, which is what made this an omission rather than a design.
- [x] A failed build cannot be reported as fresh by the next run. Record the failure in `meta`
      or leave the DB older than its sources — a warning that fires once and then goes quiet
      is worse than one that persists, because the quiet run is the one an agent reads.
      Neither: the corpse is no longer created. The index is built into `index.db.new` and
      renamed into place only on success, so a mid-execution failure leaves the previous index
      byte-for-byte and mtime-for-mtime as it was. The next `--if-stale` then sees sources
      newer than the DB, rebuilds, and fails again just as loudly. A `meta` marker would have
      recorded the failure in the very file the failure had corrupted.
      This also makes the script honour a claim it was already making: the comment above the
      assembly says the whole build happens before the existing index is touched, which was
      true of the assembly and not of the execution.
- [x] A conformance step covers both halves: a profile value containing an apostrophe, and a
      second `--if-stale` run after a failed build asserting that it still says so.
      Both, plus a recovery leg, a three-field bypass case, and an ignore-coverage case.
      Mutation-verified four ways: disabling the two-field arity check turns it red, removing
      the tier-value refusal turns it red, removing the `--if-stale` failure sentinel turns it
      red, and restoring the destructive in-place build turns it red.
      HALF 2 was also rewritten: it had produced its build failure by editing the profile,
      which is a WATCHED file, so `--if-stale` rebuilt for that reason and the assertion passed
      on the fixture rather than on the fix. The adapter is now declared before the good build
      and only then made to fail, so no watched file moves.

## Outcome

    before:  exit=1  Parse error: 8 values for 7 columns
                     index.db PERSISTS, every task tier=NULL
             run 2 --if-stale: exit=0, prints the path, SILENT, tiers still NULL

    after:   exit=0  kit: tier.rule ignored — T3',x is not a tier (T0-T3): src/** T3',x
                     tasks intact, tier column populated, refusal named in STATUS.generated.md
             failed build: index preserved intact, no index.db.new left behind
             run 2 --if-stale: exit=1, same warning, every run until it is fixed

Three changes in `tooling/kit-index.sh`: `q(fl)`; a tier that is not `T0`-`T3` is refused
where the glob refusal already lives, and recorded, so a garbage floor never reaches the
comparison that reports under-tiering; and the build is atomic.

## The T3 review, run 2026-08-08

Run before closing. `implementation-reviewer` (sonnet) **REVISE**, `security-reviewer` (opus)
**REJECT**, 8 findings recorded. Both rungs in parallel, second reader blind.

**Both found the same CRITICAL, and it was introduced by this task's own fix.** The tier-value
validator read the LAST whitespace field as the tier; the splitter downstream cut at the FIRST
whitespace run. They agree on a two-token rule and disagree on everything else, so
`tier.rule: src/** ',x T3` passed validation on its trailing `T3` while both consumers took
the tier to be `',x T3`. Reproduced independently before fixing:

    tier_floor = ',x T3      exit 0, nothing refused, no warning
    STATUS.generated.md: the "Below their tier floor" section GONE ENTIRELY
    same task, honest rule: correctly reported as T0 against a T3 floor

`'` is 0x27 and sorts below `T`, so `tier < tier_floor` never fires. A validator added to stop
a garbage floor reaching the under-tiering comparison instead created the version of that
failure which HIDES rather than reports — the direction the commit message itself named as the
dangerous one.

Fixed by parsing once: the rule is split and validated in the same pass, which emits the
already-split form, so there is no second parse left to disagree. A rule that is not exactly
`<path-glob> <tier>` is refused by name — which also refuses a glob containing a space, whose
mis-split was the same defect arriving by a different route.

Three more, all acted on:

1. `q(fl)` was NOT the unreachable defence this task claimed. Proved by reverting it alone.
   Corrected above.
2. `--if-stale` still went quiet when the failure cause was not a WATCHED file: an
   `ingest.extra` adapter is in neither the mtime list nor the fingerprint loop. A failed
   build now drops an `index.db.failed` sentinel beside the index, checked before the mtime
   comparison and cleared on success — outside the index, because a marker inside it would be
   recorded in the file the failure corrupted.
3. `index.db.new` was not covered by the exact-match ignore, so a kill outrunning the EXIT
   trap left a derived database for the next `git add -A` to stage. `kit-init.sh` now writes
   `.project/index.db*`. That moved the fixture, which the FINGERPRINT check caught — the
   cause was established first (exactly one blob, exactly one line) and both pins were then
   re-pinned deliberately, which is what that check exists to force.

## Notes

Found by `security-reviewer` (opus) during the T3 review of
T-20260808-kit-cfg-strips-space-and-tab-from-a-valu, mapped to ASVS V5.3.4. Pre-existing,
not introduced by that commit. Recorded as `correctness|major` in the findings table.

Not a privilege-escalation finding: `ingest.tasks: <path to executable>` already means a
committed `.claude/project-profile.md` is arbitrary code execution by design, so the profile
is inside the trust boundary. Whether THAT trust model is right for a plugin that runs at
session start in cloned repositories is a program-altitude question the reviewer explicitly
declined to settle from a diff, and it is not this task.
