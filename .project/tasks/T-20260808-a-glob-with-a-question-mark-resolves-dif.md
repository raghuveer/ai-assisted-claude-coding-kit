---
id: T-20260808-a-glob-with-a-question-mark-resolves-dif
title: A glob with a question mark resolves differently on the two floor paths
epic: portability
tier: T3
lang: bash
paths: tooling/kit-index.sh
state: done
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

- [x] `?` resolves the same way on both paths, or it is refused the way `[` and `]` are.
      Refusing is the cheaper answer and matches the precedent already set — a floor that
      means two things is worse than one that is missing and announced — but it removes a
      documented glob character, so decide deliberately rather than by default.
      REFUSED, and the deciding evidence was not the cost: making the regex byte-correct
      needs a one-UTF-8-character matcher, which needs hex escapes inside an awk program, and
      macOS ships an awk that does not interpret them. The kit already paid for that lesson —
      T-20260731-remove-hex-escapes-from-awk-programs-so- exists because `'` broke the
      whole index build on macOS. Re-buying it for a character that appears in no shipped
      example, no doc example and not once in this project's own profile is a bad trade.
- [x] Whichever is chosen, the comment at `globre` stops claiming agreement it does not have.
      It currently carries an explicit ASCII-only caveat pointing at this task; that caveat is
      the interim honesty and must not outlive the fix.
      Replaced. It now says what remains — `*` and literal text — and states agreement without
      the caveat, because the character that broke it can no longer reach the function.
- [x] A conformance case with a non-ASCII path defends the claim, so the next reader is not
      relying on prose. Note that `core.quotepath` must be false for the touched-files half to
      reproduce — git renders a non-ASCII path as `"src/Ã©.go"` by default, which is a
      THIRD way these two sources can disagree and is worth checking while you are here.
      Checked, and it was not merely a testing obstacle -- it was the larger half of the
      defect, and after review it turned out to have a residual of its own.

      Neither of `kit-index.sh`'s two git invocations passed `-c core.quotepath=false`, so
      EVERY non-ASCII path was recorded in the `touches` edges and in the co-change graph under
      an octal-escaped name matching no glob and no other reader:

          before:  declared-paths floor T3, touched-files floor (none)
                   node recorded as  f:"src/Ã©.go"
          after:   declared-paths floor T3, touched-files floor T3
                   node recorded as  f:src/ß.go

      **The flag does not do what the first version of this claimed.** It suppresses escaping
      for bytes above 0x7F AND NOTHING ELSE: git quotes unconditionally for a double quote, a
      backslash or a control byte, all legal filenames on a POSIX checkout. Measured through
      the unmodified indexer -- `src/i\j.go` still arrived as `"src/i\j.go"`, node recorded
      under the mangled name, touched-files floor NONE, against a `src/** T3` rule. Same
      mechanism, same silence, same under-tiering direction, and author-controllable.
      Those paths are now DROPPED, counted in `meta.paths_unusable`, and named by
      `kit-status.sh` -- missing and announced, which is the rule this repository already
      applies to a refused rule.

      So the honest scope of the claim: the two sources agree for every path git will report
      unescaped, and a path it will only report escaped produces no floor from either source
      and says so. The conformance case covers the non-ASCII path through BOTH git invocations
      (co-change included, with `hub_pct` raised so the fixture actually produces a co-change
      row), the quoted path via nested tree objects, and the `?` refusal.

## Outcome

Five changes:

1. `?` is refused in a `tier.rule` glob, where `[` and `]` already are.
2. `globre` returns "" for any glob it cannot translate faithfully and the caller skips that
   rule, so the guarantee lives in the function rather than in a guard seventy lines away at
   its single caller. The `?`-to-`.` mapping is gone rather than dead.
3. Both git invocations pass `-c core.quotepath=false`, so a non-ASCII path is recorded as
   itself in the touches edges and in co-change.
4. A path git reports escaped anyway is dropped, counted in `meta.paths_unusable`, and named
   in `STATUS.generated.md`.
5. `templates/project-profile.md` documents the glob vocabulary and what is refused, since
   that is the file someone reads while writing a rule.

One thing verified rather than believed along the way: an early transcription of `globre` into
a test harness produced `^src/.&go$`, which looked like a live escaping bug. Extracting the
function from the file verbatim showed `^src/.\.go$` — correct. The `&` was mine. Worth
recording because the fix that a wrong reproduction would have prompted would have broken
something that worked.

The template edit moved the fixture, and FINGERPRINT caught it for the second time today. The
cause was established first — exactly one blob, exactly the intended lines — and only then were
both pins moved.

## The T3 review, run 2026-08-08

Run before closing. `implementation-reviewer` (sonnet) **REVISE**, `security-reviewer` (opus)
**REVISE**, 7 findings recorded. Both rungs in parallel, second reader blind.

**The second reader disproved a comment I had just written.** "The flag makes git emit the path
as it is" is false; it covers bytes above 0x7F only. Reproduced independently before acting --
a backslash path still arrives quoted, still lands as a mangled node, still loses its floor
silently. Fixed by dropping and announcing, and the comment now states the limit.

**The first reader proved a half of the fix had no coverage.** The flag was added to BOTH git
invocations and the conformance case only reached the touches one: reverting the co-change flag
alone left the step green. It also showed why the obvious fixture could not test it -- with
`hub_pct` at 20 and a two-commit fixture, every file is filtered as a hub and the cochange
table comes out empty, so the assertion would have passed against anything. The fixture now
raises `hub_pct` and commits two files together.

Both also flagged the dead `?`-to-`.` mapping still sitting in `globre`, guarded only from a
distance. Removed, and `globre` now refuses rather than translates.

Worth recording as evidence FOR the change: the second reader differentially fuzzed the
extracted `globre` against SQLite GLOB over **1,708,826 glob/subject pairs with zero
disagreements**, including combining characters, astral-plane characters and embedded quotes
and backslashes -- with 16,955 positive matches, so the comparison is not vacuously empty.
That is what makes dropping the ASCII caveat a measured claim rather than an assertion.

Mutation-verified four ways after the rework: reverting the touches flag, reverting the
co-change flag, removing the `?` refusal, and removing the quoted-path drop each turn the step
red on their own.

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
