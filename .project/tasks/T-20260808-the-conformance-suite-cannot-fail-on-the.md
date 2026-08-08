---
id: T-20260808-the-conformance-suite-cannot-fail-on-the
title: The conformance suite cannot fail on the platform it is written on
epic: validation
tier: T1
lang: bash
paths: tests/conformance.sh
state: open
---

## Intent

On 2026-08-08, twenty-eight commits were written and verified on Windows/git-bash, and every
one of them failed `macos-latest`. Ubuntu passed throughout, so nothing local or in reasoning
could see it. The cause was two GNU-only constructs in the SUITE — `wc` padding and BSD sed
not interpreting `\r` — fixed in T-20260808-the-conformance-suite-shipped-two-gnu-o.

The defect that task records is the constructs. The defect THIS one records is structural, and
it is the reason the constructs shipped:

**The suite has no way to fail on the platform its author is using.** Three step-groups were
added that day — CRLF handling, non-ASCII paths, apostrophes in awk programs. All three exist
specifically to guard text-encoding and userland portability. All three shipped a portability
defect in their own test code. Knowing about BSD `wc` would not have prevented it; the same
file already used `| wc -l | tr -d ' '` correctly two hundred lines away.

**And nothing guards the guard.** FINGERPRINT exists precisely to catch two platforms
producing different results, and it did not catch this, because it compares the DERIVED INDEX
— the kit's output — not the suite's own assertions. A check can be wrong on a platform while
the thing it checks is right, and the suite has no opinion about that at all.

## Acceptance criteria

- [ ] A check whose result depends on userland behaviour either runs identically everywhere or
      declares that it did not run. The `NOT EXERCISED` mechanism built for the CRLF step is
      the right shape — a probe, an honest skip, and a tally line — but it is applied to one
      step. Decide where else it belongs and apply it there.
- [ ] A lint over the suite for constructs known to diverge: bare `wc` captures, `sed` with a
      backslash escape in the pattern, `sed -i` without a suffix, `grep -P`, `readlink -f`,
      `date -d`, `stat -c`. This is mechanical, it is cheap, and every one of them has already
      cost this repository or is documented as costing others.
- [ ] Decide whether the suite should assert something about ITSELF the way it asserts about
      the kit. FINGERPRINT compares derived output across platforms; the open question is
      whether an equivalent exists for the assertions. If the answer is that CI is the only
      possible answer, record that — it is a legitimate finding and it changes the workflow
      rather than the code.
- [ ] Write down the cheapest lesson explicitly, where someone will read it: **push early.**
      Twenty-eight commits landed before CI was asked. The first push would have cost nothing
      and caught this twenty-seven commits sooner. This belongs in the working agreement, not
      in a task nobody re-reads.

## Notes

Deliberately T1 and deliberately narrow. The temptation is to widen this into "test the tests",
which has no natural stopping point. The finding is specific: checks that guard portability
are themselves unguarded, and the platform that writes them is the one platform they cannot
fail on.

Worth recording for the trial protocol (T-20260808-a-repeatable-trial-protocol-for-running-):
any measurement taken on one platform and reported without saying which is subject to exactly
this. Today produced 46 findings and a full day of fixes on evidence from a single OS.
