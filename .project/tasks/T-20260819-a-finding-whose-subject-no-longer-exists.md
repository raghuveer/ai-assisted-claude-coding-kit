---
id: T-20260819-a-finding-whose-subject-no-longer-exists
title: A finding whose subject no longer exists has no disposition so it blocks a gate forever
epic: feedback-loop
tier: T3
lang: bash
paths: tooling/kit-resolve.sh, tooling/kit-status.sh, tooling/kit-preflight.sh, tooling/kit-index.sh, tooling/kit-event.sh, tooling/kit_findings.py, tooling/schema.sql, tests/conformance.sh, docs/TRIAL-PROTOCOL.md, .claude/CLAUDE.md
state: completed
---

> **Retiered T2 → T3 on 2026-08-21, by the project's own floor rule rather than by judgement.**
> `tier.rule: tooling/kit-index.sh T3`, and floors are never ceilings. The implementation had to
> teach the indexer a sixth acting kind, which the original `paths:` did not anticipate.
>
> **An earlier version of this note said the floor report could not see the under-declaration.
> That was wrong, and an approach review refuted it.** `kit-index.sh:1293` raises `tier_floor`
> from **`touches` edges**, which come from commit trailers — not only from declared `paths:`.
> `T-20260813-nine-criticals-predate-summary-and-canno` declares three files, none of them
> `kit-index.sh`, and is reported `recorded T2, floor T3` today by exactly that route.
>
> The true and weaker statement: a `touches` edge exists only **after** the commit is made and the
> index rebuilt, so the report is **late, not blind** — it names a landed commit as under-tiered
> rather than stopping one. Filed as
> `T-20260821-kit-trailers-never-checks-tier-against-t`.

## Intent

The kit can record three things about a finding, and none of them fits the case that turns out to
be the most common one on a design review:

| command | claim |
|---|---|
| `kit-resolve.sh --fixed` | it was addressed |
| `kit-resolve.sh --unassessable` | it cannot be judged at all |
| `kit-vindicate.sh --false` | it was never a real defect |

**Nothing says "the thing this criticised no longer exists."**

Measured 2026-08-19 on `T-20260814-one-entry-mechanism-brownfield-is-the-ge`, which carries 64 open
findings — **more than half of every open finding on a closed task in this repository**. Of those,
**31 are reviews of `docs/design-input/2026-08-15-entry-mechanism.md`**, and design 2 opens by
rejecting design 1 outright: *"That design was rejected twice"*, and §A — *"Design 1's per-area
inventory. **Reject — now measured, not argued**"*, falsified against three real repositories.

Every one of the three existing dispositions is **wrong** for those 31:

- `--fixed` is false. Nothing was fixed; the design was abandoned.
- `--unassessable` is false. They are perfectly assessable — the record is intact and the
  reasoning is legible. That mark is for the nine findings that predate the `summary` column and
  have nothing left to judge.
- `--false` is the worst of the three. They **were** real. Being real is why the design died.

So they sit in the gate permanently, and under the operator's rule that all findings must be
addressed before a task closes, **`one-entry-mechanism` can never close no matter how much work is
done on it.** A gate that cannot be satisfied by any amount of correct work is the same failure the
`--unassessable` route was built to remove, arriving one category over.

## Acceptance criteria

- [x] A finding can be recorded as **superseded** — its subject was withdrawn, rejected or replaced
      — distinctly from fixed, unassessable and false. The distinction is the point: a review that
      killed a design is evidence the review worked, and collapsing it into "fixed" erases that.

      `kit-resolve.sh --finding ID --superseded --by NAME`, recorded as a `finding-superseded`
      event and derived into `finding.superseded_at` / `superseded_by`. Routed through the SAME
      deferred array in `kit-index.sh` as the other two marks, which is what makes a mark naming an
      unknown id get *reported* rather than run as an UPDATE that matches nothing and exits 0.
- [x] The mark **names what superseded it** — the ADR, the revision, or the commit that withdrew
      the subject. `--reason` is required on `--unassessable` because a mark that clears a gate
      without saying why is laundering; this is the same requirement for the same reason.

      `--by` is required and refused blank, in `kit_findings.py` rather than in the shell, so it
      holds for every caller instead of for one path.
- [x] It **leaves the gate and stays in the record**, exactly as `--unassessable` does, and
      `kit-status.sh` reports the count separately rather than folding it into zero. A design that
      was rejected because a review found 31 problems is a fact worth keeping.

      It also caught a **false claim that was already there**: the "none outstanding" line read
      *"N critical finding(s) recorded, all marked addressed"*, which had been untrue since
      `unassessable_at` existed and became untrue a second way here. It now reports
      `13 addressed, 13 excluded` rather than asserting a disposition for every row.
- [x] **The route is not reachable for a finding whose subject still exists.** `--unassessable`
      already refuses a finding that carries a summary; this needs the equivalent guard, or it
      becomes the escape hatch for anything inconvenient — which would make the whole findings
      record worthless.

      **The obvious guard does not work, and finding that out shaped the real one.** The subject
      here — `docs/design-input/2026-08-15-entry-mechanism.md` — is still on disk, still 15KB, and
      still referenced by an ADR and by its own successor. Rejected designs are KEPT. What ended is
      its STANDING, and standing is not a property of the filesystem.

      So the guard is a **withdrawal marker in the subject itself**: `--superseded` is refused
      unless the finding's `file_path` carries a `Superseded-by:` line naming what `--by` names.
      Refused when the finding records no `file_path`, when the file is **absent** (deleting the
      evidence must not be the cheapest way out of the gate), when the marker is missing, and when
      the marker names something else. The withdrawal is then reviewable in a diff and lands in
      front of the next reader of the subject.

      The measurement that justifies the strictness: on this one task, **26 of 57 open findings
      point at subjects that are still live** — design 2, `tooling/kit-entry.sh`, conformance, an
      ADR. A verb guarded only by "did you pass `--by`" would have cleared all 57.
- [x] `.claude/CLAUDE.md` gains it in the operator block alongside `--fixed` and `--unassessable`,
      and it is **operator-reserved for the same reason**: a session deciding its own findings are
      moot is the signature that carries no information.
- [x] A check that can fail, covering both directions: a finding on a live subject must be refused,
      and a superseded one must leave `kit-preflight.sh --criticals` while still being counted by
      `kit-status.sh`.

      Six assertions, four of them refusals, and the refusals come first so the acceptance cannot
      be the only thing the step proves. It fails on the pre-fix code: `--superseded` did not
      exist, so the refusals would pass vacuously and the acceptance would fail.

### Added during implementation — the gate grew an exclusion its report could not see

Not in the original criteria, and it is the same defect as the one the period-one retro named:
**a fix at the site that leaves the consumer unchanged.** `kit-preflight.sh --criticals` gained a
fourth exclusion, and `TRIAL-PROTOCOL.md` §0 — the box that exists to expose what the gate does not
count — had no way to see it. Within minutes of the verb landing, this repository passed
`--criticals` with **thirteen** excluded criticals behind the zero.

- [x] `kit-preflight.sh --superseded`, mirroring `--unassessable`: exit 0 either way, because a
      standing exclusion is a figure the report carries, not a stop.
- [x] A §0 box that calls it, and a report-template line, so the next trial can compare.
- [x] The two counts are **never summed**. An unassessable critical is unreadable — a gap in the
      record. A superseded one is perfectly readable, was real, and its subject was withdrawn
      because of it. Merging them would erase the difference between missing evidence and evidence
      that worked.

### The suite caught a hole this change opened, which is the whole reason it is shaped that way

`tooling/kit-event.sh` refuses to write any kind `kit-index.sh` MUTATES a row for, because that
script validates nothing and splices its third argument in as raw JSON. The conformance step
derives that list from the indexer's own `k=="..."` branches rather than restating it, so teaching
the indexer a sixth acting kind without guarding it **goes red instead of quietly reopening the
hole.** Its comment said so in advance; it then did it.

The hole was real and total: `kit-event.sh T-x finding-superseded '{"finding":"<id>","by":"y"}'`
would have cleared a critical from the gate with `kit-resolve.sh` never invoked — **forging past
the marker guard that is the entire point of this task**, and past the operator reservation in
`.claude/CLAUDE.md`, by the same route that once forged `finding-fixed`.

- [x] `finding-superseded` added to the refusal in `kit-event.sh`. Verified in both directions: the
      forge exits 2, an ordinary `progress` kind still appends.

**Nobody remembered to do this. A derived list did.** That is the difference between a check that
restates a rule and one that reads its source — and it is the argument for writing the next guard
the same way.

## Notes

Found 2026-08-19 while walking the 64 findings on `one-entry-mechanism` at the operator's request,
after measuring that 325 open findings existed against 17 ever marked fixed and asking which of
them were real.

**The population is not homogeneous, and that was the actual finding.** Of the 64: 31 are reviews
of a rejected design, 15 review the design that replaced it, and 18 anchor to code — of which five
were verified fixed and marked, one **critical remains live** (`kit-entry.sh` still contains the
`[^']*` sed capture), and `--` guarding is still partial (`head` has it, `grep` and `awk` do not).

**Not a licence to clear the backlog.** This disposition applies only where the subject is
genuinely gone. The 206 findings on `progress` tasks are unaffected, and so are the nine remaining
criticals, which all carry summaries and are therefore ordinary fix work.

Related: `T-20260813-nine-criticals-predate-summary-and-canno` built `--unassessable` for the
adjacent case and is the model to follow — including its refusal guard, which is the criterion here
most likely to be skipped.
