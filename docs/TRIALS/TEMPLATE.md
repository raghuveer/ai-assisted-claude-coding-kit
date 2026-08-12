# Trial: <subject> — <date>

> Copy this file to `docs/TRIALS/<date>-<subject>.md` and fill it in. Do not restructure it:
> a section that exists in one trial's report and not another's cannot be compared, which is
> the whole reason this template exists. Delete nothing — write "not measured" or "n/a" and
> say why. A missing section reads as a clean result.
>
> Procedure: `docs/TRIAL-PROTOCOL.md`. A VOID trial is filed as
> `<date>-<subject>-VOID.md` with the condition it hit and what was established first.

| | |
|---|---|
| Question | *the one written at pre-flight, before the first command* |
| Kit SHA | |
| Time-box / actual | |
| Subject | *languages, size, commit count, age of history* |
| Greenfield / brownfield | *and whether history was truncated* |
| Outcome | COMPLETE \| ABORTED (*cause*) \| VOID (*condition*) |
| Baseline before the kit | build pass/fail, tests pass/fail, duration |
| Instruments verified live | spend rows > 0, findings row landed |
| Copy isolation verified | `git remote -v` printed nothing |

## Cost

**n on every figure, in the figure.**

- BTE by tier / scope / provenance / model — from `kit-status.sh`
- BTE by agent — from the §1 query
- Raw counters, so the weighting can be redone if pricing changes
- Wall-clock and API time, separately

## Findings

- By agent: class, severity, summary
- **Rejected by the recorder** — `finding-gap` rows with reasons. A `rejected` row is a review
  whose findings were lost; a `empty` row is a review that found nothing. They are not the same.
- Escape rate by tier, over **both** provenance populations. If `via:kit` has no denominator,
  say so rather than printing zeroes shaped like a rate.

## Which brownfield degradations bit

- Over-tiering from an empty edge table
- Co-change: usable graph, or withheld
- Planner ordering on a backlog it did not author

## Three kinds of finding

1. **Kit defects** — filed as tasks before any is fixed
2. **Subject defects** — delivered to the owner as a proposal, never applied
3. **Methodology** — folded back into `TRIAL-PROTOCOL.md` §3, with a detection

## Not exercised

*What ran and produced nothing, and what never ran. An untested component named as untested is
information; one omitted reads as fine.*

## Disputed

*Findings the subject's owner disagrees with — both positions, unresolved. The trial measures
whether the kit produced the finding, not whether it is correct.*
