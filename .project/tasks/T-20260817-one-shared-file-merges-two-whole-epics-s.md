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
- [x] **Decide whether 61 is a kit defect, a labelling artifact, or both — and say which.** Seven
      epics genuinely do touch `tooling/kit-index.sh`; that may be true of this backlog rather
      than wrong of the clusterer. This criterion exists so the answer is recorded rather than
      assumed, and a fix that only reshuffles a mislabelled backlog is not a fix.

      **VERDICT, operator, 2026-08-19: KIT DEFECT — and two independent ones, not one.** The
      labelling is sound and was explicitly cleared rather than assumed.

      *Why not a labelling artifact.* With the file signal switched off entirely (`hub_cap 1`),
      the largest cluster is **16 of 85** — exactly the size of the `measurement` epic. Epics
      group sensibly on their own; **not one epic label was changed** to get that result. Had the
      labelling been a contributor, that measurement would still show a blob. It does not.

      *The two defects, each measured.* **(a)** The file signal admits documentation as
      subject-matter evidence — 28 of 46 leaf files were docs, **61% of the evidence base**. Two
      tasks both editing `README.md` are not about the same thing. **(b)** It accepts a single
      co-edit as sufficient — **34 of 43 links came from one shared file**.

      *Neither is sufficient alone*, which is what makes them independent rather than one defect
      described twice: excluding docs alone gives 67%, requiring two shared files alone gives 58%,
      and both together give **34%**. Fixing either would have left the other.

      *Why `hub_cap` was not simply tuned.* It is inert across its useful range — 5 → 75 of 85,
      3 → 74 of 85 — because it assumes a cross-cutting file is HIGH degree. Here the
      cross-cutting surface is documentation and it is LOW degree: `README.md` and `SECURITY.md`
      at 5 are kept as evidence while `tests/conformance.sh` at 13 is excluded as a hub. The rule
      drops the code that indicates shared subject matter and keeps the prose that does not.
      **Degree is an inverted proxy here**, so a tuned knob would only have looked resolved.
- [x] Whatever changes, a conformance step covers it with a fixture that would fuse under the
      current rule, so the property is proven rather than true-once.
- [x] `tooling/schema.sql` no longer describes `plan_item.cluster` as *"connected component over
      the dependency graph"*. Dependency was removed as a union signal at lines 131-142 and the
      comment was not updated.

## Notes

Found 2026-08-17 pre-flighting the cluster-pack ROI experiment
(`docs/EXPERIMENTS/2026-08-17-cluster-pack-roi.md` §2(b)).

## CLOSE-RECOMMENDATION — 2026-08-19, `ab96c5c`. State stays `progress`.

**Recommending, not deciding.** 5/5 acceptance criteria met, **0 findings recorded against this
task**, so the operator's rule — all findings addressed before a task closes — is satisfied
without exception. Evidence: full conformance **88 passed / 0 failed over 56 steps**; CI green on
all four jobs at `ab96c5c`, including `conformance (macos-latest)`, which matters because the
`ignore_glob` condition is assembled in a shell loop and the union rule changed the `S` query.

Result on this repository: **88% → 34%**, 9 clusters → 18, packs writing again rather than
withheld.

**Two things this does NOT claim, and they are the reason to read before closing.**

1. **Both thresholds are seeded from one backlog.** `cluster.min_shared: 2` and the
   `cluster.ignore_glob` default were chosen against the only backlog available, which is the
   overfitting this repository's own doctrine warns about — the component-model task refuses
   invented field names for exactly this reason. `T-20260808-trial-the-kit-on-one-unfamiliar-brownfie`
   now carries a criterion making the trial the first chance to earn or refute them.
2. **The file signal is thin here regardless.** After both filters it contributes **4 links across
   85 tasks**. On a code-heavy application with genuinely shared modules it would likely carry
   real signal; on this repository it is close to noise either way. That is a fact about the
   subject, not a defect, and it is worth knowing before anyone concludes the signal is valuable.

**A consequence to accept knowingly:** `cluster.max_share` withholds packs when one cluster
exceeds 60% of a backlog of at least `cluster.min_tasks`. That is now a live control on any
adopting project, and it will fire on backlogs whose clustering is genuinely degenerate — which is
the intent, and will still surprise someone the first time.

---

**Correction on the record, because the first version of this finding was wrong.** It was
originally reported as *"the pack's 40-file cap truncates silently with no degree refusal"*, on
the basis that c1's list hit the `rn <= 40` cap exactly. Cluster 1 touches **42** distinct files,
so the cap drops **two** — a near-empty finding. The operator asked for verification before
filing; counting the population is what replaced it with this one. A round number landing exactly
on a documented limit looks like a finding and is not one until the denominator is counted.
