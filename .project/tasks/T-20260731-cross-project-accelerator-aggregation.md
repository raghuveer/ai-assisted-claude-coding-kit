---
id: T-20260731-cross-project-accelerator-aggregation
title: Cross-project accelerator aggregation
epic: accelerators
tier: T2
state: open
---

## Intent


## Acceptance criteria

- [ ] an aggregator counts distinct salted project handles, not raw occurrences
- [ ] the collection point is private; only promoted content is published
- [ ] a project can be excluded from aggregation without editing its findings

## Notes

From HANDOFF §8. `kit-accel.sh export` writes per-project NDJSON --
{kind,key,class,n,vindicated,refuted,project,kit} with a salted project handle -- and
currently exports nowhere. Something must collect across projects and count distinct
project hashes; the promotion ladder counts distinct projects, not raw occurrences.

Layout decision, previously recorded as blocking: public marketplace folder vs private
collection repo. Recommendation given the client mix is private collection, public
promotion -- aggregate is not the same as non-sensitive, since {bfsi, fail-open, n:17}
still asserts a fact about an engagement. See docs/DESIGN-NOTES.md §3.


---

## Folded in 2026-08-11: the promotion ladder (R-07)

From the recommendations register, folded here rather than filed separately because it is the
policy this task's aggregation needs, not a distinct piece of work.

A pattern starts **project-local**, becomes **active** only after N confirmed uses, and is only
then **eligible** for promotion to the shared library. Unconfirmed candidates **expire** rather
than accumulating. Promotion to the shared library is a **human review gate**, never automatic.

The trust boundary to state explicitly: *a derived accelerator is unreviewed context, not
executable policy, until promoted.*

Acceptance to add: every entry in the shared library traces to a specific project and a
confirmation count, and an entry that cannot produce both is refused.

The plumbing partly exists — `tooling/kit-accel.sh`, and both `accelerator` and
`accel_candidate` tables (0 rows as of 2026-08-11). What is missing is the policy above and the
expiry.

**Why per-project vocabularies would break this**, recorded because it was nearly done the other
way on 2026-08-10: aggregation across projects is the entire point, so `class` and `severity`
must stay a shared taxonomy. A per-project class list would make the aggregate meaningless.
