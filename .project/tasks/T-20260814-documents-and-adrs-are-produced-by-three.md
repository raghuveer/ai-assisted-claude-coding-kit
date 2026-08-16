---
id: T-20260814-documents-and-adrs-are-produced-by-three
title: Documents and ADRs are produced by three agents and reviewed by none
epic: agent-contracts
tier: T2
lang: bash
paths: agents, tests/conformance.sh
state: open
---

## Intent

Three agents produce prose artefacts: `researcher` writes a dated design-input document,
`adr-scribe` writes an ADR, `documenter` updates README, docstrings, CHANGELOG and topic docs.

**No reviewer reads any of them.** `implementation-reviewer` reviews code against a design,
`security-reviewer` fires on high-stakes code paths, `approach-reviewer` judges a design
*before* implementation. The pipeline reviews the code half of the deliverable and nothing else.

That is a structural hole, not an oversight of degree: the kit's own constraint is that **the
delivered application must be maintainable without GenAI, by developers, as-is**, which makes the
code AND the docs — ADRs included — the entire inheritance. Half of it currently ships ungated.

## What such a reviewer is for

Not style. The failure mode is a document that reads well and is not anchored:

- a claim attributed to a source the source does not make
- an identifier, path, ADR number or version that does not exist
- a figure carried from an earlier draft and no longer true of anything
- a summary that inverts a negation or widens a quantifier from its source
- an inference presented with the same confidence as a quoted fact

Every one of these survives a proofread and is caught by comparing against the source.

## The change

A read-only reviewer, same contract as the others — `Read, Grep, Glob`, one JSON object with
`verdict`, `narrative` and `findings`, recorded through the existing door. Fires after
`documenter` for shipped docs, after `adr-scribe` for a decision record, and on any prose-heavy
output from `coder`.

Two design points worth settling:

- **Overlap with the reference check.** `T-20260814-nothing-checks-that-a-finding-s-file-and`
  proposes mechanical verification of paths and symbols. Whatever is mechanically checkable
  should be checked mechanically and NOT delegated to a reviewer — a model asked to do a grep's
  job is a slower, less reliable grep. This agent gets what the grep cannot decide.
- **Which class findings take.** The vocabulary has `false-rationale` and `compliance` but nothing
  for an unanchored claim. Either an existing class stretches, or the vocabulary gains one, and
  that decision belongs here rather than to whoever files the first such finding.

## Acceptance criteria

- [ ] A document produced by the pipeline can be reviewed by an agent whose findings are recorded
      through the same door as every other finding.
- [ ] The reviewer is read-only **by declaration**, and the task states plainly that this is a
      convention rather than a mechanism. *Amended 2026-08-16.* This criterion originally read
      "enforced at invocation rather than requested in prose" — it was written against the
      `SECURITY.md` claim that `--allowedTools` binds, which was disproved and moved to
      `SECURITY.md` §3 under `T-20260815-security-md-claims-allowedtools-enforces`. As written it
      could only be met falsely, so it is corrected rather than left to be ticked on a premise
      that no longer holds. If a real gate is wanted here, it is separate work with its own
      criterion: it must FAIL when removed.
- [ ] Anything mechanically checkable is checked mechanically and is not this agent's job.
- [ ] The finding class used for an unanchored claim is decided and is in the one vocabulary home.
- [ ] Conformance asserts the new agent's inlined vocabulary against `--vocab`, as it does for
      every other agent that carries one.

## Notes

Filed 2026-08-15, from noticing that the kit's own `docs/` are produced and never reviewed while
`tooling/` cannot be changed without two reviewers. Adopted as an idea from external reference
material; the gap is the kit's own.
