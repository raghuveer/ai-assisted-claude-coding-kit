---
id: T-20260808-co-change-has-no-eval-harness-so-its-sco
title: Co-change has no eval harness so its scoring cannot be improved
epic: measurement
tier: T3
lang: bash
paths: tooling/kit-index.sh, docs/DESIGN-NOTES.md
state: open
---

## Intent

Co-change exists to answer blast radius on a repository with no `touches` edges — the
brownfield case, where it is the only signal available on day one. Its measured quality is
**recall@10 = 0.24, 2.4x a popularity baseline**, recorded once in `docs/DESIGN-NOTES.md` on
2026-07-31. Three quarters of genuinely related files are missing, which the schema comment
correctly tells consumers to read as "and at least these".

Two things follow, and neither is being acted on.

**There is no harness.** 0.24 is n=1, produced by hand. Any change to the scoring — and the
parameters were themselves tuned by measurement, so tuning is the established method here —
cannot be evaluated, because nothing re-runs the measurement. The number cannot move because
nothing can tell whether it moved.

**The lever is scoring, not storage.** External research on 2026-08-08 evaluated five graph
databases against this exact table and the verdict was unambiguous: no engine changes which
files come back. `cochange(src,dst,weight)` is a precomputed weighted adjacency list and the
query is one indexed `ORDER BY weight DESC LIMIT 10`. What moves recall is a different scoring
function, and every candidate is computable in the tools already present:

- **Adamic-Adar or common-neighbour normalisation** — down-weight pairs that co-occur only
  because both are popular. Directly attacks the popularity baseline the current score barely
  beats.
- **Temporal decay** — a 2023 co-change and last month's are currently worth the same.
- **Personalised PageRank** seeded on the task's touched files, instead of one-hop weight.
  At ~900 nodes this is twenty iterations of a power method — an awk loop, or a fixed
  three-join SQL expansion.

## Acceptance criteria

- [ ] A harness that computes recall@k against a held-out ground truth, re-runnable on demand,
      so a scoring change produces a number rather than an opinion. Ground truth needs stating
      explicitly: the obvious candidate is files that actually changed together in commits held
      out of the training window.
- [ ] The current scoring re-measured through the harness, to confirm it reproduces 0.24 before
      anything is changed. A harness that cannot reproduce the known number is measuring
      something else.
- [ ] At least one alternative scoring measured against it, with n and the held-out window
      stated. Report the result even if it is worse — a scoring change that loses is as useful
      to record as one that wins, and the minimum-edge-weight parameter was already rejected
      that way.
- [ ] `docs/DESIGN-NOTES.md` updated so the recall figure carries its method and its date, and
      is no longer a single number with no way to reproduce it.
- [ ] The storage question recorded as CLOSED with its reasoning, so it is not re-opened: five
      engines evaluated, four disqualified by the no-daemon/no-runtime constraint or licence,
      the fifth (RyuGraph, MIT, genuinely embedded) rejected on cost-benefit at this scale.

## Notes

Raised by research on 2026-08-08 that set out to evaluate graph databases and concluded the
question was misdirected: the bottleneck is signal quality, and the kit has no way to measure
whether it improved. That is a more useful finding than any of the engines.

Related: T-20260731-validate-the-priority-weights-against-es is the same shape one layer up —
a set of weights nobody has validated against outcomes.

Recorded T3, not the T2 it was filed at: it declares `tooling/kit-index.sh`, which `tier.rule`
floors at T3, and the kit reported `recorded T2, floor T3` on the next reindex. Raised before
the work rather than after.
