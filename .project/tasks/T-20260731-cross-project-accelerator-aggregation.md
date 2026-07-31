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

