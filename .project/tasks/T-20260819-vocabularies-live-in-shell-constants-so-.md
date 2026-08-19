---
id: T-20260819-vocabularies-live-in-shell-constants-so-
title: Vocabularies live in shell constants so nothing can join, report or extend them
epic: reporting
tier: T3
lang: sql
paths: tooling/schema.sql, tooling/kit-finding.sh, tooling/kit-lib.sh, tooling/kit-status.sh
state: open
---

## Intent

Every controlled vocabulary in the kit lives as a shell constant and nowhere else:

| vocabulary | home |
|---|---|
| finding `class`, `severity` | `CLASSES=` / `SEVERITIES=` in `kit-finding.sh` |
| `via` provenance | `kit_via_vocab()` in `kit-lib.sh` |
| task `state` | implicit — `done`/`abandoned` are filtered for by string across several scripts |
| `Task-Status` trailer values | a different, narrower vocabulary again |
| event `kind` | the indexer's own `k=="…"` branches |

That is correct for **authority** — one home per vocabulary, which the kit enforced after the
finding vocabulary drifted across four locations and produced agents whose output the recorder
silently rejected. It is a problem for **use**: nothing can join against a value, no report can
enumerate the possible states rather than the observed ones, and a project cannot extend a
vocabulary without editing the kit.

The concrete symptom is already visible in `kit-status.sh`: every distribution it prints shows
only the values that **occurred**. A severity with zero rows is indistinguishable from a severity
that does not exist, and "no critical findings" reads identically to "criticals were never
recorded" — the same class of ambiguity the empty-review rule and the `via:kit` denominator rule
already exist to prevent elsewhere.

## The tension this must not resolve the wrong way

`tooling/schema.sql:84` states it deliberately:

    class TEXT,  -- kit-finding.sh --vocab is authoritative; do not restate it here

**A master-data table that becomes authoritative recreates the exact defect that comment
prevents.** The only safe shape is the one the kit already uses everywhere: text is truth, the
table is a DERIVED projection rebuilt by `kit-index.sh` from the single shell home, disposable
like every other row in `index.db`.

## Acceptance criteria

- [ ] Vocabulary tables are **derived, never authored** — populated by `kit-index.sh` from the
      existing single home of each vocabulary, and rebuilt on every index like everything else. A
      value present in the table but absent from its shell home is a bug in the derivation, not a
      second opinion.
- [ ] A check that can fail: the table's contents equal `kit-finding.sh --vocab` and
      `kit_via_vocab()` exactly. This is the whole safety argument, so it is the one assertion
      that must exist.
- [ ] Reports can distinguish **zero occurrences from not-a-value**. `kit-status.sh` joins against
      the vocabulary rather than grouping only what it observed, so an absent severity or state is
      reported as absent rather than invisible.
- [ ] Task `state` and the `Task-Status` trailer vocabulary each get a single home too. They are
      currently different sets — `open` is a valid `state` and an invalid trailer value, which has
      already turned the `trailers` CI job red once — and neither is enumerated anywhere a reader
      or a query can reach.
- [ ] **Per-project extension is designed or explicitly refused, not left ambiguous.** If a project
      may add a class, that changes what "the vocabulary drifted" means and the accelerator
      derivation has to cope; if it may not, say so where someone would otherwise try.
- [ ] Additive and non-breaking: `kit-index.sh` reads frontmatter by key lookup and ignores unknown
      keys, and existing consumers must be unaffected.

## Notes

Requested by the operator 2026-08-19: *"metadata and master data tables in database for each status
and kind, for references and for future control, as the kit evolves."*

**Tiered T3** because it touches `tooling/schema.sql` and the derivation, and because the failure
mode is silent: a vocabulary table that drifts from its shell home would be believed by every
report built on it, which is worse than the current state where nothing joins at all.

Sequencing: this is an enabler rather than a fix — nothing is broken today that it repairs. Worth
doing when a consumer needs it (per-project accelerator extension, or a report that must show
absent values), and worth **not** doing speculatively. `T-20260731-cross-project-accelerator-aggregation`
and `T-20260812-status-has-no-time-dimension-so-daily-ac` are the two most likely first consumers.
