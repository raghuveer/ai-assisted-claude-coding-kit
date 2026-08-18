# The plan is the one artifact nothing reviews, and auto-mode is where that bill comes due

Design input, 2026-08-18. **A proposal, not a decision.** It records a gap found by three
consecutive sequencing reversals in one session, what mechanically caused each, and four candidate
mechanisms in the order their cost and evidence argue for. Nothing here is built. Where a claim was
measured, the query and its result are given; where it is judgement, it says so.

---

## 1. What happened, before any interpretation

Across one session the coding agent recommended a next task three times. Each time the operator
replied, in substance, *"check and double confirm"*. Each check **refuted the recommendation**:

| # | Recommended | What the check found |
|---|---|---|
| 1 | `paths:` fix next, TRIAL-PROTOCOL clause as small-and-overdue | The planner ranked the TRIAL-PROTOCOL task **4th** and `paths:` **20th** — and the former unblocks the brownfield trial through a `depends_on` edge the agent had not accounted for |
| 2 | `paths:` is "the remaining obstacle to Gate B having any population" | **False.** The experiment draws from cluster 1, `open`, T1–T2, no `blocked_by` — **35 tasks**, against Stage 1's 6 pairs. The claim came from carrying §2(a)'s "58 of 77" figure into a context where it does not apply |
| 3 | `paths:` before clustering | **Backwards.** Cluster 1 grew 61→70 of 83 tasks and 42→47 distinct files while the cap still prints 40, so `paths:` would enlarge an already-degenerate list and be measured against a worse baseline than today's |

**Zero of the three were caught by anything in the kit.** All three were caught by a human asking
for a re-check, at exactly the right three moments.

## 2. The gap, stated plainly

The kit has five verification rungs and eight agents. **Every one of them is scoped to a change** —
a design document, or a diff. `approach-reviewer` asks *is this approach right?*
`implementation-reviewer` asks *is this code right?* `security-reviewer` asks *is this safe?*
`verify-ladder` asks *has this change been verified deeply enough for its tier?*

Nothing asks **"is this the right next change?"**

The plan is the only artifact the kit produces that no reviewer reads and no rung covers. ADR 0004
has just made it durable, committed, and derived-from-text — it is now a first-class artifact in
every respect except that nothing checks it.

## 3. Why this is cheap today and expensive in auto-mode

Today the operator is the sequencing reviewer, and a wrong recommendation costs one exchange. That
is why this has never hurt: the human is in the loop at precisely the decision point.

Auto-mode removes that prompt. The failure mode becomes **thrash** — start task N, discover
mid-implementation that M should have come first, abandon or rework. The cost is tokens and wall
clock, and worse, a contaminated record: a task showing `progress` with abandoned work behind it,
which the escape-rate and spend measurements then attribute to the wrong thing.

**This is the same lesson the kit already learned once, at a different altitude.** The reviewer
agents exist because a coder's own judgement of its output is the signature that carries no
information. The plan is that same problem one level up: *the agent that chose the order is the
worst judge of whether the order is right.*

## 4. What mechanically caused each reversal

Worth separating, because the three have different fixes and only one is expensive.

**(a) An undeclared dependency.** The `paths:` → experiment link existed in prose in
`docs/EXPERIMENTS/…` and nowhere else. `kit-plan.sh` reads `blocked_by`; it cannot read a
paragraph. So the planner ranked the task 20th while the design argued it was next, and both were
internally consistent. **Demonstrated live:** declaring the clustering task in `blocked_by` moved
it from rank 49 to rank 5 and pushed the experiment into layer 1 — the ordering the prose had been
asserting for three retellings arrived automatically the moment it was declared.

**(b) A stale premise.** "58 of 77 tasks can never receive a pack with file information" was true
when measured and remained true — but it was carried into a context where it did not apply, and
nothing re-derived it. Both the figure and the population claim are **queries**, not opinions.

**(c) No adversarial read of the ordering.** The sequence was one agent's judgement, restated three
times, never read by anything whose job was to disagree with it.

## 5. Four candidate mechanisms

Ordered by the evidence, which does **not** put the obvious one first.

### D — measure the thrash, first

The kit measures escape rate and spend. It measures nothing about sequencing quality. Candidate
observables, all derivable from data already recorded: tasks that moved `progress` → `open`; plan
top-N churn between consecutive `kit-plan.sh` runs; commits against a task later found blocked;
`blocked_by` edges added *after* work began on the dependent.

**This is proposed first, and the argument is the kit's own.** Building A–C without it repeats the
cluster-pack mistake precisely: a mechanism built at both ends, documented, wired, and never
measured — which is the task that has consumed most of this session. A sequencing control whose
value nobody can state is a hope. **If the thrash rate turns out to be low, B and C should not be
built at all**, and that is a legitimate and cheap outcome.

### A — lint undeclared dependencies

A task file, ADR, or experiment design that names another task id in prose must either declare it
in `blocked_by` or carry an explicit "not a blocker, because…". Mechanically checkable: extract
`T-\d{8}-` references from the body, compare against `blocked_by`, require an exemption marker.

Would have caught (a). Cheapest of the four, no agent spend, and it fails loudly. Its risk is
false positives — a task legitimately *mentions* another without depending on it — which is why
the exemption marker is part of the proposal rather than an afterthought.

### B — re-derive a task's premise before starting it

A task records the measurement that justifies it **as a runnable query**, not as a sentence.
`task-context` re-runs it and reports drift before any work begins.

Would have caught (b). This is the kit's existing "derive from the authority" discipline applied to
*why a task exists*, and it composes with the digest work ADR 0004 just landed — the same shape:
record what a claim was computed from, recompute, report the delta. Its cost is that most tasks'
premises are not currently expressed as queries, so this is a convention change with a long tail,
not a switch.

### C — a plan-review gate at goal level

One adversarial read of the **ordering** before a multi-task goal begins: undeclared dependencies,
premises gone stale, pairs where doing A before B wastes the work, tasks already obsoleted by
something merged. `approach-reviewer`'s discipline pointed at the backlog instead of at a design.

Would have caught (c), and is the only one that would. It is also the expensive one — an agent
run per goal — and the one whose value is least certain without D.

## 6. Scope, stated because this is exactly where it would be breached

**This stays a support kit, not an agent framework.** Each candidate is a lint, a rung, a skill, or
a reviewer *definition* — artifacts the kit already has shapes for. None of them is an orchestrator
that decides what to run. A mechanism that picks the next task and acts on it without the operator
is out of scope regardless of how well it would work.

## 7. What this proposal does not claim

- **Not that the kit is broken.** The human-in-the-loop control worked three times out of three.
  The claim is narrower: it does not survive auto-mode, and nothing else covers it.
- **Not that any of A–D is worth building.** That is what D is for.
- **Not a cost estimate.** C is an agent run per goal and nobody has measured what that is.
- **Not that three reversals is a rate.** n=1 session, one agent, one backlog. It establishes the
  failure mode is reachable, not how often it happens — which is D's question.

## 8. Recommended next step

File this as a task, tier it, and put **D** through the normal review chain before building
anything. If the measurement says thrash is rare, close the whole line and record why — that is a
cheaper answer than four mechanisms nobody can evaluate.

Related: `T-20260808-cluster-packs-are-generated-and-read-by-` is the standing example of a
mechanism built and never measured. `docs/EXPERIMENTS/2026-08-17-cluster-pack-roi.md` §3 carries
the correction that produced this document.
