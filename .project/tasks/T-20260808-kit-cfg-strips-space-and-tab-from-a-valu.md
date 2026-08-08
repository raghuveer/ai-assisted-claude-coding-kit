---
id: T-20260808-kit-cfg-strips-space-and-tab-from-a-valu
title: kit-cfg strips space and tab from a value but not carriage return
epic: portability
tier: T2
lang: bash
paths: tooling/kit-lib.sh, tooling/kit-index.sh
state: open
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

- [ ] A CRLF profile produces identical values to an LF one, on an awk that does not strip CR.
      The second half needs a Linux or macOS run — this cannot be closed from Windows alone,
      which is the whole point of the defect.
- [ ] Audit the other awk readers of user-authored text for the same trim, not just this one.
      `kit-index.sh` parses task frontmatter and `events.ndjson`; task files are `.md` and are
      authored by hand.
- [ ] A test covers it. A fixture profile written with CRLF, asserting the same parsed values
      as the LF one, fails today on any awk that does not strip CR — and would have caught the
      whole class rather than this instance.

## Notes

Related: T-20260808-fixture-fingerprint-is-not-reproducible- and
T-20260808-vocabulary-drift-check-reports-drift-tha, which are the same byte reaching two
other readers. This is the third, and the only one that reaches user-authored configuration
rather than files the kit ships.

Deliberately not fixed as a rider on those two. `kit-lib.sh` is sourced by every script in
the kit; a one-character regex change there is still a change to the file with the widest
blast radius, and it deserves its own tier declaration and its own review rather than being
carried in on a test fix.
