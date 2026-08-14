---
id: T-20260814-a-reviewer-s-verdict-and-narrative-are-d
title: Record the bounded facts agents already return - verdict, build, lint and test results
epic: measurement
tier: T3
lang: bash
paths: tooling/kit_findings.py, tooling/kit-index.sh, tooling/kit-status.sh, tests/conformance.sh
state: open
---

> **Re-scoped 2026-08-14, hours after filing.** This was "a reviewer's verdict and narrative are
> destroyed", which bundled a cheap fix with an expensive one. `verdict` is a closed three-value
> vocabulary that fits the existing event line today; `narrative` is unbounded free text going
> into a committed, line-oriented log, and every hard question belongs to it alone. Splitting
> them on **bounded vs unbounded** rather than on reviewer-vs-producer also showed the seam runs
> ACROSS that boundary: `coder` and `tester` emit bounded facts with the same problem and the
> same fix. The narrative half is now
> `T-20260814-a-review-narrative-has-nowhere-to-live`.
>
> **The id slug still says "verdict-and-narrative".** Ids are written into git trailers and are
> not rewritten, so it stays wrong and is documented rather than corrected.

## Intent

Every agent already returns facts in a fixed shape, and **none of them are recorded.**

`kit_findings.py:210` validates `verdict` and `narrative` as strings and then deliberately drops
both: *"Accepted and ignored here: this module records findings; the verdict is for the human who
decides whether the work closes."* The contract is not missing — one decision discards its
output.

The producing agents are the same story with no JSON at all. `coder` returns
`build pass|fail (N errors)`, `lint clean|N` and a run-log path. `tester` returns
`N passed / M failed / K skipped`, plus the names of surviving mutants. These are deterministic,
bounded, already-structured facts, delivered as prose that nothing reads.

**What this costs, concretely:** an empty review cannot be told from a review that never
happened. Observed 2026-08-14 on this repository — `implementation-reviewer` returned zero
findings while `security-reviewer` returned five on the same brief and the same tree, and the
zero could not be used as corroboration, challenged, or audited. A recorded `verdict` settles
that: `APPROVED` with no findings is a review that looked and approved; nothing at all is a
review that did not run.

## Why these belong together, and why the narrative does not

Everything in scope here is **bounded and closed**:

| fact | shape |
|---|---|
| `verdict` | `APPROVED \| REVISE \| REJECT`, plus `HALT` for `security-reviewer` |
| build | pass/fail + an error count |
| lint | clean, or a count |
| tests | passed / failed / skipped counts |
| mutants | names of survivors |
| run log | a path |

Each fits the event line exactly as `class` and `severity` already do. There is no size question,
no flattening question, and no way for an agent to write unboundedly into a tracked file. That is
the whole difference from the narrative, and it is why that is a separate task rather than a
later section of this one.

## The change

Record them as events through the one writer. `kit_findings.py` is the only serialiser and must
stay so. Open questions that belong to this task:

- **Vocabulary.** `verdict` needs the same treatment `class` and `severity` get: one home,
  asked for rather than restated, asserted by conformance. `HALT` exists on exactly one agent
  and must not be silently accepted from the others or silently rejected from that one.
- **Attachment.** A verdict belongs to a review of a task. A build result belongs to... a task, a
  commit, or a session? Decide it once and state it; spend already has this question and answers
  it with a documented heuristic.
- **Producer emission.** `coder` and `tester` currently return prose. Either their contracts gain
  a small JSON envelope, or the runner extracts the fixed fields. The first is honest; the second
  is parsing, which every defect in this area has come from.

## Acceptance criteria

- [ ] A reviewer's `verdict` survives the process that produced it and is readable afterwards.
- [ ] An empty review is distinguishable from a review that never ran, **by the record alone** —
      not by a human remembering which happened.
- [ ] `verdict` has one vocabulary home and conformance fails if any agent's stated values drift
      from it. `HALT` is accepted only where it is defined.
- [ ] Build, lint and test results from `coder` and `tester` are recorded as data, not prose.
- [ ] Nothing new serialises JSON outside `kit_findings.py`.
- [ ] `kit-status.sh` can answer "was this task reviewed, and what did the review conclude"
      without reading a transcript.
- [ ] Every control added here is mutation-proved on the assertion written for it. Two mutations
      in this area have already survived by changing behaviour no test read.

## Notes

Filed 2026-08-14 from round 2 of `T-20260812-a-finding-cannot-be-marked-fixed-so-any-`, where
the round's own author could not verify whether a zero-finding review had looked at anything.
