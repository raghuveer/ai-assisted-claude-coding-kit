---
id: T-20260814-one-entry-mechanism-brownfield-is-the-ge
title: One entry mechanism - brownfield is the general case and the other two are its starting conditions
epic: components
tier: T2
lang: bash
paths: skills, tooling, docs/DESIGN-NOTES.md
state: open
---

## Intent

The kit has no way to turn an existing codebase into a task list. That was previously framed as
three separate entry paths — greenfield, brownfield, legacy modernization — to be built in
sequence. **That framing is wrong, and it would have built the same thing three times.**

They are not three kinds of project. They are **three states of one project's life**: a
greenfield build becomes a brownfield project the moment anyone maintains it, and a modernization
candidate as its stack ages. So there is one mechanism, parameterised by what exists at the start:

| state | what it is |
|---|---|
| **Brownfield** | the general case — existing code and docs, analysed to produce a candidate task list |
| **Greenfield** | brownfield with an **empty inventory**; the overlay and the feature discussion carry the whole input |
| **Modernization** | brownfield plus a **source→target stack delta** |

Brownfield is therefore built first — not because it is the case adopters happen to have, but
because it is the general form the other two specialise.

## The rule that must not be got wrong

**An undocumented design choice is a QUESTION, not a defect.**

When the analysis meets a choice with no decision record and no explanation, it has found an
absence of rationale — not evidence of a mistake. A future team reading the same code will
reach the same fork, and the failure mode is well known: read a deliberate choice as an
oversight, "fix" it, and break what it was protecting.

So an entry analysis must:

- **surface such choices as open questions** carried into the solution overlay scope or into the
  discussion with the architect, and
- **never auto-file them as work**, and
- **hold the task list unconfirmed** until those questions have answers.

This is the same rule the kit already applies to measurement — absent is not zero, unknown is not
clean — applied to design intent. Undocumented is not wrong.

## Output, and who confirms it

The mechanism produces a **candidate** list: proposed tasks, the questions that must be answered
first, and what the analysis could not determine. **A human confirms it before any coding
begins** — the same human gate that already governs task filing, for the same reason.

Only after confirmation does the existing machinery take over: tiering, dependency grouping,
context loading per group, review at the declared tier.

## The test that comes free

A project this kit builds becomes its own input later, read by a different team, possibly with a
different kit or none. That gives a checkable property, and a subject that already exists:

> **Can the kit ingest a project it built itself, with no memory of having built it?**

If the decision records, task files, trailers and docs it left behind do not support that, they
will not support a stranger either. Run it against this repository before looking for an external
subject.

## Acceptance criteria

- [ ] One mechanism handles all three starting conditions. Greenfield is the empty-inventory case
      of it, not a separate path.
- [ ] The output is a CANDIDATE task list plus a list of questions, and is not usable as work
      until a human confirms it.
- [ ] A design choice lacking a decision record is raised as a question and is never filed as a
      defect or a task by the analysis itself. A fixture proves the refusal, not just the
      surfacing.
- [ ] What the analysis could not determine is stated. An inventory silent about its own gaps
      reads as complete.
- [ ] Running it against this repository produces a usable candidate list — the self-ingest test.
- [ ] Modernization's source→target delta is expressible without a second mechanism.

## Notes

Filed 2026-08-15. Supersedes the sequencing that treated the three as separate builds. The
adoption work (`T-20260808-adoption-paths-for-an-empty-folder-and-f`) is a different thing —
that is about installing the kit into a repository; this is about what the kit does once it is
there and there is code to read.
