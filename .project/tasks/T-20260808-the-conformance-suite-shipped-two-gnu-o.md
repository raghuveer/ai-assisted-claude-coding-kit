---
id: T-20260808-the-conformance-suite-shipped-two-gnu-o
title: The conformance suite shipped two GNU-only constructs and took macOS red
epic: portability
tier: T1
lang: bash
paths: tests/conformance.sh
state: done
---

## Intent

CI ran for the first time on today's work and reported **ubuntu-latest green, macos-latest
red**. Every commit from 2026-08-08 fails; the last green commit is `36e229e`, the state
before the day started. The failure is in the conformance suite itself, not in the kit.

Two constructs, both added today, both GNU-only:

**1. `wc` output is padded on BSD and not on GNU.** `tests/conformance.sh:361` read

        [ "$(tr -cd '\r' < rules.out | wc -c)" = 0 ] || exit 1

On Linux that compares `0`; on macOS it compares `       0`, which is never equal, so the
step exits 1. A second instance at `:342` fed a printed label rather than a check, so it was
wrong on macOS without failing anything. The same file already got this right in the
vocabulary step — `| wc -l | tr -d ' '` — so the knowledge was present and applied
inconsistently.

**2. BSD sed does not interpret `\r`.** Ten call sites used `sed 's/\r$//'` to strip a line
terminator without deleting the artifact under test. On BSD that pattern matches a literal
`r`, so it strips a trailing `r` instead. It happened to be harmless because no asserted
value ends in one — which is luck, not correctness, and precisely the shape this suite exists
to refuse.

## What was done

- Every `wc` capture strips whitespace.
- Every CR strip uses `sed $'s/\r$//'`, where the shell expands the byte before sed sees it.
  That form is correct on both.

## Acceptance criteria

- [x] macOS and Linux run the same assertions and reach the same verdict.
- [x] No bare `wc` capture and no bare `sed 's/\r$//'` remains in the suite.
- [ ] CI green on both platforms. **This is the criterion that closes it, and it cannot be
      checked from the machine that wrote the fix** — which is the whole lesson.

## Notes

The lesson is not "remember BSD wc". It is that **the suite has no way to fail on the
platform it is written on.** Every check added on 2026-08-08 was verified on Windows/git-bash
and shipped on the strength of that, including checks specifically written to guard
platform-specific behaviour. The CRLF work, the non-ASCII work and the apostrophe work were
all about text-encoding portability, and all three shipped a portability defect in their own
test code.

Two further observations worth keeping:

- The FINGERPRINT step exists to catch exactly this class — two platforms producing different
  results — and it did not, because it compares the derived index, not the suite's own
  assertions. It guards the kit; nothing guards the guard.
- CI is the only reader that can answer this, and 28 commits landed before anyone asked it.
  Pushing earlier would have cost nothing and caught this on the first commit rather than the
  twenty-eighth.
