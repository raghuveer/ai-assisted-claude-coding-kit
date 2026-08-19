---
id: T-20260817-one-shared-file-merges-two-whole-epics-s
title: One shared file merges two whole epics so 61 of 77 tasks land in one cluster
epic: planning
tier: T2
lang: bash
paths: tooling/kit-plan.sh, tooling/schema.sql
state: open
---

## Intent

`kit-plan.sh` clusters with union-find over two signals: a declared `epic` (lines 143-147) and a
shared non-hub file (`$1=="S"`, line 118). **Union is transitive**, and nothing bounds what one
union pulls in. So a single shared file between two tasks merges **both of their entire epics**,
and one more shared file merges a third.

Measured 2026-08-17 at `1f83fe8`, and the arithmetic is exact:

    cluster 1 = measurement 16 + validation 14 + portability 10 + agent-contracts 8
              + accelerators 5 + feedback-loop 4 + no-epic 4  =  61   of 77 open tasks

The 19 open tasks that carry `touches` edges span exactly those seven groups —
4 + 4 + 3 + 3 + 2 + 2 + 1 = 19 — and each acts as a bridge. The other ten clusters hold 1-3 tasks
each; **seven are singletons.**

`cluster.hub_cap: 5` is the guard, and here it stops almost nothing. It excludes files touched by
more than five open tasks, which is **exactly one file** — `tests/conformance.sh`, at 12. Three
more sit at exactly 5 (`README.md`, `tooling/kit-index.sh`, `tooling/kit-status.sh`) and pass the
`<=` test, each fusing five tasks. The cap bounds the *file* signal only; nothing bounds the epic
amplification a single bridge produces.

**The author has already met this failure once, from the other direction.** `kit-plan.sh:131-133`:

> Deliberately NOT unioned into a cluster. A dependency says "after", not "about", and layering
> already expresses it. Unioning it too made one chain of 40 tasks transitively fuse every epic it
> passed through: **300 tasks, one cluster, no grouping left.**

Dependency was removed as a union signal for exactly this reason. The same fusion has returned
through the epic-and-file composition that replaced it, and this time there is no comment
recording it because nobody has looked at the cluster sizes since.

**Why it matters beyond tidiness:** a 61-task cluster produces a pack listing 61 task titles and
40 filenames — roughly 2.4k tokens of "most of the repository", loaded for 61 of 77 tasks. The
mechanism's whole claim is that a *group* shares context; a group of 61 is not a group. And the
rank order deliberately keeps clusters contiguous (`before()`, lines 101-107) so that consecutive
sessions share a pack — which does nothing when four fifths of the backlog is one cluster.

## Acceptance criteria

- [x] A cluster-size distribution is **observable**. Today nothing prints it — the degeneration
      was found by querying `plan_item` by hand. `kit-plan.sh` or `kit-status.sh` reports the
      sizes, so this cannot silently return.
- [x] A stated bound on cluster size, and a refusal when it is exceeded. The kit already has the
      shape to copy: `kit-index.sh` **withholds** a co-change graph whose average degree exceeds
      `cochange.max_degree`, on the grounds that a graph answering "everything" is worse than an
      honest unknown. A cluster containing four fifths of the backlog is the same failure and is
      currently emitted with full confidence.
- [ ] **Decide whether 61 is a kit defect, a labelling artifact, or both — and say which.** Seven
      epics genuinely do touch `tooling/kit-index.sh`; that may be true of this backlog rather
      than wrong of the clusterer. This criterion exists so the answer is recorded rather than
      assumed, and a fix that only reshuffles a mislabelled backlog is not a fix.
- [x] Whatever changes, a conformance step covers it with a fixture that would fuse under the
      current rule, so the property is proven rather than true-once.
- [x] `tooling/schema.sql` no longer describes `plan_item.cluster` as *"connected component over
      the dependency graph"*. Dependency was removed as a union signal at lines 131-142 and the
      comment was not updated.

## Notes

Found 2026-08-17 pre-flighting the cluster-pack ROI experiment
(`docs/EXPERIMENTS/2026-08-17-cluster-pack-roi.md` §2(b)).

**Correction on the record, because the first version of this finding was wrong.** It was
originally reported as *"the pack's 40-file cap truncates silently with no degree refusal"*, on
the basis that c1's list hit the `rn <= 40` cap exactly. Cluster 1 touches **42** distinct files,
so the cap drops **two** — a near-empty finding. The operator asked for verification before
filing; counting the population is what replaced it with this one. A round number landing exactly
on a documented limit looks like a finding and is not one until the denominator is counted.
