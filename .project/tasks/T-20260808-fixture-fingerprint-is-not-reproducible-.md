---
id: T-20260808-fixture-fingerprint-is-not-reproducible-
title: Fixture fingerprint is not reproducible across line-ending settings
epic: portability
tier: T2
lang: bash
paths: tooling/kit-init.sh, tests/conformance.sh, .gitattributes
state: done
---

## Intent

`tests/conformance.sh` step FINGERPRINT fails on a Windows/git-bash checkout:

    head    ea3722c5578fa1be9b6d41bb459b3e99707a8ae5
    FAIL  fixture is reproducible (HEAD == 53000060db14454d607a4db4bacef4e758ed0382)

The fixture is fully determined — fixed author and committer dates, fixed content — so the
check's own comment concludes that a mismatch means the fixture drifted. **It has not.** The
fixture-building section of `conformance.sh` is byte-identical to the commit that pinned
`EXPECT_HEAD` (`e61b829`), `templates/project-profile.md` has not changed since, and building
the seed commit with the kit at `e61b829` and at HEAD produces the same tree and the same
commit id. The mismatch is environmental, and the message points away from that.

## Diagnosis

`kit-init.sh` copies the profile template into the fixture with `cp`, which bypasses git's
filters, and the fixture sets `core.autocrlf false`, so whatever bytes are on disk are what
gets committed. `.gitattributes` pins `*.sh`, `commit-msg`, `*.py` and `*.sql` to `eol=lf`
and says nothing about `*.md`, so on a `core.autocrlf=true` checkout the template is CRLF:

    working tree, this machine   4662 bytes   raw blob 2d84418e0ee0e1d44b485489f07f938c44b1d7d6
    committed / LF checkout      4575 bytes   raw blob f6f1015c25f99da9f68839b695a0de8dabd00cb8

87 bytes, one per line. A different blob makes a different seed tree, a different seed
commit, and a different HEAD 27 commits later.

Confirmed by running the same suite at the same commit against an LF checkout
(`GIT_CONFIG_KEY_0=core.autocrlf GIT_CONFIG_VALUE_0=false git clone`): HEAD comes out
**53000060db14454d607a4db4bacef4e758ed0382**, and the suite is **23 passed, 0 failed**.

So the check is not wrong about there being a difference. It is wrong about what kind, and
it is measuring something it did not intend to: the pin is a fingerprint of the operator's
line-ending configuration as much as of the kit.

## Acceptance criteria

- [x] The fixture produces one commit id on Linux, macOS and a `core.autocrlf=true` Windows
      checkout of the same commit. Decide whether that is achieved by pinning `*.md` to
      `eol=lf`, by making `kit-init.sh` normalise what it copies, or by having the fixture
      normalise what it commits — and record which, because they protect different things.
      The first two. `.gitattributes` pins `*.md text eol=lf`, which covers everyone who gets
      the kit through git; `kit-init.sh` writes the profile through `tr -d '
'` instead of
      `cp`, which additionally covers a kit unpacked from an archive, where no git attribute
      is in force. The third was rejected: normalising inside the fixture would make the test
      pass while leaving real user repositories seeded with CRLF, which is the failure and
      not the symptom.
- [x] Do NOT re-pin `EXPECT_HEAD` to the value this machine produces. The comment above it
      already says: update it deliberately, never to make a red run go green. That advice is
      correct and this task is a test of it.
      `EXPECT_HEAD` is untouched. The suite now reaches `53000060db1445...` on its own.
- [x] On mismatch the check must say what differs, not only that something does. A bare hash
      inequality, plus a comment asserting that a mismatch means drift, sent this
      investigation through the template history, the kit-init history and a two-version
      fixture rebuild before reaching the blob. Printing the seed commit id alongside HEAD
      would have named it immediately.
      The seed commit is now pinned separately and printed on mismatch, with the two cases
      spelled out: seed matching means this script moved, seed differing means a file
      `kit-init.sh` commits is not byte-identical. Both branches were exercised by tampering
      with each pin in a scratch copy — an error path that has never run is not a diagnostic.
- [x] `kit-init.sh` copying a text file with `cp` is the mechanism here, and it copies into
      real user repositories too, not only fixtures. Establish whether a CRLF
      `project-profile.md` reaches a Windows user's repo and travels to their Linux
      colleague, and whether anything downstream cares. Report the answer even if it is "no".
      IT DID, and the reproduction is in this repo's own history: every `.md` here was CRLF
      on disk, and `kit-init.sh` copied those bytes verbatim into `.claude/project-profile.md`.
      Whether anything downstream cares is platform-dependent, and the honest answer is worse
      than "no". `kit_cfg` strips only `[ 	]` from a value, not `
`. It did not bite here
      because the gawk in git-bash strips CR on input -- demonstrated: a deliberately CRLF
      profile yields `paths.state` as 8 clean bytes. That is a property of this awk build, not
      of the code, and it is the reason the CR-counting in this investigation had to be redone
      with `tr`. What happens on an awk that does not strip CR could not be tested on this
      machine, so it is stated as a hazard rather than a result: a CRLF profile written on
      Windows and read on a colleague's Linux checkout would leave `
` on every value.
      Filed as T-20260808-kit-cfg-strips-space-and-tab-from-a-valu rather than fixed here --
      `kit-lib.sh` is read by every script in the kit and deserves its own tier and its own
      review, not a one-character rider on a test fix.

## Outcome

`kit-init.sh` writes the profile with `tr -d '
'` rather than `cp`; `.gitattributes` pins
`*.md` to LF; the FINGERPRINT step pins and prints the seed commit so a mismatch says which
half moved.

The convincing test is not that the suite is green — it is that the suite is green on a
checkout whose profile template was deliberately CRLF-ified. That is the exact condition that
produced `ea3722c5...` before, and `kit-init.sh` now normalises it away at the copy, so the
fixture reaches the pinned `53000060db1445...` from a corrupted source. `.gitattributes`
alone would have hidden the defect on this machine while leaving it live for anyone
installing from an archive.

## Notes

Shares a root cause with T-20260808-vocabulary-drift-check-reports-drift-tha: the same CRLF
working tree, reaching a different test by a different route. One `.gitattributes` line may
close both.

The two failures together are an argument for the check rather than against it — this is
exactly the platform difference it was built to catch, and it caught it. What failed is the
diagnostic, not the detector. CI covers Linux and macOS, so the only platform where this
could go unnoticed is the one it appeared on.
