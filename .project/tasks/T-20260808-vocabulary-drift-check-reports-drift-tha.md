---
id: T-20260808-vocabulary-drift-check-reports-drift-tha
title: Vocabulary drift check reports drift that does not exist on a CRLF checkout
epic: validation
tier: T2
lang: bash
paths: tests/conformance.sh, .gitattributes
state: done
---

## Intent

`tests/conformance.sh` step "finding vocabulary has not drifted" fails on a Windows/git-bash
checkout of this repository, naming all three reviewers:

    class list differs: approach-reviewer.md
    class list differs: implementation-reviewer.md
    class list differs: security-reviewer.md

**The vocabulary has not drifted.** All three carry exactly what `kit-finding.sh --vocab`
prints:

    class:    fail-open race false-rationale perf compliance correctness style unclassified
    severity: critical major minor nit

The check flattens each agent file with `tr '\n' ' ' | tr -s ' '` and looks for the class
list as a substring. `.gitattributes` pins `*.sh`, `commit-msg`, `*.py` and `*.sql` to
`eol=lf` and says nothing about `*.md`, so with `core.autocrlf=true` — the Git for Windows
default, set in the system config here — every agent file is CRLF in the working tree. The
flatten converts `\n` and leaves the `\r`, so the inlined list reads `...style\r
unclassified` and matches nothing. The class list happens to wrap across a line in all three
agents, which is why only that one of the two assertions fires.

Verified by running the same suite against an LF checkout of the same commit
(`GIT_CONFIG_KEY_0=core.autocrlf GIT_CONFIG_VALUE_0=false git clone`): **23 passed, 0
failed**.

Tier T2 rather than the T1 default: this is a control, not a feature. It guards a
vocabulary that has already drifted across four locations once and left reviewers emitting
classes the recorder silently rejected. A guard that is red for a reason unrelated to what
it guards is a guard people stop reading, and this one has been red on this machine for
every run since it was written.

## Acceptance criteria

- [x] The check passes on a CRLF working tree and still fails on genuine drift — prove the
      second half by editing one agent's class list and watching it go red.
      Both proven. A copy of the kit with every agent and template CRLF-ified runs 23 passed,
      0 failed. Renaming `style` to `styling` in one agent, on a CRLF file, still goes red.
- [x] Decide where the normalisation belongs and record why. Two candidates, and they are
      not equivalent: `*.md text eol=lf` in `.gitattributes` fixes the checkout for every
      reader, and stripping `\r` at read time fixes only this comparison. A repository whose
      tests read working-tree bytes has more than one such comparison.
      BOTH, deliberately, and the second is the one that matters. `.gitattributes` fixes the
      checkout for everyone who gets the kit through git; `tr -d '\r'` in the reader makes
      the guard independent of anyone's configuration. Relying on the attribute alone would
      leave a test that passes only while every contributor's git agrees with it.
- [x] Whatever is chosen, no test in the suite may depend on the checkout's line endings.
      Audit the rest of `tests/conformance.sh` for the same shape rather than fixing the one
      step that happened to fail.
      Audited. One other reader of a checked-out file: the `tools:` line in "no agent is told
      to run a tool it does not have". It survived a CRLF checkout by luck -- the value it
      searches for is never last on the line, so the trailing `\r` never landed inside the
      match. Normalised anyway; luck is not a property. `validate.py` also reads these files
      and is immune, because Python's text mode collapses `\r\n` on read.
- [x] The failure message names the DIFFERENCE, not just the file. "class list differs" sent
      the reader to compare two identical lists by eye; printing the first differing run of
      bytes would have named the cause immediately.
      It now names the word the match dies on, and prints what `--vocab` says:
      `class list differs: security-reviewer.md — breaks at "style"`.

## Outcome

Three changes, and only the middle one is the actual fix:

1. `.gitattributes` pins `*.md text eol=lf`, so a markdown file checks out the same on every
   platform. The comment says why markdown is there for a different reason than `*.sh`:
   nothing in it would BREAK on CRLF, but the kit reads it as data.
2. The two readers in `tests/conformance.sh` strip `\r` before comparing. This is what makes
   the guard true regardless of configuration, and it is why 1 alone was not enough.
3. The failure names the word the match dies on rather than only the file.

Verified against a checkout with every agent and template deliberately CRLF-ified: 23 passed,
0 failed. Before the change that same checkout reported all three reviewers as drifted.

The working tree of this repository was renormalised in the same commit -- the committed
blobs were already LF, so nothing in git changed; only the files on this machine's disk did.

## Notes

Shares a root cause with T-20260808-fixture-fingerprint-is-not-reproducible-, which is the
same CRLF working tree reaching a different test by a different route. One `.gitattributes`
line may close both — which is an argument for fixing them together and against calling
either one closed on the evidence of a green run alone.

The kit is meant to run on Linux, macOS and Windows from the same checkout; CI covers the
first two. So this failed only where nothing was watching, which is the part worth
generalising: `.gitattributes` currently protects the files that would BREAK on the wrong
line ending (`*.sh`) and not the files that are merely READ (`*.md`). Being read by a test
turns out to be its own reason.
