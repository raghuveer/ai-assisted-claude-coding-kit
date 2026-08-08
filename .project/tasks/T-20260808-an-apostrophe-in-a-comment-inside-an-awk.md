---
id: T-20260808-an-apostrophe-in-a-comment-inside-an-awk
title: An apostrophe in a comment inside an awk program breaks the script far from its cause
epic: validation
tier: T1
lang: bash
paths: tests/conformance.sh
state: done
---

## Intent

Every awk program in `tooling/` is a multi-line single-quoted shell string. An apostrophe
typed inside one — almost always in a comment, in an ordinary English possessive — closes
that string. What follows is reinterpreted as shell, and the script breaks.

It happened twice on 2026-08-08, in the same file, hours apart:

    # ... otherwise the agent's own .meta.json ...
    # ... this project's own rule is that a floor ...

`bash -n` does catch it, and it is already the project's `commands.lint`. What it does not do
is say where. Both times it reported a syntax error at the line where PARSING finally broke —
ten to seventy lines below the apostrophe — naming a token that had nothing to do with the
cause:

    kit-index.sh: line 531: syntax error near unexpected token `p,'

The second time the whole conformance suite went from 27 passed to 13 passed / 12 failed,
which is a loud signal pointing at the wrong place.

There is also a case `bash -n` cannot catch at all. Two stray apostrophes in one program
re-balance the quoting: the script parses, runs, and hands awk a program whose text has been
silently altered. Nothing on this machine has hit that yet, and nothing would report it.

The codebase already has the correct idiom for a genuine apostrophe, used in this very file:
`'"'"'` — close the string, emit a quoted apostrophe, reopen. The guard should accept that and
reject the bare one.

## Acceptance criteria

- [x] A conformance step names the FILE AND LINE of a bare apostrophe inside a single-quoted
      program body, before `bash -n` gets a chance to report something else.
      **Reframed on measurement.** Detecting independently was tried and rejected: tracking
      single-quote parity to decide whether a line sits inside a program flags **21 lines of
      this tree**, because an apostrophe inside a DOUBLE-quoted string -- `sed "s/'/''/g"` --
      flips the same counter, and separating the two needs a shell tokeniser. `bash -n`
      already detects reliably; what it does badly is locate. So the step DIAGNOSES rather
      than re-detects: it runs `bash -n`, and on failure reports the nearest
      comment-carrying-an-apostrophe at or above the line bash blamed. Measured on the real
      defect re-injected into `kit-index.sh`:

          bash -n alone:  line 544: syntax error near unexpected token `p,'
          with the step:  likely cause kit-index.sh:543: # ...this repository's that a floor...

- [x] The `'"'"'` idiom is accepted, since it is the correct way to write one and is already
      used in `tooling/kit-index.sh`.
      Neutralised before the scan, so the correct form is never offered as a cause.
- [x] It fails on a fixture that contains the defect and passes on the tree as it stands --
      proven by mutation, not by the suite being green today.
      The step carries its own fixture: a small script whose awk program has a possessive in a
      comment at a known line. It asserts that the script does not parse AND that the
      diagnosis points at that line, so the guard is exercised on every run rather than only
      when something is already broken.
- [x] It does not fire on an apostrophe in an ordinary shell comment outside a program body,
      which is legal and common.
      Zero false positives: the diagnosis only runs on a file that already failed to parse.

## Outcome

Two checks in one step: every script parses, and the diagnosis points at the apostrophe.

**What is NOT covered, and is stated in the step itself:** two stray apostrophes re-balance
the quoting, so the script parses, runs, and hands awk a silently altered program. `bash -n`
cannot see that and neither can this. Nothing has hit it yet, and the honest position is to
name the gap rather than let a green step imply it is closed.

## Notes

This note originally proposed the rule "a COMMENT line inside a single-quoted region
containing a bare apostrophe", on the argument that it needs no quoting model beyond tracking
the region. **That argument was wrong and the measurement is above:** tracking the region IS
a quoting model, and an incomplete one -- 21 false positives on this tree, every one an
apostrophe inside a double-quoted string flipping the same counter. Anchoring the diagnosis to
the line `bash -n` already found needs no model at all. Left here rather than rewritten,
because the proposal is what the reasoning supported before it was tried.

Raised by the operator after watching it happen the second time.
