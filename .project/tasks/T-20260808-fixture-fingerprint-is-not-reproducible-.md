---
id: T-20260808-fixture-fingerprint-is-not-reproducible-
title: Fixture fingerprint is not reproducible across line-ending settings
epic: portability
tier: T2
lang: bash
paths: tooling/kit-init.sh, tests/conformance.sh, .gitattributes
state: open
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

- [ ] The fixture produces one commit id on Linux, macOS and a `core.autocrlf=true` Windows
      checkout of the same commit. Decide whether that is achieved by pinning `*.md` to
      `eol=lf`, by making `kit-init.sh` normalise what it copies, or by having the fixture
      normalise what it commits — and record which, because they protect different things.
- [ ] Do NOT re-pin `EXPECT_HEAD` to the value this machine produces. The comment above it
      already says: update it deliberately, never to make a red run go green. That advice is
      correct and this task is a test of it.
- [ ] On mismatch the check must say what differs, not only that something does. A bare hash
      inequality, plus a comment asserting that a mismatch means drift, sent this
      investigation through the template history, the kit-init history and a two-version
      fixture rebuild before reaching the blob. Printing the seed commit id alongside HEAD
      would have named it immediately.
- [ ] `kit-init.sh` copying a text file with `cp` is the mechanism here, and it copies into
      real user repositories too, not only fixtures. Establish whether a CRLF
      `project-profile.md` reaches a Windows user's repo and travels to their Linux
      colleague, and whether anything downstream cares. Report the answer even if it is "no".

## Notes

Shares a root cause with T-20260808-vocabulary-drift-check-reports-drift-tha: the same CRLF
working tree, reaching a different test by a different route. One `.gitattributes` line may
close both.

The two failures together are an argument for the check rather than against it — this is
exactly the platform difference it was built to catch, and it caught it. What failed is the
diagnostic, not the detector. CI covers Linux and macOS, so the only platform where this
could go unnoticed is the one it appeared on.
