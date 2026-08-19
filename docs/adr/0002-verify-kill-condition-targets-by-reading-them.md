# ADR 0002: A pre-registered kill condition must have its targets read before it is registered

- **Date:** 2026-08-15   **Status:** **Accepted**   **Accepted:** 2026-08-19   **Supersedes:** —   **Related:** [[0001-anchor-entry-facts-to-files]]

> **Status corrected 2026-08-19, not decided then.** Same defect as ADR 0001 and found in the same
> sweep: this read `Proposed` while the decision it records had shipped alongside
> `tooling/kit-entry.sh`. The correction is the status line only — nothing about the decision
> changed, and if any part of it is now doubted that belongs in a superseding ADR rather than in a
> quiet edit here.

## Context

`docs/design-input/2026-08-15-entry-mechanism-2.md` pre-registered a pass/fail condition for
the comment-block localiser (§B4, AC5.1) before running it: *"the top-40 list contains ≥3 of
these 4 known rationale sites: `kit-index.sh` §4 (~935-961), `kit-finding.sh:1-26`,
`kit-lib.sh:71-88`, `schema.sql:55-59`."* The stated intent was `delete, not tune` (`LESSONS.md`
§5) — a condition strict enough that failure would mean deleting the localiser rather than
adjusting it until it passed.

When the localiser was run and measured, the condition turned out to have been **void, not
failed**, for two compounding reasons found only by re-examining the targets themselves:

- `schema.sql:55-59` sits inside an 8-line comment run. The scanner's own threshold — a run
  must be ≥10 lines to be emitted at all — excludes that site **by construction**. The
  condition's "3 of 4, one miss allowed" was silently "3 of 3 reachable, no miss allowed",
  because a fourth of the named targets could never have been found regardless of how well the
  localiser worked.
- Scoring the other three against the actual run showed the two sites marked FOUND —
  `kit-finding.sh:1-26` and `kit-lib.sh:71-88` — were exactly the two sites the author of the
  design had personally read and confirmed as genuine ≥10-line rationale blocks earlier in the
  same session (recorded in the design document's own hypothesis section: *"Two of its four
  target sites I have read directly and they are genuinely ≥10-line rationale blocks... so the
  hypothesis is not unsupported — it is unquantified."*). The condition did not independently
  verify the localiser found real rationale; it reproduced the reader's own prior reading.

So the registered condition, run as written, measured **whether its own targets had been
verified before the run**, not whether the localiser locates rationale. `delete, not tune`
never actually fired, because the condition that was supposed to trigger it was never capable
of failing in the direction that mattered.

The design was then re-measured properly: a second agent, read-only and with no sight of any
scanner output, was asked to name the sites where "an explanation whose loss would cause a
competent maintainer to change the code and break something" lives, blind to the first
condition's four targets. It returned twelve, with line ranges and a one-clause reason each.
Scored against that independent set, the localiser's real recall was 6/10 into a capped top-40
report and 10/10 once the report was replaced with an uncapped artefact (`ADR 0001`) — a result
the original four-site condition was never positioned to produce, whether or not it had passed.

## Decision

**A pre-registered kill condition is only as good as its targets, and every target named in it
must be read and confirmed before the condition is registered — not sampled, not taken from
memory, not asserted from having filed the site once for an unrelated reason.**

Concretely, for this project: a kill condition that names specific sites as ground truth is not
usable evidence until (a) each named site is independently re-read at registration time against
the exact scanner rule that will be applied to it — thresholds included — and (b) the set of
targets is disjoint from the set the condition's author already knows to be correct answers,
which in practice means either a second, blinded party selects the targets, or the targets are
drawn by a rule the author does not control (e.g. a fixed sample, not a hand-picked list).

## Alternatives considered

- **Keep the four-site condition and treat its 3-of-4 pass as sufficient evidence.** Rejected.
  The condition was shown to be void by inspection of its own targets, and treating a void
  condition as a passed one is precisely the "green check that cannot fail" failure named in
  `LESSONS.md` §1 — this instance just wears a measurement costume instead of a test-suite one.
- **Widen the four-site condition instead of replacing its method.** Rejected as insufficient.
  Widening the list without changing who selects it, or without re-checking each site against
  the scanner's actual thresholds, reproduces the same defect at a larger N: a hand-picked list
  the author has already read is still a list the author has already read.
- **Drop pre-registered kill conditions for this kind of measurement entirely, and rely on the
  blind ground-truth method alone going forward.** Not adopted as a blanket rule by this ADR —
  pre-registration is still valuable for stating a bar before seeing results — but this decision
  narrows what counts as a *usable* pre-registered condition to one whose targets were verified
  independent of prior reading, per the Decision above.

## Consequences

**Easier.** The blinded re-measurement is now the project's evidence of record for the
localiser (`docs/design-input/2026-08-15-localiser-measurement.md`), and it is falsifiable in
the way the first condition was not: the twelve targets were chosen without sight of scanner
output, so a future scanner change can genuinely fail against them.

**Harder.** Registering a kill condition now costs more up front — every named target has to be
read and checked against the exact rule (including thresholds) before the condition counts as
registered, not just listed. A condition proposed without that reading is not evidence yet.

**New failure modes, named.** The blinding itself is a single point of trust: if the same
person both selects "independent" targets and already knows the scanner's behaviour in detail,
blinding by instruction alone may not be enough, and this ADR does not prescribe a mechanical
enforcement for it — the same convention-not-mechanism caveat as the hold and title-charset
gaps in `ADR 0001`.

**Invariants that must hold.** No pre-registered condition in this project should be cited as
having "passed" without recording, alongside the pass/fail line, who selected the targets and
whether they had been read or scored before registration. A condition without that provenance
is prose, not a measurement — the same standard `LESSONS.md` §11 sets for recording a measured
value beside a required one.

## References

- `docs/design-input/2026-08-15-entry-mechanism-2.md` §B4 ("The localiser, measured — and the
  result is 60%, invariant") and its "Hypothesis, unmeasured" section
- `docs/design-input/2026-08-15-localiser-measurement.md` (the blinded twelve-site ground truth
  and the recall table)
- `docs/LESSONS.md` §1 ("A green check that cannot fail is worse than no check"), §11 ("Record
  the measured value beside the required one")
- [[0001-anchor-entry-facts-to-files]]
