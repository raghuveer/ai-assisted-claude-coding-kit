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

- [x] One mechanism handles all three starting conditions. Greenfield is the empty-inventory case
      of it, not a separate path.
      **Two of three proved.** Greenfield and an imported single-commit history are asserted in
      `tests/conformance.sh`, each mutation-killed; a third case (a second commit clearing the
      degenerate state) exists so the first two cannot pass against a hardcoded string.
      Modernization is deferred — see the last criterion.
- [x] The output is a CANDIDATE task list plus a list of questions, and is not usable as work
      until a human confirms it.
      `kit-entry.sh --check` validates the shape and refuses thirteen malformed proposals; the
      tool writes no task file and a fixture proves it. **The hold itself is convention, not
      mechanism** — ADR 0001 records that as an accepted gap, not a solved one.
- [x] A design choice lacking a decision record is raised as a question and is never filed as a
      defect or a task by the analysis itself. A fixture proves the refusal, not just the
      surfacing.
      The fixture asserts a PRESENCE — the undocumented constant is reported — alongside the
      absences, so a `kit-entry.sh` of `exit 0` fails it.
- [x] What the analysis could not determine is stated. An inventory silent about its own gaps
      reads as complete.
      Degeneracy states per input, counted exclusions, a `reconciled` invariant, and a
      "What this does not know" section that names what no comment scanner can reach.
- [x] Running it against this repository produces a usable candidate list — the self-ingest test.
      **Measured 2026-08-15.** 9 candidates against a bound of 12, 8 questions against 1–15,
      21/21 cited paths exist, `--check` conformed first attempt, zero overlap above 0.12 with
      any of 99 open tasks. Questions committed at
      `docs/design-input/2026-08-15-entry-questions.md`. Four of the nine candidates are defects
      in `kit-entry.sh` itself.
- [~] Modernization's source→target delta is expressible without a second mechanism.
      **DEFERRED by the operator, 2026-08-16, and this task closes without it.** The delta lives
      in the solution overlay (`docs/DESIGN-NOTES.md` §2), which is unbuilt, so there is nothing
      to express it with and nothing to assert. Carried by
      `T-20260815-ac6-modernization-delta-is-claimed-but-u` (T3), which must be met before the
      overlay work claims this ground. Recorded as deferred rather than ticked, because an
      acceptance criterion met by an unbuilt component is met by nothing.

## Notes

Filed 2026-08-15. Supersedes the sequencing that treated the three as separate builds. The
adoption work (`T-20260808-adoption-paths-for-an-empty-folder-and-f`) is a different thing —
that is about installing the kit into a repository; this is about what the kit does once it is
there and there is code to read.

## Closed 2026-08-16

Five of six criteria met with checks that fail under mutation; the sixth deferred by the operator
and carried by a filed task. What ships: `tooling/kit-entry.sh` (file-anchored census, uncapped
comment runs, `--check`), `docs/ENTRY-PROPOSAL.md`, ADRs 0001 and 0002, four conformance steps,
and `paths.adr` / `paths.design_input` in both the profile and the template.

**What is NOT true of it, stated because closing a task is where these get lost.** Nothing in the
kit causes `kit-entry.sh` to run — no hook, no skill, no `--if-stale`, no mention in `INSTALL.md`.
It is correct, tested, green on both platforms, and unreachable until §C is rewritten. The hold on
the candidate list is convention. Six findings from the final review are filed rather than fixed,
including four of five prior-round fixes still lacking a constructed `reconciled MISMATCH` case.

**What it cost to get right, in defects the process caught:** two approach reviews rejected design
1 on measurement rather than argument; an implementation review returned REJECT with 12 findings
including a fail-open in a fix pushed an hour earlier; and the self-ingest found four defects in
the mechanism that produced it — more than three review rounds did.
