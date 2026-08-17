# Experiment design: do cluster packs pay for themselves?

**Status: DRAFT, PRE-REGISTRATION, UNSIGNED. Nothing has been spent and nothing runs until the
operator signs §3 and §10.**

Task: `T-20260808-cluster-packs-are-generated-and-read-by-` (T2).
Kit SHA at drafting: `383432b`.
Written 2026-08-17, before any arm was run, because a design assembled after the numbers is
rationalisation. `docs/TRIAL-PROTOCOL.md` says the same thing about trials and this document
follows its rules where they apply — it is a sibling of that document, not a replacement.

**This is an experiment, not a feature.** *"Packs do not pay — stop generating them"* is a
legitimate outcome and it deletes code. §9 names exactly what gets deleted, in advance, so that
outcome cannot quietly become "inconclusive, keep it".

---

## 1. The claim, and the two rival mechanisms nobody has separated

The kit asserts a saving in two places, and they are not the same assertion.

`tooling/kit-plan.sh:305-313` claims a **cache** mechanism:

> written once per plan and byte-identical thereafter, so it belongs ABOVE the cache breakpoint
> and is served at 0.1x instead of being re-read at full price in each session.

`skills/task-context/SKILL.md:38-49` claims an **avoided-derivation** mechanism:

> the pack already named the cluster's files — do not re-derive them.

These predict *different signatures in the recorded counters*, which is the whole reason this
experiment is worth running rather than argued:

| | Mechanism | Prediction if true |
|---|---|---|
| **H1** | The pack is served from cache at 0.1× | `cache_read` share rises in the pack arm; `tok_in` roughly flat |
| **H2** | The pack replaces exploratory derivation | tool-call count and `tok_in` fall in the pack arm; cache share ~flat |
| **H0** | Neither — the pack is net cost | pack arm ≥ no-pack arm on BTE |

**H1 is doubtful as the mechanism is built, and this is a claim to test rather than one to
repeat.** The pack is read by a `Read` tool call at step 4 of the skill — that is, *inside* the
conversation, after the index refresh in step 1 and the task file in step 3, both of whose
outputs vary per task. A tool result arriving mid-conversation is below the cache breakpoint
described in `docs/HANDOFF.md` §4.6, not above it, and the prefix has already diverged before it
arrives. Byte-identity across sessions buys nothing if the bytes never sit in a shared prefix.

The skill also tells the agent to place the pack *"early and verbatim, before the task spec"* while
listing it as step **4**, after the task spec is read at step 3. Those two instructions cannot both
be followed. Recorded here as an observation, not fixed — see §12.

**The vendor's ~75% figure is not a target, a hypothesis to beat, or a number to repeat.** The
task file already says so. No arm of this experiment is sized to reproduce it.

---

## 2. Pre-flight finding: the packs on this repository are degenerate today

Reproduced 2026-08-17 on `383432b`, by rebuilding derived state and reading it. Every number
below is from a command run in that session, not from the design.

`plan_item` was **empty** and `goal` held **no rows** — while six pack files sat in
`.project/packs/default/`, orphaned from a plan that no longer existed in the index. By the
skill's own step 4 (*"No row means no plan covers this task — skip the pack"*), **not one task in
this repository could have loaded a pack**, and the files on disk would not have been consulted
by any agent following the procedure.

Re-running `bash tooling/kit-plan.sh` produced 11 clusters and 11 packs. What they contain:

| Observation | Value |
|---|---|
| Open tasks | 77 |
| Tasks in cluster 1 | **61 (79%)** |
| Singleton clusters | **7 of 11** |
| c1 pack size | 115 lines / 9,470 bytes (order 2.4k tokens) |
| File rows in c1's "Files this cluster touches" | **40 — exactly the `rn <= 40` cap** |
| Open tasks with any `touches` edge | **19 of 77**, all in cluster 1 |
| Packs whose file section reads *"none recorded yet"* | **10 of 11**, covering 58 of 77 tasks |
| Findings in the index | 316 |
| Findings with `vindicated = 1` | **0** — all 316 are NULL |
| Packs with a non-empty "Confirmed defect classes" section | **0 of 11** |

Three of these are structural, not incidental:

**(a) The file list can only describe work that has already been done.** `kit-plan.sh:351` joins
`edge … rel='touches'` and nothing else. Those edges come from commit diffs carrying a `Task-Id`
(`kit-index.sh:645`), so a task with no commits has no files — and the pack is consulted precisely
when starting a task, i.e. when it has none. The kit has already met and fixed this exact gap
elsewhere: `kit-index.sh:206-213` adds frontmatter `paths:` as a second source for tier floors
because *"7 of 8 open tasks in a real backlog had no touches edges … A floor that only sees
touched files therefore passes silently on every task that has not started."* **82 of 104 task
files declare `paths:`. The pack query does not read it.**

**(b) A 40-file list is the "answers everything" failure the kit refuses elsewhere.** For 61 of 77
tasks the pack names 40 files — most of the source tree. `kit-index.sh` deliberately *withholds*
a co-change graph whose average degree exceeds `cochange.max_degree`, on the stated grounds that
a graph answering "everything" is worse than an honest unknown. The pack has no equivalent
refusal and hits its cap silently. Its list also includes
`tooling/__pycache__/kit_findings.cpython-314.pyc` — a build artifact, unfiltered.

**(c) The third section is empty by construction here.** It requires `finding.vindicated = 1` and
this repository has never marked one. So the pack's prior-evidence section carries no evidence.

### What this does to the experiment

Running an A/B today measures **a 2.4k-token list of 61 task titles plus 40 filenames** against
**nothing**. That is a real measurement of the artifact as it exists, and it is not a measurement
of the idea. A "does not pay" result from it would be true of this implementation and would tell
us nothing about whether a pack that named 5 relevant files and 3 confirmed defect classes would
pay — which is the thing the design claims.

Reporting the degenerate result as *"cluster packs do not pay"* would be the same error the kit
has already documented twice: a green-but-meaningless check, and a summary that upgrades a narrow
result into a broad one.

---

## 3. The decision the operator makes before anything is spent

Three routes. They differ in cost and in what the answer means.

| | Route | Spend | What a result means |
|---|---|---|---|
| **R1** | **Fix the pack, then measure.** Land the `paths:` fallback, a degree refusal, and artifact filtering first; re-plan; then run §4. | Fix work (unestimated) + §10 budget | Tests the *idea*. The strongest answer, and the slowest. |
| **R2** | **Measure as-is, knowingly.** Run §4 on today's packs and report the result as scoped to this implementation. | §10 budget only | Tests *this artifact*. Cheap, honest, and cannot license the general claim. |
| **R3** | **Stop and delete now.** Treat §2 as sufficient: the mechanism is unreachable (no `plan_item`), its file list is empty where it matters, and its evidence section has never been non-empty. | ~zero | Saves the whole budget. Forfeits the measurement the task asked for. |

**Recommendation: R1, restricted to cluster 1.** §2(a) is a one-source-to-two-source change the
kit has already made once in `kit-index.sh` and can copy; without it, 58 of 77 tasks can never
receive a pack with any file information, and the experiment has no population. R3 is defensible
and is *not* recommended only because §2's faults are all in the pack's derivation rather than in
its premise — deleting on this evidence discards the idea to punish the implementation.

**If R2 is chosen, the report title is fixed in advance:** *"the cluster pack as generated on
2026-08-17 does/does not pay"* — never *"cluster packs do/do not pay"*.

---

## 4. The arms, pre-registered

### Design: paired, within-task

The acceptance criterion as written asks for *"two tasks in one cluster, one arm with the pack and
one without"*. **That design confounds the arm with the task** — a difference of 30% between two
different tasks is not evidence about packs, because two tasks never cost the same. Proposed
amendment, for sign-off: **the same task, run in both arms, in separate copies, from the same
commit.** Task difficulty is then held exactly constant and the pair difference is attributable.
n is the number of *pairs*, and it is stated on every figure.

Sessions do not share state, so the second run is not contaminated by the first; each arm gets its
own `git clone --no-hardlinks` copy verified with `kit-preflight.sh --isolated`.

### The three arms

| Arm | Setup | What it isolates |
|---|---|---|
| **A — pack** | `kit-plan.sh` run in the copy; `plan_item` row exists; pack on disk | the mechanism as intended |
| **B — no plan** | `kit-plan.sh` **not run**; no `plan_item` row, no pack directory | the control |
| **C — stale pack** | plan generated, then files renamed/deleted in the copy so the pack names paths that no longer exist | AC4: is a confident wrong pack worse than none |

**Arm B is defined as "no plan", not "pack file deleted".** Deleting the file leaves a `plan_item`
row pointing at a missing path, which is a *third* condition (a broken pack) and not the control.
With no plan the skill takes its own documented branch — *"No row means no plan covers this task —
skip the pack"* — so the only difference between A and B is that a plan exists.

**Checked, and it constrains the protocol:** `plan_item` is read by exactly two consumers —
`skills/task-context` step 4, and `kit-plan.sh`'s own `--show`/`--next`. So the arms differ only
in the pack, **provided the task id is given to the agent explicitly**. Never let an arm choose its
own work with `--next`; that would reintroduce the plan as a second variable.

### Stage 1 and Stage 2 — a budget gate, not two experiments

**Stage 1 (cheap): context assembly only.** Each run invokes only the `task-context` skill and
stops, reporting the files it loaded. This isolates precisely what the pack is supposed to change —
derivation cost — at a fraction of a full task. It separates H1 from H2 (§1) on the counters, and
it is the only stage needed to answer *"is there a delta worth chasing?"*.

**Stage 2 (expensive): the full task, arms A and B, with review.** Required for the quality
criterion — a cheaper assembly that omitted the right file shows up nowhere in Stage 1. Stage 2
runs **only if** Stage 1 clears the threshold in §9, and that threshold is fixed now.

---

## 5. The subject

**A `--no-hardlinks` clone of this repository, per arm, per pair.**

Justified: it has 104 tasks, real history, a populated co-change graph, and 19 tasks carrying
`touches` edges — the only population where a pack has any file content at all. A fresh subject
would have to be adopted, tiered and planned first, which is a trial (`TRIAL-PROTOCOL.md`), not
this experiment.

**Stated bound, to appear in the report:** the kit's own backlog has unusually well-formed task
files. Packs will look *better* here than on an arbitrary brownfield repo, and no figure from this
experiment may be quoted as a rate for one.

**The precondition that is not negotiable:** every run goes through
`claude --plugin-dir <kit> …` against the copy. The kit's hooks fire only when it is loaded as a
plugin; a run from a development session records `scope=main` rows that conflate every agent, and
the experiment would produce a confident wrong number. This was established 2026-08-16 by a probe
that recorded `scope=subagent`, `agent=general-purpose`, 42,491 BTE for one trivial subagent.

**Task selection, pre-registered:** pairs are drawn from **cluster 1 only** (the only cluster whose
pack carries files), from tasks that are `open`, tiered T1–T2, and have no `blocked_by`. The
specific ids are written into this file before the first run and not changed afterwards.

---

## 6. The unit and the instruments

**BTE, exactly as `TRIAL-PROTOCOL.md` §1 defines it**, weights read from their single home
(`BTE=` in `tooling/kit-status.sh`) and never retyped. Per-agent figures come from that section's
query against the `spend` table. Raw counters are recorded alongside every weighted total, because
weights are a pricing assumption and a weighted total cannot be un-weighted.

**Do not use the harness's per-agent completion summary.** It is final context size, not cost —
reconciled at 0.012% against summed last-context while differing from output work by 5–215×.

Pre-flight, per §0 of the trial protocol and for the same reasons:

- [ ] `bash tooling/kit-preflight.sh --spend` passes **in the copy**, after one throwaway agent.
- [ ] `bash tooling/kit-preflight.sh --isolated <copy>` returns zero for every copy.
- [ ] `git status --short` clean before each `kit-index.sh`, or the index read is early.
- [ ] `kit-index.sh` and `kit-status.sh` run clean in the copy.

**The criticals pre-flight (`--criticals`) is not a gate on this experiment** and saying so here is
deliberate: it gates *trials on someone else's codebase*. This runs on a copy of our own repo with
no remote. If the operator wants it applied anyway, that is a sign-off decision, and today it would
block — 17 unfixed criticals, nine of them awaiting the `--unassessable` marks.

---

## 7. AC1 — proving the pack was actually read

*"The skill says to read it"* is not evidence. Three independent checks, all required:

1. **Transcript tool-use.** The session transcript must contain a `Read` `tool_use` whose path is
   the pack. `kit-spend.sh --transcript` already locates transcripts; the check is a grep for the
   pack path in a `tool_use` block, not in prose.
2. **Negative control.** Arm B's transcript must contain **no** read of any path under
   `.project/packs/`. An arm that reads a pack it was not given voids that pair.
3. **Downstream use.** The agent's own report names files, and in Arm A those names must be
   traceable to the pack rather than to a fresh `sqlite3` or `grep`. Recorded by comparing the
   report's file list against the pack's, and against the tool log for independent derivation of
   the same names.

Check 3 is the one that distinguishes *read* from *used*, and it is the one most likely to fail.
If it does, that is a finding about the skill, not a void pair.

---

## 8. AC3 — the quality side, and the trap in measuring it

The claim is that a pack removes repeated derivation **without** removing depth. A cheaper arm that
finds less has disproved the claim, not supported it.

**The trap:** scoring "did the agent touch the right files" against the pack's own file list scores
Arm A against its own answer key. That measures compliance, not correctness.

**Ground truth is sealed before the runs.** For each selected task the operator writes the files the
acceptance criteria actually require, into a file committed **before** the first arm runs. Both arms
are scored against that list — precision and recall of files loaded, and of files changed.

**Review is blind to arm.** In Stage 2 the reviewer receives the diff and the task file only, with
no indication of which arm produced it, and its findings are recorded through
`kit-review-record.sh` so that "found nothing" and "recorded nothing" stay distinguishable
(`finding-gap` rows with reasons are part of the result).

Recorded per arm: verdict, finding count by severity and class, findings rejected by the recorder,
and files loaded / changed against the sealed list.

---

## 9. AC4 — the stale arm, and what counts as an answer

Arm C exists because a pack that names files which have moved is a *confident wrong answer*, and
the design has no staleness detection: the pack is a snapshot, deliberately frozen, regenerated
only on the next `kit-plan.sh` run.

Staleness is introduced mechanically in the copy — rename two files the pack names, delete one —
and the question is behavioural, not numeric:

- Does the agent notice the paths do not exist, or does it report on files it never opened?
- Does it fall back to deriving, or does it stop?
- Does the wrongness reach the diff?

**Pre-registered:** if any Arm C run produces a report naming a file it could not have read, that
is recorded as a **critical** finding against the pack mechanism regardless of what Arms A and B
show on cost. A cheaper mechanism that lies is not cheaper.

---

## 10. The decision rule, fixed in advance

n will be small. **No p-values, no significance claims** — the rule is about effect size and
direction consistency, and the n appears next to every figure.

**Stage 1 gate (assembly only, n = 6 pairs proposed):**

| Result | Action |
|---|---|
| Arm A cheaper in **≥ 5 of 6** pairs **and** median BTE reduction **≥ 20%** | proceed to Stage 2 |
| Median reduction **< 10%**, or Arm A cheaper in ≤ 3 of 6 | **stop. Packs do not pay.** Go to §11 |
| Anything between | report as **inconclusive at n=6**, and stop. Do not re-run opportunistically to chase the band |

**Stage 2 verdict (full task, n = 3 pairs proposed):**

- **Packs pay** — Stage 1 gate cleared **and** no quality regression: recall against the sealed
  list not lower in Arm A, and no severity class present in B and absent in A.
- **Packs do not pay** — any quality regression, or Stage 1's reduction not reproduced.
- **Packs are dangerous** — any Arm C run per §9, which overrides both of the above.

The 20% / 10% thresholds are a judgement, chosen so the answer has to be large enough to survive
being wrong about the subject. They are stated here to be argued with **before** the data exists.
Changing them after a run voids the experiment.

---

## 11. If packs do not pay — what gets deleted

Named now so the outcome cannot decay into "keep it, it's already written":

- `tooling/kit-plan.sh:305-391` — the whole pack block, its `sq()` helper, the sqlite ≥ 3.25
  requirement and both warnings.
- `skills/task-context/SKILL.md` step 4, and step 7's *"The pack already named the cluster's
  files"*.
- `tooling/kit-init.sh:84-86` — the `.gitignore` entry.
- The sqlite 3.25 line in `INSTALL.md` and `README.md:202-203`, if nothing else needs window
  functions.
- `docs/DESIGN-NOTES.md:185`, which names cluster packs as rebuildable derived state.

`docs/HANDOFF.md` §4.6 needs **no** change: its claim is about `plan_item` as state (*"each task
session reads one row (~20 tokens)"*), which survives pack deletion intact.

Clustering itself is **not** deleted — `plan_item.cluster` orders the plan independently of whether
a pack file is written. Only the artifact goes.

---

## 12. VOID conditions specific to this experiment

Beyond `TRIAL-PROTOCOL.md` §3, which applies unchanged:

| Condition | Detection |
|---|---|
| An arm ran outside `--plugin-dir`, so only `scope=main` rows exist | `SELECT DISTINCT scope FROM spend` in the copy must contain `subagent` |
| Arm B read a pack | grep its transcript for `.project/packs/` (§7 check 2) |
| The two arms of a pair started from different commits | record `git rev-parse HEAD` per arm; they must match |
| The pack changed between the arms of a pair | `sha256` the pack before and after Arm A |
| Two tasks in flight in one copy | spend attribution binds a transcript to the following transition and can bind to the wrong task. One task at a time, per `TRIAL-PROTOCOL.md` §5 |
| The plan was regenerated mid-pair | `plan_item` row count and cluster id recorded per arm; must match |

---

## 13. What this experiment cannot establish

- **Whether packs help on a repository unlike this one.** §5 states the bound; the report repeats it.
- **Whether a *well-formed* pack pays, if R2 is chosen.** Only R1 tests the idea.
- **Whether H1 would hold if the pack were placed above the cache breakpoint.** That is a different
  build, not a different arm. If the counters say H2 and not H1, the honest conclusion is that the
  saving is avoided derivation and the `kit-plan.sh:308` comment is wrong — worth a separate task.
- **Anything about accumulation over a long-running plan.** Every pair here is one session.

---

## 14. Companion: the R-13 documentation-layer audit

Folded into the same task and answered separately, because it needs no agents and almost no spend.

`docs/HANDOFF.md` §4.7 already carries a measurement — ~1,259 tokens always-on (5 skills ~440,
8 subagent descriptions ~840, hooks zero, MCP zero), taken with
`claude --plugin-dir . plugin details coding-kit`. The audit is therefore: **re-run that command at
`383432b`, confirm the figure still holds, and check each always-loaded item against the rule the
register asked for** — anything always-loaded that does not earn its place moves to on-demand.

This is independent of §3's route and can run first at negligible cost. It is *not* a substitute
for the experiment: it measures the resident footprint, not what the pack buys.

---

## 15. Acceptance-criteria coverage

| AC (from the task file) | Where | Note |
|---|---|---|
| 1 — a pack is loaded by a real agent, observably | §7 | three checks, one of which distinguishes read from used |
| 2 — both arms in BTE, n stated | §4, §6, §10 | **amended**: paired within-task, not two different tasks. Needs sign-off |
| 3 — quality, not only tokens | §8 | sealed ground truth; blind review |
| 4 — what happens when the pack is stale | §9 | promoted to a full arm with an overriding verdict |
| 5 — if they do not pay, stop generating them | §10, §11 | deletion list written before the data exists |

---

## 16. Sign-off checklist

- [ ] **§3 route chosen** — R1 (fix first), R2 (measure as-is), or R3 (stop and delete).
- [ ] **§4 amendment accepted or rejected** — paired within-task instead of two tasks.
- [ ] **§10 thresholds accepted or changed** — 20% / 10%, ≥5 of 6, before any data exists.
- [ ] **Budget accepted.** Order-of-magnitude, and it is large: the only measured task in this
      repository's `spend` table cost **10,142k BTE** (n=1, 11 transcripts, main scope). Stage 1 is
      a small fraction of a task and 12 runs should land in single-digit millions; **Stage 2 at 3
      pairs × 2 arms plus blind reviews plausibly costs 60M+ BTE**. Stage 1's gate exists to avoid
      paying that for nothing. A cap should be stated here before signing.
- [ ] **Time-box stated**, in hours.
- [ ] **Task ids for the pairs written into §5** and frozen.
- [ ] **Sealed ground-truth file committed** (§8) before the first arm runs.

Nothing in this document has been executed. The first thing it will discover is that this document
is wrong somewhere — `TRIAL-PROTOCOL.md` was reviewed three times before its first checkbox proved
unevaluable, and the fix for that was running it, not reviewing it again.
