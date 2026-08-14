---
id: T-20260814-a-review-narrative-has-nowhere-to-live
title: A review narrative has nowhere to live
epic: measurement
tier: T2
lang: bash
paths: tooling/kit-review-record.sh, tooling/kit_findings.py
state: open
---

## Intent

A reviewer returns `{verdict, narrative, findings}`. The narrative is where it explains a defect
it could not fit in a 200-character summary — the reasoning that makes a finding actionable
rather than a row in a table. `kit-review-record.sh` builds the reply in a `mktemp -d` under a
cleanup trap, so **the moment the loop exits the reasoning is gone**, for a review that was paid
for and ran read-only against the tree.

The verdict half of this is `T-20260814-a-reviewer-s-verdict-and-narrative-are-d`, and it is the
cheap half: a closed vocabulary that fits the existing event line. This task is the part that is
actually hard, and it was split out so the cheap fix is not held behind it.

## Why it is hard, stated rather than discovered later

`events.ndjson` is **committed, append-only, and read by line-oriented awk**. Every design that
puts a narrative there collides with at least one of:

- **Size.** A narrative runs to thousands of characters. Every one is carried in git forever, and
  `kit-index.sh` re-reads the whole log on every rebuild.
- **Flattening.** `sanitise()` reduces a value to one printable line with no quote and no
  backslash. A markdown narrative survives that badly — it is the one field where the lossiness
  destroys the thing being stored.
- **Unbounded write.** Nothing currently stops a model writing 40KB into a tracked file. A
  reviewer is the least appropriate party to hold that pen.

## The change

The shape is the decision, and one option is not "in events.ndjson at all":

- **An artefact, referenced.** Write the narrative as a file — the way `researcher` writes a
  dated design-input document and `adr-scribe` writes an ADR — and have the event carry its path.
  A review narrative is a document a human reads, which is what those two agents already produce.
  It also sits better with the constraint that outranks the rest: **the code and the docs must be
  usable without the kit**, and a markdown file is, where a flattened line in an NDJSON log is
  not. The cost is a second store and a retention question the kit does not otherwise have.
- **In the log, bounded.** Simpler to reason about, and it needs a stated limit, a truncation
  rule that is visible rather than silent, and an answer to the flattening problem.

Prefer the first unless the second can be made to keep markdown readable, because a narrative
that survives as one mangled line has been recorded without being kept.

## Acceptance criteria

- [ ] A reviewer's narrative is readable after the process that produced it exits.
- [ ] It is readable **without the kit** — a person with the repository and no tooling can find
      and read it.
- [ ] Whatever is stored, a reviewer cannot cause an unbounded write into a committed file. The
      limit is stated and enforced, not assumed.
- [ ] Markdown survives storage and retrieval intact, or the loss is explicit and visible at the
      point of reading. A silently mangled narrative is worse than an absent one, because it
      reads as the record.
- [ ] The one-writer rule holds: nothing new serialises JSON outside `kit_findings.py`.
- [ ] A fixture stores a narrative containing quotes, newlines and several KB of text, and
      `events.ndjson` is still line-parseable afterwards.

## Notes

Split out of `T-20260814-a-reviewer-s-verdict-and-narrative-are-d` on 2026-08-14, hours after
that task was filed, once it was clear the two halves shared a title and nothing else. There is
deliberately **no `blocked_by` edge** between them: `blocked_by` cascades — `kit-plan.sh` withholds
a dependent and everything transitively behind it, measured once at 20 of 22 open tasks from a
single mistyped id — and these two share a design constraint, not an order. The one-writer rule
is already enforced by `kit_findings.py` being the only serialiser, which does the work an edge
would do badly.
