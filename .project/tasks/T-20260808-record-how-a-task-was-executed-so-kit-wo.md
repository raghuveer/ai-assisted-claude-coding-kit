---
id: T-20260808-record-how-a-task-was-executed-so-kit-wo
title: Record how a task was executed, so kit work and other work are distinguishable
epic: measurement
tier: T3
lang: bash
paths: tooling/schema.sql, tooling/kit-index.sh, tooling/kit-status.sh, tooling/kit-task.sh
state: open
---

## Intent

Nothing in the kit records HOW a task was done. `task` carries tier, state, epic, lang and
owner; `event` carries actor; `finding` carries agent and model. None of them answers "did
this project's own review pipeline run on this work, or did a human do it, or did a coding
agent do it without the kit."

Two things depend on that answer and neither can be given today.

**The value question.** Whether the kit pays for itself is comparative by nature — kit-run
work against work done the other ways — and a comparison needs the two populations labelled.
This is the measurement the README's central bet rests on.

**Escape rate, which is already wrong in a way nobody sees.** `kit-status.sh` computes escape
rate by tier over EVERY task, regardless of whether the review pipeline ever ran on it. On a
brownfield adoption most tasks are pre-existing or hand-done, so from the first day the
headline metric that the whole tiering design rests on is diluted — and diluted in the
direction that makes tiering look ineffective. A metric that cannot distinguish "reviewed and
nothing escaped" from "never reviewed" is the same open-circuit failure the findings loop had.

## Acceptance criteria

- [x] A task records how it was executed, from a CLOSED vocabulary, defaulting to unknown.
      `kit | agent | manual | unknown`, defined once in `kit_via_vocab()` in `kit-lib.sh`.
      A value outside it is not stored: the indexer writes `unknown` instead, so a typo
      cannot invent a fifth population.
- [x] It is recorded the way state already is -- a `Via:` trailer validated by the same hook
      that validates `Task-Id` and `Tier`, and a frontmatter key for tasks that never reach a
      commit. One vocabulary, defined in ONE place, asserted by a test.
      Trailer beats frontmatter, the same precedence and for the same reason as tier: git
      records what actually happened, frontmatter declares an intent. Verified -- a task
      declaring `via: manual` in its file, committed with `Via: agent`, indexes as `agent`.
      The single-definition rule has its own conformance step, and that step builds its search
      pattern by calling `kit_via_vocab` rather than spelling the list out, because spelling it
      out made the test file the second copy. It caught itself on the first run.
- [x] Every derived metric that mixes the populations either filters by it or prints the mix.
      Escape rate by tier read `WHERE t.via='kit'` and said so in the report, with the excluded
      population listed BY VALUE beneath it. Spend gained a **By provenance** split, because
      "did the kit pay for itself" is a comparison and a comparison needs both populations
      labelled. The tier-floor report was checked and deliberately left alone: under-tiering is
      a property of the task, not of who did the work.
      **Superseded 2026-08-09 by T-20260808-report-escape-rate-over-both-populations.** The
      filter was the wrong half of "filters by it or prints the mix": it could make a recorded
      escape disappear. Escape rate now PARTITIONS — `via:kit` and `all` side by side — and only
      spend still filters, which is safe there because spend cannot go missing by being
      relabelled. The criterion held; the option it chose did not.
- [x] A task with no value recorded is visibly absent from a comparison rather than counted
      into one -- the same rule spend already follows for unattributed rows.
      `unknown` is excluded from the rate and printed as itself. It is never folded into
      `manual`: one says nobody recorded it, the other is a claim about what happened.
      **Amended 2026-08-09, same supersession.** `unknown` is no longer absent from the rate;
      it is absent from ONE COLUMN of it and present in the other, still printed as itself and
      still never folded into `manual`. "Visibly absent from a comparison" was satisfied by
      exclusion and is now satisfied by labelling, which is strictly stronger: exclusion also
      hid whatever the excluded population had escaped.
- [x] The human gate is preserved. A model may propose the value; a human confirms it, exactly
      as `kit-task.sh` requires for a task itself. A self-reported `via: kit` from the agent
      that did the work is the one value nobody should take on trust.
      Nothing in the kit writes this value anywhere. `kit-task.sh` does not set it, no hook
      sets it, no agent sets it; it appears only where a person typed it. The working
      agreement in `templates/CLAUDE.kit.md` states it in those terms, and **the commit
      implementing this carries no `Via:` trailer** -- it would have been the first
      self-report, and it indexes as `unknown` like anything else nobody vouched for.

## Outcome

    task.via   kit | agent | manual | unknown, NOT NULL DEFAULT 'unknown'
    Via:       trailer, validated by kit-trailers.sh against kit_via_vocab()
    via:       frontmatter key, for a task that never reaches a commit
    event      kind 'via', so history holds what actually happened

Measured on a fixture with all four cases:

    T-kit   via: kit in frontmatter                    -> kit
    T-man   via: manual in frontmatter, Via: agent      -> agent      (trailer wins)
    T-none  nothing anywhere                            -> unknown
    T-bad   via: made-up                                -> unknown    (not stored)

and the report:

    ## Escape rate by tier
    _Over work this pipeline ran on (`via: kit`)..._
    - T2  0 / 1
    **Excluded from the rate above**
    - agent  1
    - unknown  2

The report shape above is what this task shipped and is kept as the record of it. It was
replaced on 2026-08-09 — see the supersession note on the third criterion — by two labelled
columns plus per-value escape counts, on the same fixture:

    - T2         0 / 1 via:kit     0 / 4 all
    **Other provenance** — in the `all` column above, not in `via:kit`
    - agent    1 task(s), 0 escape(s)
    - unknown  2 task(s), 0 escape(s)

Mutation-verified three ways: removing the `via='kit'` filter, removing the vocabulary guard,
and removing the trailer precedence each turn the conformance step red on their own.

## Notes

Confirmed with the operator 2026-08-08 as required, not optional: model identification with a
human gate is wanted.

`unknown` is load-bearing on a brownfield adoption, where most of the backlog will be
back-filled from an existing roadmap and nobody will remember how each item was done. The
honest default is unknown, and the honest report says how much of the sample it covers.

Blocks T-20260808-trial-the-kit-on-one-unfamiliar-brownfie: a trial without this produces
data that cannot be interpreted afterwards.

Recorded T3, not the T2 it was proposed at: it touches `tooling/kit-index.sh`, which carries a
T3 floor, and the kit reported `recorded T2, floor T3` on the next reindex. Raised before the
work rather than after, which is the only order in which a tier is a control.

---

## T3 review round (2026-08-10) — REJECTED, do not close

Two reviewers, read-only (`Read, Grep, Glob` enforced by `--allowedTools`, not requested in
prose), launched as separate processes at the same moment so the second was blind to the first.
`implementation-reviewer` (sonnet) returned **REJECT** with 5 findings; `security-reviewer`
(opus) returned **REVISE** with 7, explicitly excluding everything already filed. 12 findings
recorded. **Both may not be closed over: the working agreement forbids approving with major
findings pending.**

**Both agree the headline property holds.** An escape cannot be hidden by relabelling
provenance: `all` carries no `WHERE`, excluded values are counted under `Other provenance`, and
the residue guard is NULL-hardened. The second reviewer tried the trailer, the frontmatter, the
derivation and the residue and could not break it. That half is sound and should not be
re-litigated.

Every claim below was re-verified by hand before being written here.

### Must fix before this task closes — these are this task's own defects

**1. `Via: unknown` is accepted by the hook and silently discarded by the indexer** (major).
`kit-index.sh:518` guards on `viaok(via) != "unknown"`, but `unknown` **is in the vocabulary**
(`kit-lib.sh:88`), so no `via` event is written and the derivation's `COALESCE` falls back to
the frontmatter. Consequences: a task whose frontmatter says `via: kit` — the one value the
design says nobody should take on trust — **cannot be demoted by a human's trailer**, and a task
promoted by an earlier `Via: kit` can never be retracted. Movement into the measured population
is one-way. The only working retraction is `Via: manual`, which this task's own design forbids
conflating with `unknown` ("one says nobody recorded it, the other is a claim about what
happened"). The tool forces exactly the conflation the design prohibits. The comment at
`kit-index.sh:515-517` — "A value outside the vocabulary is DROPPED" — is also false: an
in-vocabulary value is dropped too.

**2. The fail-closed derivation filter has no test; deleting it leaves the suite green** (major).
`kit-index.sh:904-906` (`AND e.payload IN (…)`) is the entire content of commit `a4a51a0`, added
because `kit-event.sh <task> via` wrote a whole JSON line into `task.via` and dropped a task
carrying a recorded escape out of the report. **`kit-event.sh` appears zero times in
`tests/conformance.sh`** (verified: `grep -c` returns 0), and both provenance steps use only
vocabulary-valid values, so every fixture already satisfies the `IN` clause. Remove the hardening
and the suite stays 100% green. This is §1 exactly — the check prints PASS when the thing under
test is absent — and the three mutations this task cites do not touch it.

**3. `0 / 0 via:kit` is a rate with an empty denominator, printed like a measurement** (major).
Live in this repo right now, `STATUS.generated.md:65-68`: all four tiers read `0 / 0 via:kit`
against 58 tasks, and nothing on the page says the column is empty. The honest fallback string
at `kit-status.sh:213` is now unreachable, because `ESC` is grouped over every task and so is
never empty merely because the kit population is. This is this task's own stated defect
reintroduced in the new column: *"a metric that cannot distinguish 'reviewed and nothing escaped'
from 'never reviewed' is the same open-circuit failure the findings loop had."* It is the day-one
state of every adopter and the permanent state of this repo.

**4. `INSTALL.md` gives adopters the wrong frontmatter key** (major). `INSTALL.md:173` says to
set `Via:` in task frontmatter; the indexer reads lowercase `v["via"]` (`kit-index.sh:335`).
`Via: manual` in a task file lands in `v["Via"]`, is never read, and indexes as `unknown` with no
warning. Back-fill is the **only** route for work finished before adoption — you cannot add a
trailer to a commit already written — so this silently breaks the exact population the design
calls load-bearing. The correct spelling appears in one user-visible place, a line printed only
when `Other provenance` is already non-empty.

**5. The human gate is prose, and the prose is addressed to the agent it means to exclude**
(major). **Found independently by both reviewers** — the only convergent finding, and the
strongest signal in the round. Nothing checks *who* wrote the trailer: `kit-trailers.sh:123-128`
validates vocabulary membership only, so any actor with commit access — including a coder agent
this kit spawns with git access — can write `Via: kit` into its own commit and have it indexed as
legitimate. Worse, `.claude/CLAUDE.md:19` and `templates/CLAUDE.kit.md:17` say *"**You** set it,
not the agent that did the work"* in the two files loaded into **the agent's** context every
session; read by its actual audience, "you" is the agent. `INSTALL.md:176` states it correctly to
a human. Acceptance criterion 5 was closed on the narrower claim that no kit *script* writes the
value, which is true and does not establish that a person typed it — §3.

### Pre-existing, and NOT to be folded into this task

Filed separately or already filed; recorded here so the round's output is complete.

- Folded trailer drops its continuation (`T-20260809-a-folded-git-trailer-loses-its-continuat`,
  open). Names `Via` as sharing the broken record parse — worth re-verifying when that lands.
- The single-definition vocabulary check is blind to reformatting: `grep -F "kit agent manual
  unknown"` cannot see `schema.sql:25`'s `kit | agent | manual | unknown`, which is a live second
  copy inside the searched tree that the guard reports PASS on.
- `KITVIA=kit` hardcoded at `kit-status.sh:206`; no `CHECK` constraint behind the residue guard's
  NULL precondition.
- `WHERE t.via<>'kit'` drops a NULL `via` from **Other provenance** while `all` still counts its
  escapes, falsifying the claim that nothing is excluded from the report. Unreachable today
  (`NOT NULL DEFAULT 'unknown'`), and that is precisely the standing of the two NULL guards this
  same file already writes and tests — third instance of the same SQL-NULL miss.
- `t.via` is interpolated into the report unescaped (`kit-status.sh:219`) on a rationale that the
  same comment block contradicts; a `via` of `<!--` can silence the sections beneath it.

### What the reviewers said they did not check

Neither ran anything — read-only by design. Neither checked the adapter path end to end, and the
second noted the `kit-index.sh:518` sibling guard is untested for its stated threat model
("a commit that skipped the hook") but masked by the derivation filter.
