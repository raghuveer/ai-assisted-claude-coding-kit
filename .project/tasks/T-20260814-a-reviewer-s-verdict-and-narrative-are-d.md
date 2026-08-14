---
id: T-20260814-a-reviewer-s-verdict-and-narrative-are-d
title: A reviewer's verdict and narrative are destroyed, so an empty review cannot be told from one that never looked
epic: measurement
tier: T2
lang: bash
paths: tooling/kit-review-record.sh, tooling/kit_findings.py, tooling/kit-finding.sh
state: open
---

## Intent

The findings contract asks a reviewer for one JSON object with three keys: `verdict`,
`narrative`, `findings`. Only `findings` is recorded. `kit-review-record.sh` builds the reply in
a `mktemp -d` under a cleanup trap, so the moment the loop exits, the verdict and the reasoning
are gone — from a review that was paid for, that ran read-only against the tree, and whose
conclusions are now the basis for closing a task.

**The failure is not the loss. It is that an EMPTY review is indistinguishable from one that
never looked.** A reviewer returning `{"findings":[]}` records a `finding-gap` with
`reason=empty`, which the kit reports as "a review looked and found nothing" — a measurement.
Nothing in the record supports that reading. The evidence that it looked was in the narrative,
and the narrative was deleted.

Observed 2026-08-14 in round 2 on
`T-20260812-a-finding-cannot-be-marked-fixed-so-any-`: `implementation-reviewer` returned zero
findings while `security-reviewer` returned five on the same brief and the same tree. The zero
cannot be used as corroboration, cannot be challenged, and cannot be audited — it is an absence
of data being reported as agreement.

This repository has already been bitten by the same reading once. The retry loop replaced the
caller's request with the correction text, so attempt 2 reviewed nothing and returned an empty
object, recorded as `reason=empty`. That was found by OPERATING the loop, not by reviewing it,
and the fix made the retry carry its context — but the record still cannot show whether any
given empty review looked.

## Why it matters beyond this round

- `verdict` is the one field that says REJECT, and the kit's own working agreement is "run the
  review before marking done". Nothing stores the verdict a task was closed against.
- The narrative is where a reviewer explains a finding it could not fit in a 200-character
  summary. That explanation is the difference between a finding an implementer can act on and a
  row in a table.
- `finding-gap` splits `empty` from `rejected` precisely because absence has to be legible. The
  split is undermined if the `empty` half carries no evidence.

## The change

The shape is a decision:

- **Record the reply.** A `review` event carrying `verdict`, `narrative`, agent, model and a
  digest of the prompt, written by the same one writer that serialises everything else. It
  travels in `events.ndjson` and survives a rebuild, like every other fact here.
- **Or keep the artefact.** Write the raw reply under the state directory and reference it from
  the gap event. Cheaper, but introduces a second store and a retention question the kit does
  not otherwise have.

The first fits the design. Note the size problem honestly: a narrative can run to thousands of
characters, `events.ndjson` is committed and append-only, and every reader of it is a
line-oriented awk. Sanitisation flattens to one line, which a long narrative survives badly.
That tension is the real work, and it is why this is not a two-line change.

## Acceptance criteria

- [ ] A reviewer's `verdict` is recorded and readable after the process that produced it exits.
- [ ] An empty review carries evidence that a review happened — at minimum the verdict and the
      narrative it came with. `reason=empty` alone is not evidence.
- [ ] `kit-status.sh` can distinguish "reviewed, found nothing, and here is what it said" from
      "recorded nothing". A count that cannot tell them apart is the defect, not the fix.
- [ ] The one-writer rule holds: nothing new serialises JSON outside `kit_findings.py`.
- [ ] A long narrative does not corrupt `events.ndjson`. A fixture sends one with quotes,
      newlines and several KB of text, and the log is still line-parseable afterwards.
- [ ] Whatever is stored, a reviewer cannot cause an unbounded write into a committed file. The
      limit is stated and enforced, not assumed.

## Notes

Filed 2026-08-14, from round 2 of `T-20260812-a-finding-cannot-be-marked-fixed-so-any-`, where
the round's own author could not verify whether a zero-finding review had looked at anything.
