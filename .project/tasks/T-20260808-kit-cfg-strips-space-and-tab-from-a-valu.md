---
id: T-20260808-kit-cfg-strips-space-and-tab-from-a-valu
title: kit-cfg strips space and tab from a value but not carriage return
epic: portability
tier: T3
lang: bash
paths: tooling/kit-lib.sh, tooling/kit-index.sh
state: done
---

## Intent

`kit_cfg` and `kit_cfg_all` in `tooling/kit-lib.sh` trim a profile value with

    gsub(/^[ \t]+|[ \t]+$/, "", val)

Space and tab, not carriage return. A `.claude/project-profile.md` with CRLF line endings
therefore yields values with a trailing `\r` — `paths.state` becomes `.project\r`, which
names no directory, and `tier.rule` globs stop matching.

Found while fixing T-20260808-fixture-fingerprint-is-not-reproducible-, whose root cause was
that `.md` files were unpinned in `.gitattributes` and `kit-init.sh` copied a CRLF template
into real repositories. Both of those are now closed, so the profile is written LF and this
does not currently fire. It is filed because the defence is one layer thin: an operator
editing the profile in a CRLF editor, or a repository adopted before that fix, reintroduces
it, and every script in the kit reads its configuration through this function.

## Why it has not been seen

The gawk shipped in git-bash strips CR on input. Demonstrated: a deliberately CRLF profile
read through `kit_cfg` returns `paths.state` as 8 clean bytes with no CR. So on Windows the
lenient awk hides the gap, and this repository ran for its whole life with a CRLF profile
without noticing.

**That is a property of one awk build, not of the code.** What a non-stripping awk does could
not be tested on the machine where this was found, so it is a hazard rather than a measured
result — and it is the fail-open direction: a value that survives only because the platform
is lenient reads as correct until it reaches a platform that is not.

## Acceptance criteria

- [x] A CRLF profile produces identical values to an LF one, on an awk that does not strip CR.
      The second half needs a Linux or macOS run — this cannot be closed from Windows alone,
      which is the whole point of the defect.
      **That last sentence was wrong and is corrected here.** gawk takes `-v BINMODE=3`, which
      turns the input translation off and makes it behave like every other awk. The test
      probes for a lenient awk and, finding one, re-runs the kit through a `gawk -v BINMODE=3`
      shim — so the case is exercised on Windows after all. Verified both ways: the test fails
      against the readers as they were and passes against the fixed ones, same harness.
- [x] Audit the other awk readers of user-authored text for the same trim, not just this one.
      `kit-index.sh` parses task frontmatter and `events.ndjson`; task files are `.md` and are
      authored by hand.
      Five trims found, four wrong. `kit-lib.sh` `kit_cfg` and `kit_cfg_all`; `kit-index.sh`
      task frontmatter, and its `tier.rule` glob/tier split. The fifth — `trim()` in the
      indexer's trailer reader — **already carried CR in its class**. So the knowledge was
      one function away from the parser that needed it and did not travel, which is why the
      fix is a per-line CR strip at the top of each reader rather than a fifth trim to keep
      in sync. `events.ndjson` is machine-written by the kit's own hooks and is read by a JSON
      field matcher, not a line trim; left alone.
- [x] A test covers it. A fixture profile written with CRLF, asserting the same parsed values
      as the LF one, fails today on any awk that does not strip CR — and would have caught the
      whole class rather than this instance.
      **Rewritten after review. The first version did not discriminate:** four of five
      one-part reverts left it green, because `tr -d` of every CR in its own assertion deleted the
      artifact under test, and because two of the three readers it named were being cleaned
      upstream by the platform before the reader ever ran. What it now covers, each verified
      by reverting that hunk alone and watching the step go red:
      `kit_cfg_all` (asserted on its own bytes, no pipeline between) and the indexer's
      frontmatter parser (asserted with the line terminator stripped, not every CR).
      What it does NOT cover, stated rather than implied: `kit_cfg`'s single-value path, which
      msys2 `$(...)` cleans before any assertion can see it — the step probes for that and
      prints `kit_cfg leg: masked by $(...) on this shell`; and the carriage return added to `floorof`'s
      trim classes, which is defence behind `kit_cfg_all`'s strip and is unreachable from a
      fixture here because msys2 `sed` cleans `TIER_RULES` upstream. Both are live on a POSIX
      shell and sed; neither is claimed as covered.

## Outcome

Fixed by stripping CR once per input line at the top of each reader, not by widening four
trims. `kit-index.sh` line 194's glob/tier split keeps a widened class as well, because that
value arrives from an environment variable rather than from a line.

**THREE platform leniencies were hiding this, not the two this task originally claimed.** The
third was found by review, and it invalidates the reasoning the fixture was built on:

1. The gawk in git-bash strips CR on input. Known when this was filed.
2. msys2 bash strips a trailing CR in command substitution — text ending CRLF comes back from
   `$(...)` one byte shorter. So `kit_cfg`, which returns a single value that way, came back
   clean even with the broken trim.
3. **msys2 GNU sed strips CR in text mode**, for any script, at any line position. `TIER_RULES`
   is built by piping `kit_cfg_all` through `sed` (`kit-index.sh:156`), so the CR is gone
   before `floorof` ever sees it.

The original Outcome argued that declaring TWO `tier.rule` lines defeated leniency 2 by
reaching an interior line. **That reasoning was wrong** — leniency 3 removes the CR from every
line regardless of position, so one rule or two made no difference, and the `tier.rule` leg
tested nothing. The fixture keeps two rules for a different and now-true reason: leg 1 asserts
`kit_cfg_all`'s own output, where `$(...)` would still clean the last line.

Neither leniency 2 nor 3 exists on Linux.

The damage, made visible by running the pre-fix readers under a CR-preserving awk: task rows
indexed with `tier` = `T1<CR>` and `epic` = `e1<CR>`. Nothing errors. Every `tier = 'T2'`
filter, the escape-rate grouping and the planner's ordering just quietly stop matching — the
under-tiering direction, arriving silently, which is the failure this repository has already
recorded twice.

Recorded T3, raised from the T2 it was filed at, before the work rather than after: the fix
touches `tooling/kit-index.sh` and `tier.rule` puts a T3 floor there, which the kit reported as
`recorded T2, floor T3`. The tier was raised before the work, which is the only order in which
a tier is a control rather than a label.

## The T3 review, run 2026-08-08

Both rungs run, in parallel so the second reader was blind to the first's findings, on the
models `docs/MODELS.md` pins.

- `implementation-reviewer` (sonnet): **REVISE**, 2 findings.
- `security-reviewer` (opus): **REJECT**, 6 findings.

All 8 recorded through `kit-finding.sh` — the first real review this loop has carried.

**Both reviewers independently found the same central defect: the test did not discriminate.**
Independent corroboration is exactly what a blind second reader is for, and it landed on the
one claim in this file that a reader would have taken on trust. The test is rewritten above
and mutation-verified.

The second reader ALSO found a critical fail-open the first did not: `globre` compiles an
unescaped glob, so a `tier.rule` typo makes awk fatal and three of four tasks vanish from the
index while `kit-index.sh` exits 0. Reproduced before filing, as
T-20260808-a-malformed-tier-rule-glob-silently-empt; the unescaped `fl` on the task `INSERT`
and the `--if-stale` amnesia that hides the failure are
T-20260808-an-apostrophe-in-a-tier-rule-breaks-the-. Both are pre-existing and out of scope
here; both sit in the function this change edited.

**The state transition preceded the control** — this task was marked `done` and its trailer
written before any reviewer ran, which the security reviewer raised as a process finding and
which is fair. The trailer is immutable; this section is the correction. The CR fix itself was
judged correct by both reviewers, who read the built index directly and confirmed no CR
reaches any column.

## Notes

Related: T-20260808-fixture-fingerprint-is-not-reproducible- and
T-20260808-vocabulary-drift-check-reports-drift-tha, which are the same byte reaching two
other readers. This is the third, and the only one that reaches user-authored configuration
rather than files the kit ships.

Deliberately not fixed as a rider on those two. `kit-lib.sh` is sourced by every script in
the kit; a one-character regex change there is still a change to the file with the widest
blast radius, and it deserves its own tier declaration and its own review rather than being
carried in on a test fix.
