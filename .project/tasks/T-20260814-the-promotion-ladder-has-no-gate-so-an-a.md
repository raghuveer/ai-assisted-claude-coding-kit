---
id: T-20260814-the-promotion-ladder-has-no-gate-so-an-a
title: The promotion ladder has no gate so an accelerator promotes on opinion
epic: accelerators
tier: T2
lang: bash
paths: tooling/kit-accel.sh, accelerators, tests/conformance.sh
state: open
---

## Intent

The promotion ladder is documented — 1 occurrence is not a pattern, ≥N in one project is a
project-scoped tier, ≥1 in ≥2 distinct projects is a shared candidate, and refutations block
promotion regardless of volume. **None of it is implemented.** `kit-accel.sh` has no threshold,
no status, and no gate; grep finds nothing.

The three shipped accelerator files carry no metadata at all: no status, no version, no owner, no
statement of what they are unsuitable for. An accelerator is a distributed artefact — loaded into
other people's work, where it becomes an assumption — and today nothing distinguishes a seeded
draft from something that has earned its place.

Without a gate, promotion happens because someone believes it should. That is exactly the
failure the escape-rate machinery exists to prevent one level down.

## The change

**A gate that compares a measured value against a declared threshold, and records both.** The
discipline is the kit's own: the number that decides sits next to the number required, so an
asset that has not earned promotion says so by arithmetic rather than by opinion. An accelerator
whose measured pass rate sits below its threshold stays `experimental`, visibly, with the two
numbers adjacent.

Minimum metadata for a shared asset, and no more than is needed to make the gate meaningful:

- **status** — `experimental | approved | deprecated`, with a review date, and on deprecation a
  named successor rather than a dead asset that still loads
- **owner** — so "who may publish this" has an answer
- **applicability in both directions** — what it suits AND what it must not be used for, plus
  known limitations. An asset that advertises only its strengths gets loaded where it does harm
- **provenance per line** — the `[seeded]` / `[earned]` marking that already exists in the design,
  and is in none of the three files

## Deliberately out of scope

Model routing, cost envelopes per model, and runtime telemetry belong to whatever operates the
models, not to a stack-agnostic support kit. Note one live tension for whoever takes this: the
kit's agents pin **tier aliases** (`haiku` / `sonnet` / `opus`) and `docs/MODELS.md` exists to
forbid pinning a model ID, for portability. Any metadata that carries model identity into the kit
contradicts that rule, and the rule should be changed deliberately or not at all.

## Acceptance criteria

- [ ] An accelerator carries a status, and a status that is not `approved` is visible wherever
      the accelerator is listed.
- [ ] Promotion is refused when the measured value is below the declared threshold, and both
      numbers are recorded — not a boolean.
- [ ] A refutation blocks promotion regardless of occurrence count.
- [ ] A deprecated accelerator names a successor and is not silently loadable.
- [ ] The three shipped files gain metadata or are marked as the seeds they are.
- [ ] No model identity enters accelerator metadata while `docs/MODELS.md` forbids it.
- [ ] The gate is mutation-proved: an accelerator below threshold must fail to promote, and the
      test must fail if that check is removed.

## Notes

Filed 2026-08-15. `T-20260808-co-change-has-no-eval-harness-so-its-sco` makes the same argument
for co-change scoring: a ladder without a measurement is a ranking without a basis. The two share
the "measured beside required" shape and should probably share an implementation.
