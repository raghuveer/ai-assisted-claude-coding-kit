# ADR 0001: Anchor entry-mechanism facts to files, not to an aggregation unit

- **Date:** 2026-08-15   **Status:** Proposed   **Supersedes:** —   **Related:** [[0002-verify-kill-condition-targets-by-reading-them]]

## Context

The kit has no way to turn an existing codebase into a first task list. A first design
(`docs/design-input/2026-08-15-entry-mechanism.md`) proposed a per-directory inventory
("areas"): marker-file stack detection, per-directory churn, and a *rationale map* that
classified doc-shaped files by name and path. Two independent approach reviews rejected it.

A prototype implementing exactly that design's five inputs was then run against three real
repositories, and the measurements falsified the central invention rather than qualified it:

- On this repository, `tooling/` — 21 files, 1,554 comment lines, 34.1% density, the densest
  rationale in the project — reported **zero** rationale sources under the area model. The map
  would have asked the question it was built to prevent.
- On prometheus, 13 of 23 areas reported zero rationale, including `config` (224 files), `cmd`
  (87), `util` (83). Doc-shaped files were 4.1% of the tree and `docs/` held 32 of the 68.
- Directory attribution destroyed history: `(root)` absorbed 72% of prometheus's commits and
  94% of actix-web's.
- Marker files discriminated nothing: all 13 actix-web areas resolved to `Cargo.toml`; the
  prometheus `web/` area carried `go.mod` *and* `package.json`.

The second design (`docs/design-input/2026-08-15-entry-mechanism-2.md`) starts from the
problem, not from a patch. It serves
`.project/tasks/T-20260814-one-entry-mechanism-brownfield-is-the-ge.md`. The operator
walkthrough against that document is complete and the decision below is taken.

## Decision

**Entry facts anchor to files. The tool counts and locates; the model groups and judges.**

`kit-entry.sh` emits one row per tracked file — path, extension, line count, comment-line
count, comment-block count, commit count, first/last commit date, authors, doc-shaped flag,
co-change degree — to `entry-facts.tsv`, plus a bounded `entry-report.md` whose every section
states its ranking key in the heading. **No artefact contains an aggregation unit.** There is
no "area", no per-area stack, no per-area churn, and no rationale map that infers absence of
rationale from a directory's contents. Any claim of the shape "this area has no rationale" is
exactly the claim design 1 could not support, and the mechanism does not make it again.

Comment localisation — the closest thing to a replacement for the rationale map — is emitted
as a **third artefact, uncapped and unthresholded**: `entry-comment-runs.tsv`, one line per
comment run (`path · start · end · length · token`), no ranking, no cap, no minimum-length
filter applied on the way out. This was not the first cut. A capped, ranked top-40 report
section was measured against a blind ground truth of ten in-scope, independently nominated
rationale sites in this repository: recall was 6/10 into that section and did not move between
a 4-line and a 12-line threshold, because the runs a lower threshold added all landed below the
cap. Removing the cap and emitting every run — with no threshold applied by the tool at all —
raised recall to 10/10 in scope. **The cap was losing 40% of the sites the artefact exists to
surface, and it was the cap, not the threshold, doing it.** The same shape reproduced on a
large subject: at a 10-line threshold prometheus yields 921 runs and a top-40 cap keeps 4.3% of
them; at 5 lines, 1,515 runs and 2.6% kept. A capped ranked list is the tool pre-forming the
answer with under 5% of the data; an uncapped TSV lets the model apply its own ordering with
`Grep`.

## Alternatives considered

- **Per-area inventory (design 1's model).** Rejected on measurement, not argument — see
  Context. Three subjects, both failure directions (over-collapse in this repo, under-coverage
  in prometheus; history and marker-file collapse in prometheus and actix-web).
- **An `ingest.extra` adapter emitting candidate task rows.** Rejected. An adapter can
  genuinely `INSERT INTO task`, so this route places unconfirmed candidates directly in the
  backlog count and the escape-rate denominator with nothing refusing them. Worse than design 1
  knew, since design 1 never checked whether the adapter boundary could write.
- **Extending `kit-index.sh` to do this work.** Rejected, unchanged from design 1: its
  `--if-stale` incremental model runs per session; a whole-tree entry walk is a once-per-adoption
  act, and folding one into the other conflates two different cadences.
- **A skill-only approach — no script, the model runs `git` itself.** Considered live, not
  dismissed by default: with the deterministic half now thinner than design 1 assumed, this was
  a closer call than before. Still rejected as the primary design, because counting comment
  lines and locating comment blocks across the tree is arithmetic the tool does deterministically
  and reproducibly; a model doing the same counting produces a number nobody can regression-test
  or compare between trials. It remains the fallback of last resort — see Consequences — not the
  fallback of first resort the first revision of the design proposed, since that earlier framing
  deleted the only structural write control in the design (see the unmet-hold consequence below)
  and specified the replacement in one paragraph.
- **A batch `--confirm` writer.** Excluded by the operator's standing decision that a task list
  stays unconfirmed until questions are answered. A gate satisfied by passing a flag is
  laundering the same hold it claims to enforce.

## Consequences

**Easier.** Per-file facts survive every failure mode measured against the area model: a
single-commit vendor import, an empty co-change table, a 20,000-file monorepo, files with no
extension. Each degrades to a stated `ok | empty | degenerate | unavailable`, never to a silent
zero that reads as "no rationale here" when it is really "did not look."

**Harder.** The model now does the grouping and judging that the area model tried to do for
free. On a large tree this means reading more of `entry-facts.tsv` and
`entry-comment-runs.tsv` than a curated top-K report would have asked of it. That cost is
accepted because the curated version was wrong, not merely expensive.

**New failure modes, named rather than hidden.**

- **The hold on the task list is not enforced by mechanism.** `kit-entry.sh` cannot write a
  task file — that is structural, the one place this design does gate. But the orchestrator
  holds `Write` and `Bash`, `kit-guard.sh` permits every in-root path, and `kit-task.sh` refuses
  nothing but an id collision. The acceptance criterion "hold the task list unconfirmed until
  questions have answers" is met by **convention**, not by mechanism. This ADR records that as
  an accepted, known gap, not a solved one.
- **The candidate-title charset restriction is enforced by nobody.** Restricting candidate
  titles to `[A-Za-z0-9 ._-]` is an instruction to the model about its own output; the tool
  never sees the titles it would need to check, and no fixture can gate what only the model
  produces. This is the same shape as the hold above — convention bounding the actor the
  convention exists to bound — and is recorded as the second instance of it in this design,
  distinguished only in that a mechanical fix exists and is cheap (`kit-task.sh --title-file`,
  filed separately) and has not yet landed.

  > **Superseded 2026-08-15, during implementation.** This is now enforced. The premise — "the
  > tool never sees the titles" — was true of the design as written, where the tool wrote facts
  > and the model wrote the proposal with nothing reading it back. Building the proposal half
  > added a reader: the orchestrator writes the file, then `kit-entry.sh --check` validates it,
  > and at that point the titles are in front of a deterministic tool. It refuses any candidate
  > title containing a quote, backtick, `$`, `;`, `|`, `&`, `<`, `>` or parenthesis, and a
  > conformance step proves each refusal against a mutation that removes the check.
  >
  > Recorded rather than edited away, because the reasoning was sound and the conclusion still
  > became false — an artefact's boundaries change when something new reads it, and a
  > convention worth writing down is worth re-checking when the shape moves. **The hold above
  > is NOT superseded and remains convention.**
- **A sixth of this repository's load-bearing rationale is permanently outside the mechanism's
  reach.** The blind ground-truth set used to measure the localiser named twelve sites; two —
  `docs/DESIGN-NOTES.md:398-433` and `.gitattributes:1-19` — are not code comments at all, and
  no comment scanner reaches them at any threshold. The report must not imply completeness it
  does not have.

**Invariants that must hold.** No artefact this mechanism writes may contain an aggregation
unit above the file. If a future change introduces one — an area, a per-directory rollup, an
inferred "no rationale here" — it reopens the question this ADR closes, and needs its own
review against the same three-repository evidence, not an assertion that this time is different.

## References

- `docs/design-input/2026-08-15-entry-mechanism-2.md` (this decision's design input, read in
  full)
- `docs/design-input/2026-08-15-entry-mechanism.md` (superseded; rejected by two approach
  reviews)
- `docs/design-input/2026-08-15-localiser-measurement.md` (recall table, nominated sites, the
  4.3%/2.6% cap figures on prometheus)
- `.project/tasks/T-20260814-one-entry-mechanism-brownfield-is-the-ge.md`
