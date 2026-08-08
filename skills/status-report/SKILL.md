---
name: status-report
description: Regenerate and report project status — open work, escape rate by tier, and trailer-discipline warnings. Use when asked how a project is going, what is open or blocked, or whether the review tiering is calibrated.
---

# status-report

Status is derived, never maintained. There is no file to update.

## Procedure

```sh
bash ${CLAUDE_PLUGIN_ROOT}/tooling/kit-index.sh
bash ${CLAUDE_PLUGIN_ROOT}/tooling/kit-status.sh
```

Read the generated file and summarise it. Never edit it — it is overwritten on every
run, and an edit is silently lost, which is worse than being refused.

## Reading escape rate

Escape rate per tier is the number that says whether the pipeline works: changes at a
given tier that later needed a fix carrying `Fixes-Escape-Of:`. A tier escaping
materially above the others is under-reviewed for the modules it covers, and the
correct response is to raise the floor for those paths in `tier.rule:` — not to add
reviewers everywhere.

**Two columns, and neither one is "the" escape rate.** `via:kit` counts only work this
pipeline actually ran, which is the number that says whether tiering works. `all` counts
every task, which on a brownfield repository is mostly work the kit never saw and will
read lower for that reason alone. Quote the one that answers the question asked, and say
which one it is — a rate given without its population is not a measurement.

Read them together rather than separately. `via:kit` far above `all` is the pipeline
looking worse than the codebase, which usually means too few tasks are labelled. The two
converging means the kit has run on most of the backlog.

**Other provenance** carries its own escape count for a reason: that line is what makes a
recorded escape impossible to lose when a task is labelled out of `via:kit`. If it ever
shows escapes, they are real escapes — they are simply not attributable to this pipeline.

Treat small numbers as small numbers. Two escapes out of three tasks is not a rate.

## Trailer discipline

If the generated file carries the trailer-discipline warning, say so first and qualify
everything after it. An empty backlog from an under-tagged repository is a measurement
failure that reads exactly like an idle project, and acting on it wastes real work.

## Deeper queries

For anything the generated view does not answer, query the index directly rather than
reading task files. Findings by language and class:

```sh
sqlite3 .project/index.db "
  SELECT lang, class, COUNT(*) FROM finding
   GROUP BY lang, class ORDER BY 3 DESC;"
```
