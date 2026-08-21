# ADR 0005: Evidence for a disposition must be re-checkable

- **Date:** 2026-08-21   **Status:** **REJECTED — do not implement**   **Supersedes:** —   **Related:** [[0004-where-the-plan-lives]]

> **Rejected 2026-08-21 by an approach review, on the day it was written, with 3 criticals and 22
> findings.** Kept rather than deleted, because the review is the value: this document is the
> worked example of the failure it was written to prevent, and the findings against it are recorded
> against `T-20260819-a-finding-whose-subject-no-longer-exists`.
>
> **Three claims below are FALSE and were verified false against the live index.** They are left in
> place, unedited, so the record shows what was asserted:
>
> 1. **§Consequences, "the cell is empty now and will not stay empty"** — the load-bearing
>    justification for admitting commits as evidence. Measured: **275 findings carry a summary and
>    0 of those are unanchored**; the 114 anchorless ones all fall between 2026-08-08 and
>    2026-08-10, the pre-`summary` era. Reasoned from the contract, never from the behaviour.
> 2. **§Context, "one `DELETE FROM meta`"** — in a table headed *"verified rather than assumed"*.
>    There are **three** writes (`kit-plan.sh:523`, `:536`, `:540`), two of them value inserts,
>    both keys read by `kit-status.sh` and written by nothing in `kit-index.sh`. Filed as
>    `T-20260821-kit-plan-writes-two-meta-keys-the-indexe`.
> 3. **§Decision part 2's fail-closed argument does not discriminate** — the same defect ADR 0004
>    had struck from it. Applied consistently it condemns **40 of 61** fix marks that cite no
>    commit, and 9 `unassessable` marks unre-checkable by construction, all exempted here by fiat.
>    Filed as `T-20260821-a-fix-mark-citing-no-commit-is-an-exclus`.
>
> **And the three "filed" claims in §What this does not cover were untrue when written.** Nothing
> was filed. They are filed now, which is how this note can say so.
>
> **The successor should be two documents, not one**, per the review's recommendation:
> **(a) admissible evidence for a disposition** — a closed set, content-pinned, with the matching
> rule and its normalisation defined, applied uniformly to all four verbs or explicitly not; and
> **(b) what the kit does when evidence drifts** — decided separately, with the shallow-clone case,
> the 4-of-4 concentration measurement, and the attribution requirement in front of it, and with
> the middle options costed rather than skipped. Two options this document never considered belong
> in (a): **pinning evidence by git blob SHA** (content-addressed, rename-immune, needs no
> normalisation) and **deriving supersession from tree markers at index time**.

Written after a T3 review chain returned **REVISE / REJECT / REVISE** on `051fc31`, the commit that
added the `superseded` disposition. Two reviewers independently recommended a decision record of
roughly this shape, and the operator independently arrived at the same question from a different
direction — *what happens when the thing that superseded something is itself deleted.*

This ADR is about **what makes a gate exit honest over time**, not about storage.

## Context

### What already exists, verified rather than assumed

| | |
|---|---|
| `.project/events.ndjson` | tracked, append-only, `merge=union text eol=lf` — **the authority** |
| `.project/index.db` | gitignored, dropped and rebuilt from `schema.sql` on every run — **derived** |
| direct writes to the store | one `DELETE FROM meta` on a derived cache key, `kit-plan.sh:540` |

**The kit is already event-sourced and already keeps its authoritative log append-only in git.**
Dispositions are not row updates; they are projections of `finding-fixed`,
`finding-unassessable` and `finding-superseded` events. ADR 0004 exists specifically to remove the
second writer that broke this. Nothing in this ADR changes that, and no defect that prompted it is
a storage-engine defect.

### The actual gap

Every disposition cites evidence, and the log records **the citation, not the evidence**. The
evidence lives outside the log and can leave without a trace:

| disposition | evidence | re-checked on rebuild |
|---|---|---|
| `--fixed --commit SHA` | a commit | **yes** — `kit-index.sh:1471-1482` walks every `fixed_commit`, records `finding_fix_commit_missing`, warns |
| `--superseded --by X` | a `Superseded-by:` line in the subject | **no** |
| task closure | the task file's frontmatter | **no** — `T-20260809-a-deleted-task-file-is-indistinguishable` |

The middle row is new and is what the review chain rejected. `kit-status.sh` states, in the present
tense, that *"the subject file itself carries a matching `Superseded-by:` line"* — a claim that was
true once, at mark time, and that nothing re-establishes. The bottom row is the operator's
scenario: delete the superseding artefact and the exclusion stands with its justification gone.

**One sentence covers all three.** The `fixed_commit` walk is the working prototype of the answer;
it needs generalising, not replacing.

### What the guard actually was

The marker check is `grep -qF -- "$by"` against the whole marker line. Reproduced on the live
repository, not argued:

    kit-resolve.sh --finding <id> --superseded --by '-'
    kit: superseded recorded

`-` is a substring of the literal text `Superseded-by:`, so it satisfies every marker line that
exists. The self-supersede refusal below it is exact equality against a substring match, so one
dropped character defeats it too. Repairing the bogus mark then demonstrated a second finding:
`superseded_at` has **no retraction** — `--open` clears only `fixed_at` — so the only remedy was a
corrected mark winning on last-write-wins, and the false event is in the committed log forever.

## Decision

**A disposition may only cite evidence the kit can re-read on every rebuild, and drift in that
evidence is fail-closed and reported.**

Three parts:

**1. Admissible evidence is a closed set.** Two forms, each re-checkable by a command the kit
already runs:

- **a commit** — re-checked with `git cat-file -e`, as `--fixed --commit` is today;
- **a marker in a named file** — re-checked by re-reading the file.

A citation that is neither is refused at the writer. `--by` as free text is not evidence; it is a
label on evidence.

**2. Evidence is verified at index time, and its absence returns the finding to the gate.**
On every rebuild, each disposition carrying evidence is re-verified. If the evidence no longer
resolves, the exclusion **lapses** — the finding counts again — and the drift is recorded in `meta`
and surfaced by `kit-status.sh`.

This is stronger than the `fixed_commit` precedent, deliberately. That walk reports the drift and
leaves the finding excluded: *"The finding still reads as addressed and its evidence resolves to
nothing."* On a **release gate**, that is the wrong direction. The project's own fail-mode rule —
*"does every 'cannot decide' branch on a security-relevant path DENY"* — says an exclusion whose
justification has evaporated is an exclusion the kit can no longer justify. **The `fixed_commit`
walk should be reconsidered against this rule; it is filed, not changed here**, because widening a
gate-lapse to marks made under the old contract is a migration and not a bug fix.

**3. Matching is equality on an extracted value, never containment.** The marker's value — the text
after the key — must equal the citation after normalisation. Containment is not naming, and a
citation the tree does not name is the clearance this whole mechanism exists to refuse.

## Options considered

**A. Keep the marker guard as shipped, fix only the substring bug.** Rejected. It closes the
reproduced defeat and leaves the class: the guard would still be evaluated once and trusted
forever, which is the failure the operator's scenario describes and which the substring bug merely
made easy to demonstrate.

**B. Disable deletes, or restrict permissions on the store.** Rejected, and it is worth recording
why so it is not proposed again. The deletions in question are **git operations on files** — a
deleted task file, a deleted design document — not SQL `DELETE`s. There is no table to protect:
the database is gitignored and rebuilt from scratch every run, and locking a derived cache
protects nothing. `rm` on a working tree is not revocable by the kit.

**C. Move to an event-sourced append-only log.** Rejected **as already done**. This is the
architecture: `events.ndjson` is the authority, tracked and union-merged; `index.db` is a
projection. The proposal describes the status quo, which is itself worth recording — the gap was
not visible as "evidence outside the log" until someone proposed the thing that already existed.

**D. Adopt RocksDB alongside or instead of SQLite.** Rejected on four independent grounds:

1. It is a **mutable** embedded key-value store. Append-only would be a convention there exactly as
   it is in SQLite — no property is gained, only a second place to enforce one.
2. It would replace the **derived cache**, which is the one component deliberately disposable. The
   authoritative log stays a text file in git either way, so the failure mode is untouched.
3. It has **no `sqlite3`-equivalent CLI**. The portable core is 18 shell scripts, `sqlite3` and
   text files; RocksDB needs C++/Rust/Go/Python bindings, putting a compiled dependency into the
   layer that must stay maintainable without GenAI.
4. **Not one of the 38 findings from the review chain is about SQLite.** Changing the store would
   answer a question nobody asked and leave every question that was asked open.

Git is already doing the job a durable log needs: content-addressed history, review by diff,
`merge=union`, and signable commits. RocksDB provides none of those and removes human readability.

**E. Require evidence to be re-checkable, verified every rebuild.** Chosen. It is the generalisation
of a mechanism already in the tree, it covers findings and tasks with one rule, and it is the only
option under which the sentence `kit-status.sh` already prints becomes true.

## Consequences

**A route appears for subjects that have no marker to carry.** A deleted subject, a directory, and
a finding with no `file_path` are all refusable under the current guard and all become expressible
once a commit is admissible evidence — `git log --diff-filter=D` for a deletion. This matters:
`file` is **optional** in the finding contract while `summary` is **required**, so the population
that can carry a summary and no anchor is unbounded going forward. Measured today: **114 of 389
findings carry no `file_path`, and 0 of those carry a summary**, so the cell is empty now and will
not stay empty. Design-level findings — the exact population `superseded` targets — are the least
likely to be file-anchored.

**A commit is harder to forge than a marker.** A marker is one line anyone can type into a file. A
commit must exist and be reachable in the history. Where both are available, the commit is the
better evidence, which inverts the shipped design's preference.

**Rebuild cost rises by one file read per distinct cited path**, alongside the `git cat-file` per
`fixed_commit` already paid. Negligible at present scale and bounded by the number of dispositions,
not by repository size.

**A legitimate rename re-reds the gate.** This is intended. The evidence moved; re-point the
citation. A gate that silently tolerates evidence it can no longer find is the gate this ADR exists
to prevent.

**The permanence of a mark becomes load-bearing** and must be stated where the operator reads it,
because there is no retraction verb. A mark on a mistyped-but-valid id permanently excludes a real
critical, and this was demonstrated during the review, not imagined.

## What this decision does NOT cover

- **It does not make a disposition unforgeable.** A direct append to `events.ndjson` bypasses every
  writer, and `kit-guard.sh` matches `Write`/`Edit` but not `Bash` redirection. Re-checking evidence
  narrows the window — a forged mark citing evidence that does not resolve now lapses on the next
  rebuild — but a forged mark citing *real* evidence still stands. Provenance of the mark itself is
  a different problem and is not solved here.
- **It does not change `fixed_commit`'s current behaviour.** That walk reports drift and keeps the
  exclusion. Bringing it under part 2 is a migration affecting marks made under the old contract,
  and is filed rather than decided here.
- **It says nothing about who may run a disposition.** That remains the operator convention in
  `.claude/CLAUDE.md`, mechanically unenforced by design, for the reasons `Via:` is.
- **It does not address the tier floor binding late.** `kit-trailers.sh` validates `Tier:` for
  syntax only and never against `tier.rule`, so a T3-floored change can ship under a `Tier: T2`
  trailer — as `051fc31` did. Surfaced by the security review, filed separately.
