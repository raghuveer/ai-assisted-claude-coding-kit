---
id: T-20260808-report-escape-rate-over-both-populations
title: Report escape rate over both populations instead of filtering to one
epic: measurement
tier: T2
lang: bash
paths: tooling/kit-status.sh
state: open
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

- [ ] Both rates reported, each labelled with its population, and neither presented as THE
      escape rate.
- [ ] Escapes attached to excluded tasks are counted and shown. A report that can read zero
      while `SELECT COUNT(*) FROM event WHERE kind='escaped'` is non-zero must be impossible by
      construction, not by care.
- [ ] A conformance case asserts exactly that: a task with a recorded escape, relabelled out of
      `via='kit'`, still has its escape visible in the report.
- [ ] Re-examine the nine open findings on
      T-20260808-record-how-a-task-was-executed-so-kit-wo afterwards. Two should close as
      no-longer-applicable rather than be fixed; say which and why, rather than silently
      dropping them.

## Notes

This is the answer to a question asked directly: is finishing the nine open findings the best
move, or is there a better way. Two of the nine are stabilising and seven are hardening — and
both stabilising ones exist because the metric filters. Deleting the failure mode is smaller
than patching it twice.

Recording the general principle, because this repository has now met it three times: a metric
that EXCLUDES a population can silently read clean; a metric that PARTITIONS one cannot. The
same argument applies to spend by provenance, which already partitions and is therefore fine,
and to the tier-floor report, which excludes nothing.
