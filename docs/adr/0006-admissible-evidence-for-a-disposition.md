# ADR 0006: Admissible evidence for a disposition

- **Date:** 2026-08-21   **Status:** **REJECTED — do not implement**   **Supersedes:** [[0005-evidence-for-a-disposition-must-be-re-checkable]]   **Related:** [[0004-where-the-plan-lives]]

> **Superseded-by: 7491700**

> **Rejected 2026-08-21 by two reviewers launched concurrently, both returning REJECT with 4
> criticals each and 33 findings, recorded in `7491700`.** Kept rather than deleted, on the same
> grounds as 0005: the review is the value, and the findings against it are recorded against
> `T-20260819-a-finding-whose-subject-no-longer-exists`.
>
> **It failed the way its own predecessor failed, in the same section.** §Consequences claimed
> *"three open criticals close by construction"*. Queried: **all three are MAJOR** —
> check-once-trust-forever, no-retraction and guard-in-the-caller. The five real open criticals
> were different findings. A confident, checkable, false load-bearing claim is what this document
> was written to avoid repeating, in a document whose first line promises every number was
> measured and its command named. *"275 findings carry a summary"* is **297**, restated from
> 0005's rejection banner rather than re-measured.
>
> **The design defect underneath.** The decision says both *"the citation is not stored"* and
> *"matching stays as `kit-resolve.sh` now implements it"*. Those cannot both hold: `git grep -l`
> returns **filenames, not lines**, so with no citation at rebuild the check degrades to
> **presence**. That re-opens at the indexer every defeat `aeaf7ab` closed at the caller three
> hours earlier — any `Superseded-by:` line clears, and self-supersession returns. The re-check
> was weaker than the once-check it replaced, and was presented as a strengthening.
>
> Reproduced independently before any of it was accepted: `.git/HEAD` mtime does not move on
> commit; `:(glob)**`, `*` and `:(icase)` as an agent-supplied `file_path` all matched a marker in
> an unrelated file; a marker inside a fenced code block matches; and the 769 ms measurement was
> scoped to `docs/**`, which covers 7 of the 34 distinct cited paths.
>
> What survived: both tasks this document said it filed **do** exist, unlike 0005 which claimed
> three and filed none. **No successor has been written yet** — which is why the findings against
> this ADR cite the rejection commit rather than an ADR 0007.

Successor to ADR 0005, which was **rejected on the day it was written** with 3 criticals and 22
findings. That document argued the right idea — a disposition must cite evidence the kit can
re-read — and specified the wrong mechanism for it. This one is narrower on purpose: it decides
**what counts as evidence**, and nothing about what happens when evidence drifts, because under the
decision below there is nothing to drift.

Every number here was measured on this repository on 2026-08-21 and the command is named, because
ADR 0005's load-bearing claim was confident, checkable and false.

## Context

### What the shipped mechanism does, and what it costs

`kit-resolve.sh --superseded --by NAME` stores a citation in the event log and checks, once, that
the subject file carries a matching `Superseded-by:` line. Nothing re-reads it afterwards. That
produced four findings still open against `T-20260819-a-finding-whose-subject-no-longer-exists`:
the marker is checked once and trusted forever, `superseded_at` has no retraction, the guard lives
in the caller rather than the writer, and the citation can disagree with the tree.

### The cost is subprocess spawns, not the check

| measured, this machine | |
|---|---|
| full `kit-index.sh` rebuild | **39,249 ms** |
| existing `fixed_commit` walk — 21 SHAs, one `git cat-file -e` each | **9,432 ms — 24% of the rebuild** |
| the same 21 through one `git cat-file --batch-check` | **1,930 ms** |
| `git cat-file -e` ×100 | 376 ms each |
| `grep` a marker from one file ×100 | 379 ms each |
| `git rev-parse HEAD:path` ×100 | 378 ms each |

Three different checks, three identical costs: **the operation is free and the spawn is not.** So
the design question is not *which evidence* but *how many processes per rebuild*, and any option is
affordable if it is batched. This also means the most expensive verification the kit performs today
is the one that already exists, implemented as a loop. Filed separately as
`T-20260821-the-fixed-commit-walk-spawns-one-git-per`.

### Reading at a commit, not in the working tree

| | measured |
|---|---|
| `git grep -lIiE '^[[:space:]>*_]*Superseded-by:' HEAD -- 'docs/**'` | **769 ms**, one spawn |
| the same in a `--depth 1` clone | **works** |
| `git cat-file -e HEAD~5` in that same clone | **fails** |

This matters more than it looks. Reading the marker **from the commit** rather than from the
checkout makes the answer deterministic at a given SHA, immune to sparse and filtered checkouts,
and correct in a shallow clone. Commit-based evidence is the opposite: this repository's own
workflow has **three** `actions/checkout` steps and **one** sets `fetch-depth: 0`, so commit
evidence would lapse in two of three CI jobs for reasons that have nothing to do with evidence.

### Populations, because two design arguments have now been made from imagined ones

| | count |
|---|---|
| distinct cited `file_path`s that still exist | **33** |
| distinct cited `file_path`s that do not | **1** |
| findings carrying a summary | 275 |
| of those, carrying no `file_path` | **0** |
| fix marks citing a commit | 21 |
| fix marks citing nothing at all | **40** |

## Decision

**A finding is excluded from the criticals gate as superseded when BOTH of these hold, and neither
alone is sufficient:**

1. **An operator event** — `finding-superseded`, naming the finding, stamped with actor and time,
   written only by `kit_findings.py` and refused by `kit-event.sh` like every other acting kind.
   This carries **assent**, not evidence.
2. **A marker at the commit** — the finding's `file_path`, read with `git grep` **at `HEAD`** rather
   than from the working tree, carries a `Superseded-by:` line. This carries **evidence**, not
   assent.

The join happens in `kit-index.sh` at rebuild. **The citation is not stored.**

Three consequences follow directly, and they are the point:

- **Adding a marker alone changes nothing.** Without an operator event there is no exclusion, so an
  agent that can edit a document cannot clear a critical. This is what makes the decision safe;
  deriving the exclusion from the tree alone would be a regression against the reservation in
  `.claude/CLAUDE.md`.
- **An event alone changes nothing.** Evidence is re-established every rebuild, so a forged or
  mistaken event excludes nothing once the marker is absent.
- **Removing the marker lapses the exclusion, automatically and fail-closed** — with no drift
  detection, no `meta` counter, no notice, and no retraction verb, because there is no stored claim
  that could survive its evidence. The whole apparatus ADR 0005 proposed becomes unnecessary rather
  than being built and then policed.

**Matching stays as `kit-resolve.sh` now implements it** — equality on the value after the first
colon, both sides normalised (CR stripped, surrounding whitespace and `*`/`_` trimmed, case-folded
because the line is *found* case-insensitively). That rule was earned: containment let `--by '-'`
clear a critical on this repository.

## Options considered

**A1 — the shipped design: store the citation, check it once.** Rejected. It is what produced the
four open findings above. Storing a claim that nothing re-establishes means the record can assert a
present fact that stopped being true, which is what `kit-status.sh` currently does in the present
tense.

**A2 — pin evidence by git blob or tree SHA.** Not rejected on merit and worth naming precisely,
because it is the strongest alternative. Content-addressed, rename-immune, one batched spawn to
verify. It loses to the chosen option on one point only: a blob SHA pins the *bytes*, so any edit to
the subject — a typo fix, a reflow — invalidates the evidence and lapses the exclusion. The marker
is the claim; the rest of the document is not. Revisit if marker matching proves too loose in
practice.

**A3 — commit-evidenced withdrawal (`--commit` verified with `git log --diff-filter=D`).** Rejected
now, with a trigger rather than forever. Its unique coverage is deleted, directory and unanchored
subjects, measured today at **one** finding out of 34 distinct cited paths. Against that: it lapses
at `--depth 1` as shown above, and it is **more** forgeable than a marker, not less —
`git commit --allow-empty -m x` is one command and `kit-guard.sh` matches `Write|Edit|NotebookEdit`,
never `Bash`. ADR 0005 asserted the opposite without naming an adversary.

> **Revisit A3 when a real finding needs it** — a critical on a deleted, directory-shaped or
> unanchored subject that no other verb can clear. One finding is not a population, and building an
> unused, forgeable, CI-fragile route for a case that has not arrived is the *seeded, not earned*
> pattern this project rejects elsewhere.

**A4 — derive the exclusion from tree markers alone, with no event.** Rejected, and this is the
correction that shaped the decision. It is cheapest and it dissolves drift, but with no event there
is no assent: anyone who can edit a document clears every critical on it, including findings
recorded *after* the marker. That is strictly worse than today and it breaks the operator
reservation. **The chosen decision is A4's verification with A1's record**, which is why it is
stated as both-required rather than as a choice between them.

**A5 — require `--commit` on every disposition, uniformly.** Rejected here as out of scope, and
filed rather than waved away: **40 of 61** fix marks cite no commit, so the uniform rule is a
migration affecting two thirds of the existing record. `T-20260821-a-fix-mark-citing-no-commit-is-an-exclus`
owns it. ADR 0005 invoked a fail-closed rule that would have condemned those 40 and exempted them by
fiat, which is the non-discriminating argument ADR 0004 had already had struck once.

## Consequences

**Three open criticals close by construction rather than by a new mechanism** — check-once-trust-forever,
no-retraction, and guard-in-the-caller, since the derivation moves into the indexer where it binds
for every caller.

**One `git grep` per rebuild, ~769 ms**, replacing a per-finding file read. It does not scale with
the number of dispositions, only with the size of the searched tree — the opposite of the walk it
sits beside.

**`superseded_by` stops being stored.** The column and the `--by` argument remain as the operator's
statement of intent and are checked against the marker at mark time for a good error message, but
nothing downstream reads a stored citation. The four marks already recorded need no migration: their
markers exist and will be re-derived.

**The gate becomes a function of `(log × commit)`.** That is a real change and it is deliberate: at
any SHA the answer is reproducible, which the working-tree formulation in ADR 0005 was not.

**A rename lapses the exclusion** until the finding is re-anchored or the marker moves with the
file. Measured concentration: all four superseded marks share **one** path, so today a single
`git mv` lapses 100% of them. Stated because ADR 0005 asserted this trade was acceptable without
ever computing the number that decides it.

## What this decision does NOT cover

- **What happens when *commit* evidence drifts.** `fixed_commit` still cites commits and still keeps
  its exclusion when they vanish. That is untouched here and is a separate decision, deliberately
  not smuggled in — it affects 21 existing marks and the 40 that cite nothing.
- **Forgery of the event itself.** A direct append to `events.ndjson` bypasses every writer;
  `kit-guard.sh` does not match `Bash`. Requiring a marker narrows the window — a forged event
  excludes nothing without one — but does not close it.
- **Who may run a disposition.** Operator convention in `.claude/CLAUDE.md`, mechanically
  unenforced by design, for the reasons `Via:` is.
- **Batching the `fixed_commit` walk.** Worth ~7.5s of every rebuild on its own merits and
  independent of this decision. Filed.
