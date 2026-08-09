---
id: T-20260809-a-newly-added-script-is-invisible-to-the
title: A newly added script is invisible to the exec bit gate until the commit that adds it
epic: portability
tier: T1
lang: bash
paths: tests/conformance.sh, tooling/kit-init.sh
state: open
---

## Intent

`tests/conformance.sh:33` checks that every script is `100755` **in the git index**, and the
comment above it explains exactly why the index rather than the disk: git on Windows cannot read
the msys exec bit, so a `chmod` there never reaches the index and the file lands
non-executable on Linux. The check is right.

It has one blind spot, and it is the moment that matters most. `git ls-files` sees only TRACKED
files, so a script that is still untracked is not checked at all. A new script is therefore
invisible to its own gate for the entire time it is being written and tested, and becomes visible
at the instant of `git commit` — which is normally *after* the last local suite run.

Measured, 2026-08-09: `tooling/kit-review-findings.sh` was added, the full suite passed 35/0 on
that tree, and the push turned three CI jobs red — `structure`, and `conformance` on both
ubuntu and macos. The index mode was `100644` against `100755` for all fourteen other scripts.
The local pass was true and incomplete: the file was untracked every time the check ran.

Root cause of the mode itself: the tooling that writes a new file does not set an exec bit, so
this recurs for the next script anyone adds — including an adopter adding an `ingest.tasks`
adapter, which `docs/ADAPTERS.md` invites them to do.

## Acceptance criteria

- [ ] A newly added, still-untracked script is caught before the commit rather than after the
      push. Checking the working tree as well as the index is not sufficient on Windows, where
      the disk bit is unreadable — so the check has to be about what WILL be committed, not what
      the filesystem claims.
- [ ] The existing index check stays exactly as it is. It is correct, its reasoning is recorded,
      and this is a gap beside it rather than a defect in it.
- [ ] A conformance case covers the arrangement that failed: a script present but not yet
      tracked, asserted to be reported. Today nothing exercises the untracked case, which is
      precisely why it survived.
- [ ] Decide whether `kit-init.sh` should say anything about this to an adopter writing their
      first adapter. `docs/ADAPTERS.md` tells them to write an executable and never mentions
      that the exec bit has to reach the index.

## Notes

Filed 2026-08-09 after CI caught it on the first push. Worth keeping as evidence FOR the
push-early rule rather than against the suite: the gate did its job at the first opportunity it
had, and the alternative was carrying a broken mode through however many commits until someone
thought to ask CI. The defect is that its first opportunity comes later than it needs to.
