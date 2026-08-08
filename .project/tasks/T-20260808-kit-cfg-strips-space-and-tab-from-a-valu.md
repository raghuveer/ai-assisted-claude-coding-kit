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
      One step, three readers: the profile through `kit_cfg`, the task frontmatter through the
      indexer's parser, the floor through the `tier.rule` trim. The fixture carries TWO
      `tier.rule` lines deliberately — see below.

## Outcome

Fixed by stripping CR once per input line at the top of each reader, not by widening four
trims. `kit-index.sh` line 194's glob/tier split keeps a widened class as well, because that
value arrives from an environment variable rather than from a line.

**Two platform leniencies were hiding this, not one**, and finding the second changed what
the test had to look like:

1. The gawk in git-bash strips CR on input. Known when this was filed.
2. **msys2 bash strips a trailing CR in command substitution.** Measured: text ending CRLF
   comes back from `$(...)` one byte shorter than it went in. So `kit_cfg`, which returns a
   single value that way, came back clean even with the broken trim — while `kit_cfg_all`
   returns several lines and `$(...)` drops only the LAST one's CR, leaving every interior
   line dirty. Neither leniency exists on Linux.

That is why the fixture declares two `tier.rule` lines. With one rule the value is the last
line, bash cleans it, and the test passes against a broken reader — it would have measured
the accident rather than the code.

The damage, made visible by running the pre-fix readers under a CR-preserving awk: task rows
indexed with `tier` = `T1<CR>` and `epic` = `e1<CR>`. Nothing errors. Every `tier = 'T2'`
filter, the escape-rate grouping and the planner's ordering just quietly stop matching — the
under-tiering direction, arriving silently, which is the failure this repository has already
recorded twice.

Recorded T3, raised from the T2 it was filed at, because the fix touches `tooling/kit-index.sh`
and `tier.rule` puts a T3 floor there. The kit flagged it: `recorded T2, floor T3`. The tier
was raised before the work rather than after, which is the only order in which a tier is a
control rather than a label. **The T3 review rung was not run** — no reviewer was spawned,
because subagents were not requested for this session. So the tier is declared and its control
is not exercised, and saying so is better than a green that implies otherwise.

## Notes

Related: T-20260808-fixture-fingerprint-is-not-reproducible- and
T-20260808-vocabulary-drift-check-reports-drift-tha, which are the same byte reaching two
other readers. This is the third, and the only one that reaches user-authored configuration
rather than files the kit ships.

Deliberately not fixed as a rider on those two. `kit-lib.sh` is sourced by every script in
the kit; a one-character regex change there is still a change to the file with the widest
blast radius, and it deserves its own tier declaration and its own review rather than being
carried in on a test fix.
