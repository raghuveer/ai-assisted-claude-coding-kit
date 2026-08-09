---
id: T-20260808-report-escape-rate-over-both-populations
title: Report escape rate over both populations instead of filtering to one
epic: measurement
tier: T2
lang: bash
paths: tooling/kit-status.sh
state: done
---

## Intent

`kit-status.sh` now computes escape rate `WHERE t.via='kit'`. The reason was sound: the metric
was diluted by work the pipeline never ran on, which on a brownfield adoption is most of the
backlog. The implementation introduced a worse failure than the one it fixed.

**Filtering can make an escape disappear.** The T3 review of that change found it twice:

- One documented command — `kit-event.sh <task> via` — wrote a JSON blob into `task.via` and
  dropped a task carrying a recorded escape out of the report entirely. The `escaped` event
  stayed in the database and nothing anywhere mentioned it. Fixed at the derivation, but the
  shape survives: anything that moves a task out of `via='kit'` removes its escapes from the
  only place escapes are ever surfaced.
- Provenance is retroactively rewritable. A later `chore:` commit carrying `Via: manual` is
  exempt from the Task-Id requirement, passes even `--enforce`, and silently relabels a task
  out of the measured population. Nothing warns that a value changed, and nothing warns that a
  task carrying escapes has left.

Nine findings remain open on the provenance task, and two exist only because of the filter:
the folded-trailer case that drops `Fixes-Escape-Of`, and the excluded block counting TASKS
rather than ESCAPES. Both are patches on a design that can read zero while the database says
otherwise.

## The change

Report BOTH populations rather than filtering to one:

    ## Escape rate by tier
    - T2   1 / 7      over via: kit
    - T2   1 / 34     over all tasks
    excluded from the first: agent 3, manual 12, unknown 19  (0 escapes among them)

The un-diluted number is what the filter was for and it is still there. The honest denominator
is back. And no escape can vanish, because nothing is excluded from the report — only from one
of its two columns. The count of escapes among the excluded population is the assertion that
makes disappearance impossible rather than merely unlikely.

## Acceptance criteria

- [x] Both rates reported, each labelled with its population, and neither presented as THE
      escape rate. One row per tier, `via:kit` beside `all`, with the framing text saying in
      as many words that neither alone is the escape rate and why each is misleading on its
      own.
- [x] Escapes attached to excluded tasks are counted and shown. **Other provenance** carries
      `N task(s), M escape(s)` per value. Counting tasks alone was the old shape and is exactly
      the one that reads clean: "12 excluded" says nothing about whether any of the twelve
      escaped.
- [x] A report that can read zero while the database cannot is impossible by construction. The
      `all` column carries no `WHERE`, so it reaches every task in the index; the only escape it
      cannot reach is one attached to no task row, and that residue is counted and named
      separately. The two are exhaustive by construction, not by inspection.
- [x] A conformance case asserts exactly that: `T-esc` records an escape while `via: kit`, is
      relabelled to `manual` by a later `chore:` commit, and its escape stays visible in `all`
      and in the provenance breakdown. The `via:kit` column is allowed to drop it — that is the
      column's job — and the test asserts the drop as well, so the two columns are pinned apart
      rather than merely both present.
- [x] The identity is asserted rather than spot-checked: escapes shown plus residue equals
      escapes stored.
- [x] Re-examined below.

## What this did to the nine findings on the provenance task

Two of the nine are answered, as predicted, though not both in the way predicted.

**Closed, fixed** — *the excluded block counting TASKS rather than ESCAPES*. Directly repaired
rather than obviated: the block now counts both. Mutation-proven — reverting only the escape
count in that query turns the conformance step red on its own.

**Closed, no longer applicable** — *retroactive relabelling with no audit*. The finding's teeth
were that a later `chore:` commit carrying `Via: manual` silently moves a task out of the
measured population and takes its escapes out of the only report that shows escapes. Relabelling
still happens and is still unaudited, but it can no longer hide anything: the escape stays in
`all` and is named under its new provenance. That exact sequence is now the conformance case.
What remains — no history of *when* provenance changed — is a smaller and different concern
about the audit trail, not about metric integrity, and it should be re-filed in those terms if
it is still wanted rather than left to inherit this one's severity.

**Still open, untouched by this change**: the folded-trailer case that drops `Fixes-Escape-Of`,
the missing CHECK constraint, the single-definition test being blind to other spellings, and the
adapter documentation.

**Partly addressed**: *kit-status hardcoding `kit`*. Splitting the rate into two columns would
have taken the literal from two occurrences to four, so the value is now named once as `KITVIA`
and the column label is built from it. That is duplication removed, which is not what the
finding asks for — it wants the value DERIVED rather than stated — so the finding stays open on
its own task. Recorded here because this change is why the count moved.

## Notes

This is the answer to a question asked directly: is finishing the nine open findings the best
move, or is there a better way. Two of the nine are stabilising and seven are hardening — and
both stabilising ones exist because the metric filters. Deleting the failure mode is smaller
than patching it twice.

Recording the general principle, because this repository has now met it three times: a metric
that EXCLUDES a population can silently read clean; a metric that PARTITIONS one cannot. The
same argument applies to spend by provenance, which already partitions and is therefore fine,
and to the tier-floor report, which excludes nothing.

## Measured while building it

**The residue branch cannot fire today.** It was written as the last piece of the exhaustiveness
argument, then tested, and the test would not go red: `kit-index.sh` materialises a task row for
any id it sees in a trailer, `Fixes-Escape-Of:` included, so an escape pointing at a task with no
file becomes an escape pointing at an untiered `unknown` phantom — which the `all` column already
counts. An empty `Fixes-Escape-Of:` produces no event at all, so that route is closed too.

It is kept rather than deleted, because the phantom behaviour is itself
T-20260808-a-task-id-matching-no-task-file-is-count, whose acceptance criteria include checking
every derived metric for the same shape. Fixing that defect is exactly what makes this branch
live, and a guard written afterwards is a guard nobody thinks to write. Conformance covers it by
seeding the row into the index directly — legitimate here because the index is derived and
disposable, and the unit under test is `kit-status.sh` reading a state `kit-index.sh` does not
yet produce.

**On this repository the section previously read `_no kit-run task recorded yet_`** over 47
tasks, because not one commit has ever carried a `Via:` trailer. The filter was not diluting the
metric here; it was erasing it. It now shows the per-tier distribution across all 47.

**`schema.sql` comments are inside the index fingerprint.** SQLite stores the CREATE TABLE text
verbatim in `sqlite_master`, so the comment added to `via` moved the printed index hash
(`79021e93…` → `d923228d…`) while `EXPECT_HEAD` was untouched. Only HEAD is asserted, so nothing
failed, and both platforms hash the same bytes — but a pure-comment edit and a schema change are
indistinguishable in that number, which is worth knowing before reading a fingerprint diff as
drift.

## T2 review, and the one thing it found

One adversarial reviewer, as T2 requires — `security-reviewer` was not spawned, because this is a
reporting path and none of the high-stakes classes its own description names are touched.

It re-derived the three mutation claims rather than believing them, building three mutated copies
and confirming each is red alone. Then it found a fourth thing, and it was in the guarantee
itself.

**`fail-open`, major — a NULL id in `task` silences the entire residue count.** The subquery read
`task_id NOT IN (SELECT id FROM task)`. SQLite does not enforce NOT NULL on a TEXT PRIMARY KEY,
so `task` can hold a NULL id, and `x NOT IN (set holding NULL)` is NULL rather than true for
*every* x. One such row takes the orphan count to zero and hides every orphan, not only its own.
Reproduced against the real `schema.sql` before accepting it: residue 1 → NULL row accepted → 0,
and the filtered subquery restores 1.

That is this task's own failure mode, arriving through the guard written to prevent it, and
`by construction` was therefore overstated: a second precondition — ids are never NULL — was
load-bearing and disclosed nowhere, while the first (phantom rows) got ten lines of comment.
Fixed at the reader that makes the claim, with the precondition now written down beside it.
Unreachable today, since `kit-index.sh` guards every insert and is the only writer — which is
precisely the status of the phantom-row branch, and the same argument applies: a guard written
after someone relaxes the upstream discipline is a guard nobody thinks to write.

A fourth mutation now holds, red alone: dropping `WHERE id IS NOT NULL` fails the escape step and
nothing else (31 passed, 1 failed). Conformance 32/32 with it. The index fingerprint did not move
— `d923228d…`, unchanged — because the fix is in `kit-status.sh` and touches no schema text.

The schema-level answer, `CHECK (id IS NOT NULL AND id <> '')`, is deliberately NOT taken here.
It belongs to the missing-CHECK finding already open on
`T-20260808-record-how-a-task-was-executed-so-kit-wo`, and closing it there will not make this
line redundant: the constraint owns the invariant, this line owns the claim.

Also raised and correctly not filed against this change: a task's frontmatter `tier:` is never
validated the way a `Tier:` trailer is (`kit-index.sh:336`), so a malformed value can produce an
oddly-labelled row in the tier table. Exhaustiveness is unaffected — the escape is still counted,
just under an unexpected label — and `kit-index.sh` is untouched here. Pre-existing, and filed
separately if it is wanted.
