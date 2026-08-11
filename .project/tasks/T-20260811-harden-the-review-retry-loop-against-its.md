---
id: T-20260811-harden-the-review-retry-loop-against-its
title: Harden the review retry loop against its own edges
epic: feedback-loop
tier: T2
lang: bash
paths: tooling/kit-review-record.sh, tooling/kit_findings.py, tooling/kit-status.sh
state: open
---

## Intent

`tooling/kit-review-record.sh` closes the findings loop: it runs a reviewer, hands back the
validator's own diagnostics when a reply is refused, retries boundedly, and records either the
findings or a `finding-gap`. Round 5 of `T-20260801-nothing-invokes-kit-finding-so-the-findi`
reviewed it and returned 15 findings, **all in that one new file or its fixture**.

The critical (a missing prompt file reviewed as an empty prompt and reported as a clean review)
and the two majors of the same false-clean shape (SIGPIPE turning a good review into a broken
command; a validator failure read as a refusal, resending an empty prompt) are **fixed and
mutation-proved** on the parent task. Everything below is what remains.

Filed separately rather than folded in because the parent task has already run five review
rounds and the remaining items are hardening, not correctness of the mechanism.

## The findings, verbatim from the round

**Majors**

1. **The `INT` trap deletes `WORKDIR` without exiting** (`:71`), so Ctrl-C falls through to the
   tail and writes a `rejected` gap into the committed log instead of cancelling the run. A
   cancelled review is not a refused one.
2. **`$ATTR` is unquoted at three call sites** (`:53-56`, `:102`, `:126`) so that it word-splits
   into two arguments. A task id containing whitespace or a glob character breaks both the
   recorder and the gap call, and the review is lost with no row at all — a fail-open in the
   thing whose job is to never lose a row. Build the arguments as a list instead.
3. **The tail gap append is unchecked and does not `mkdir -p` the state directory** (`:126-127`).
   This is precisely the check round 4 added to `kit-finding.sh`, reintroduced one file over —
   §4, third instance of that lesson in three days.
4. **A broken reviewer command is recorded as `reason=rejected`** (`:126`), and `kit-status.sh`
   words that as findings refused "for an unrecognised class or severity, or a malformed field".
   No findings ever existed. The gap vocabulary needs a third value — `unavailable` — with the
   report wording to match.

**Minors**

5. **A double gap is possible**: `kit-finding.sh`'s `emit` writes one on rejection, and if that
   invocation then exits non-zero the tail writes a second, so one failed review counts twice.
6. **The `mktemp -d` fallback is predictable** (`${TMPDIR}/kitrev.$$`) and `mkdir -p` accepts a
   pre-created or symlinked directory, so a local user could read or substitute a reviewer reply.
7. **No timeout and no output cap on the reviewer command.** The bound counts attempts only, so
   one hung or runaway invocation is unbounded in time and disk.
8. **The exit-3 / exit-2 distinction is now read** by the loop, but the comment claiming it
   "protects the caller" predates that and should say what it actually buys.
9. **Reviewer-controlled text is interpolated into the correction prompt** sent back to a model,
   so a crafted field name can carry instructions into the retry (OWASP LLM01). Low impact while
   the reviewer is read-only, and worth bounding before it is not.

## Acceptance criteria

- [ ] Ctrl-C cancels: no gap row is written, and the exit status says interrupted.
- [ ] A task id containing a space or a glob records correctly, and cannot lose the review.
      Proved with such an id in a fixture, not by inspection.
- [ ] The tail append is checked and creates the state directory, and a failure to write says so
      rather than reporting success.
- [ ] `unavailable` exists as a gap reason, a broken command records it, and `kit-status.sh`
      words the three reasons distinctly. A reason nothing emits must not appear in the report.
- [ ] One failed review produces exactly one gap row, asserted by count in a fixture that
      exercises the double-write path.
- [ ] The reviewer command is bounded in time as well as attempts, with the timeout stated in
      the failure message.

## Notes

Filed 2026-08-11 from round 5. The parent task's round-5 section carries the full context,
including that the round was run THROUGH the loop — one reviewer was refused, corrected itself
from the validator's diagnostics, and recorded on the second attempt with no human involved.

Deliberately T2 rather than T3: the mechanism's correctness is established and mutation-proved
on the parent; these are edges around it. Note the `tooling/**` floor is T2, so this is at its
floor, not below it.
