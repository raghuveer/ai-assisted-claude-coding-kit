---
id: T-20260815-the-entry-mechanism-has-never-produced-a
title: The entry mechanism has never produced a proposal for this repo
tier: T2
lang: bash
paths: docs/design-input, .project
state: open
---

## Intent

AC5 of `T-20260814-one-entry-mechanism-brownfield-is-the-ge` is the self-ingest test: the mechanism
run against this repository must produce a usable candidate list. The census half has been run and
measured -- 80 files, 758 co-change pairs, 606 comment runs, a 607-line runs file. The judgement
half never has.

There is no `entry-candidates.md` and no committed `YYYY-MM-DD-entry-questions.md` under
`paths.design_input`. `researcher` has never been handed the report, so the one artefact the whole
mechanism exists to produce has not been produced once.

Found by the final implementation review, 2026-08-15.

## Acceptance criteria

- [ ] `researcher` is run against this repository's own entry artefacts and returns a proposal.
- [ ] `kit-entry.sh --check` passes on it.
- [ ] The questions file is committed under `paths.design_input`; the candidate list is not.
- [ ] The registered AC5 conditions are scored against the real output and the score recorded,
      whether or not it passes.

## Notes

Filed 2026-08-15. This is the acceptance criterion, not a demonstration: until it runs, "the
mechanism works" is an inference from its parts.
