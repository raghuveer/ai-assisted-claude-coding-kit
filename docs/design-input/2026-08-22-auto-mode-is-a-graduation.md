# Auto-mode is a graduation, and the interrupt budget is the constraint

Design input, 2026-08-22, second of the day. Produced from a working session between the operator
and the coding agent, immediately after
`2026-08-22-competitive-comparison-and-roadmap-input.md` and correcting its framing.

That earlier document organised the roadmap around competitive gaps. The operator's response made
clear that the organising axis is different and simpler: **the kit exists to get multiple
open-source projects developed in auto-mode.** Everything else is instrumental. This document
records that goal chain, the operating model it implies, and the design questions it opens — most
of which had no home before.

Marked as before: unmarked statements are the operator's stated goals or facts about the kit;
`[judgement]` marks an opinion a future session may overturn.

**§3.1 was added later in the same session**, after the operator corrected §3's assumption that the
definitions are fixed before a run. It is marked as a correction in place rather than folded into
§3, so that the assumption and its refutation are both visible.

**Nothing here is filed as a defect and nothing is marked done.** Where the reasoning implies work,
it is named as an open question with what would settle it.

---

## 1. The goal chain, recorded because it lived only in a transcript

1. **Terminal goal:** expedite development of multiple open-source projects **in auto-mode**. The
   kit is the means, not the product.
2. **Maturity is plural.** Auto-mode is switched on per project, against that project's own
   roadmap. There is no single ready date for the kit.
3. **Positioning:** an add-on used *with* Claude Code and other coding agents, by architects,
   developers and teams, from startups to enterprises.
4. **No gateway, no agent framework — because of (3), not as a preference.** An add-on that
   requires you to adopt its runtime is not an add-on. It has to sit on top of whatever the
   organisation already runs.
5. **Host sequencing:** stable as a Claude Code plugin first, then other coding agents. The
   foundation for the second was designed in deliberately over time; the deferral is intent, not
   debt.
6. **Model support, later and constrained:** the kit never selects a model. It works with whatever
   models the organisation's own AI/LLM gateway exposes to the coding agent the kit is connected
   to in that deployment. The kit must be model-*aware* — able to price and attribute what was
   used — and model-*agnostic* — unable to name what should be used.

### 1.1 Two corrections to the previous document

**LangGraph was an example use case, not a scope.** The previous document promoted it to a design
pillar (§3.1 there) on the grounds that agent applications are non-deterministic subjects. That
over-read one example into a category. The surviving residue is one finding class, not a pillar:
some acceptance criteria are distributions rather than booleans, and that will matter when finding
classes for non-functional coverage are defined. Nothing more.

**"Not a gateway" is a positioning statement, not a build-vs-buy conclusion.** The previous
document read it as "consume what exists". Goal (4) above is the actual reason and it is
stronger: it constrains what the kit may ever require of a host organisation.

---

## 2. Auto-mode is a graduation, not a mode

The operator's formulation, which is the load-bearing sentence of this whole design:

> It is only when the person sitting there sees the appropriate outcome that they can define a set
> of tasks as a goal and leave it in auto-mode.

Three things follow, and none of them is a feature flag.

**The unit of delegation is a goal, not a task.** A goal is a set of tasks with acceptance
criteria, handed over as one thing. That is a larger unit than anything the kit currently
delegates, and `goals` already exist in the schema as the milestone mechanism — with only
`default` ever used. The mechanism is present and unexercised, which is the right kind of gap.

**Trust is earned by observation, not by argument.** Nobody delegates because the design is sound;
they delegate because they watched it produce appropriate outcomes repeatedly. So the kit's first
obligation is not to be trustworthy — it is to be **legible enough that trustworthiness can be
observed**. That reframes the measurement work entirely: escape rate at `0/0`, tier floors that
have never bound, reviewers whose recall has never been tested. These are not competitive gaps.
**They are the evidence the watching human does not have**, and without that evidence graduation
cannot happen no matter how good the kit gets.

**The controls do not change at graduation; their addressee does.** Today every gate resolves to
the operator: never mark a task done, propose the disposition and stop, `Via:` is yours, findings
are marked by you. That is correct for the trust-building phase and it is precisely what stops in
auto-mode. So the transition is not "add an unattended mode" — it is deciding, control by control,
which addressee each has at which phase, and what evidence justifies the change. `[judgement]`
This is the single largest piece of unbuilt design in the kit, and it is design, not code.

---

## 3. The interrupt budget is the real constraint

The operator's second formulation:

> Too many runtime reminders are not needed, unless the system is really deviating beyond the
> discussed approach, plan, acceptance criteria and all kinds of definitions.

Read as a requirement rather than a preference, this is demanding, and it is demanding in a
productive direction.

**It says escalation must name which definition was breached.** Not "I am uncertain", not "this
seemed risky", not "confirming before I proceed" — those are the interrupts that make auto-mode
not auto-mode. A legitimate interrupt points at a recorded definition and says: *this diverged
from that.*

**Therefore the definitions must exist as checkable artifacts, not as prose in a document a model
is asked to honour.** This is the same distinction the competitive comparison found between our
computed tier floors and BMAD's prose floor — except here it is not a differentiator to boast
about, it is a precondition. Every class of definition the operator named needs a form that
divergence can be computed against:

| Definition | Where it lives today | Is divergence computable? |
|---|---|---|
| Approach | Solution overlay | No mechanism found |
| Plan | `.project/plans/`, `kit-plan.sh` | Ordering is computed; adherence is not |
| Acceptance criteria | Task files | Ticked by judgement, not checked |
| "All kinds of definitions" | Profile, tier floors, catalogue, ADRs | Floors are computed; the rest are not |

**The asymmetry to design for `[judgement]`:** silence must be cheap and interruption must be
expensive. Anything the kit notices that is *not* a divergence from a definition goes into the
record for later review rather than to the human now. This inverts the current default, where the
agent surfaces everything and the operator filters. Under auto-mode the kit must filter, and the
filter must be a named definition rather than a confidence threshold — because a confidence
threshold is exactly the thing that drifts.

**The failure mode this creates, stated so it is not discovered later:** a definition that does not
exist cannot be diverged from, so an under-specified project will run quietly and wrongly. The
interrupt rule therefore puts weight on the *completeness* of the overlay and acceptance criteria
that nothing currently checks. A silent dimension is a finding — BMAD's phrasing for its
architecture spine — and it applies here for a different and sharper reason than theirs.

---

### 3.1 Definitions accrete, and a deviation is an event with a disposition

§3 above treats the definitions as a set fixed before the run, with divergence measured against
it. **That is wrong about how inputs arrive**, and the operator corrected it in the same session.

- The **solution overlay is one input channel** from the architect and/or the lead developer. It is
  not the definition set.
- **`project-profile.md` carries an introduction and further inputs.**
- **At any point while the activity progresses, a developer may input something about a
  deviation** — and it is adjudicated: **planned, rejected, accepted as proposed, or accepted with
  changes**. Execution then continues under whatever that adjudication left standing, through the
  kit on whichever coding agent is in use.

So the governing state at any moment is an **accumulation with provenance**, not a document. Three
consequences, and the first is the useful one.

**A deviation has the same shape as a finding, so it should reuse the same machinery.** The kit
already has a disposition vocabulary where each value is a distinct claim rather than a synonym,
and where one of them is refused unless the tree carries corroborating evidence. A deviation needs
exactly that treatment one layer up — `planned | rejected | accepted | accepted-with-changes`,
each recorded with **who decided, against which definition, and on what date**. `[judgement]`
Building a second, parallel mechanism for this would be the mistake; the finding-disposition design
already solved the hard part, which is making a mark that clears a gate say why.

**"Planned" is an entry into the backlog — and that gap is already recorded elsewhere.** Turning an
accepted deviation into task rows is the same missing mechanism as brownfield entry, where
`ENTRY-PROPOSAL.md` can express exactly one disposition — a new task — and nothing turns a roadmap
into rows. **One mechanism, two callers.** That is worth knowing before either is built
separately.

**Acceptance mutates a definition, so authority is per layer.** The overlay is co-authored by the
solution architect with the lead developer and is explicitly not the coding agent's to re-open. A
developer's in-flight input therefore cannot silently amend it. **Which disposition a person may
apply depends on which layer the deviation touches** — a task's acceptance criteria, a
project-scoped floor, or the overlay itself. This is undecided, and the goal chain puts it on the
critical path: without it, an accepted deviation is indistinguishable from drift the next time
anyone reads the record.

**What this changes about §3.** An escalation is not only "name the definition breached". It is
**name the definition, propose a disposition, then either apply a pre-authorised one or queue it**.
In auto-mode nobody is sitting there to adjudicate, so the pre-authorisation rules are the whole
difference between a run that halts at the first deviation and one that finishes. That is the
addressee question from §2 arriving from the other side, and it is the same question.

**What it does not change: the invariant layer.** A deviation may amend approach, plan or
acceptance criteria. It may **not** amend what counts as a finding, a tier, or an escape — because
the accumulated record has to stay comparable across time and across projects, and graduation is
built entirely on that comparison (§4).

---

## 4. Personalisation and determinism are both required, so they must live in different layers

The operator's third point: each architect or developer using the kit works in their own style,
while some aspects of the SDLC are expected to be common — and personalisation extends to how a
person or team plans a solution.

Held next to "the kit's duty is to facilitate deterministic outcomes", that is a tension, and it
resolves only by being explicit about which layer is allowed to vary.

**Proposed layering `[judgement]` — three layers, of which the third does not exist yet:**

- **Invariant, kit-owned.** The *shape of the record*: what counts as a finding, a disposition, a
  tier, a spend row, an escape, a goal. **This may not vary by person or project.** If one
  practitioner's style can change what counts as a finding, then outcomes observed under one style
  stop predicting outcomes under another — and graduation, which is entirely built on observed
  outcomes, becomes impossible. Determinism lives here or nowhere.
- **Project-scoped.** Approach, stack, baseline patterns, tier floors, thresholds, debt strategy,
  acceptance criteria, which accelerators apply. Carried by the solution overlay and
  `project-profile.md`; authoritative from the first commit; amended by ADR.
- **Practitioner-scoped — absent today.** Working style: how much research before a decision, how
  much narration, review appetite, when to ask versus proceed, preferred decomposition
  granularity, how a person likes solution planning to run.

Today the profile absorbs some of the third layer's job and the rest lives in each session's
habits. `[judgement]` The open question is not whether to add the layer but **where its boundary
sits**: a style that changes *how work is approached* is legitimate; a style that changes *what
counts as done, found, or escaped* is the invariant layer in disguise and must be refused.

That refusal is testable, which makes it a real boundary rather than a slogan: a practitioner
setting that alters any number `kit-status.sh` reports is in the wrong layer.

---

## 5. What "deterministic outcomes" can honestly mean

Worth settling because the goal is stated in those words and the literal reading is impossible: a
language model does not produce identical text from identical input, and no overlay changes that.

**The defensible meaning is determinism of conformance, not of text.** The same inputs produce
outcomes that conform to the same definitions — the same tier floors bind, the same acceptance
criteria are met, the same finding classes are checked, the same budget holds. Two runs may write
different code and both be correct outcomes; two runs may write similar code and one be a
divergence.

The kit's stated mechanism maps onto three stages, and this is the clearest statement of what the
overlay and accelerators are *for*:

1. **Constrain before generation.** The solution overlay narrows the solution space — stack,
   baseline patterns, the architect's recorded answers, the debt strategy — so fewer decisions are
   improvised in the moment. Fewer improvised decisions is the whole of the variance reduction.
2. **Supply instead of improvise.** Technology and industry accelerators provide pre-decided
   answers that were earned on previous projects. Every answer supplied is a decision not re-made,
   and re-made decisions are where two runs diverge.
3. **Verify after.** The record shows conformance: tiers, findings, dispositions, spend, escapes.
   This is the stage that produces the observable outcomes graduation depends on.

Constrain → supply → verify. `[judgement]` Stage 1 exists as a concept with its authorship settled
and its content per project. Stage 2 exists as a concept with an earning ladder and no
distribution mechanism. Stage 3 is the most built and the least exercised. The order of maturity is
the reverse of the order of use, which is worth knowing when sequencing.

---

## 6. What graduation requires, per project

Since maturity is plural, this is a checklist a project passes, not a milestone the kit reaches.
`[judgement]` — offered as a first draft to argue with, not as a standard:

1. **The definitions exist.** Overlay present; acceptance criteria on every task in the goal; tier
   floors populated. A project cannot be run unattended against definitions it does not have.
2. **Divergence is computable** for each class of definition, and has been **proven to trigger** at
   least once. An escalation path that has never fired is not known to work.
3. **The controls have readings.** Escape rate has a denominator; floors have bound; reviewer
   recall has been measured against something planted rather than found.
4. **A budget cap binds**, because unattended plus unbounded is the one failure that cannot be
   noticed late.
5. **Disposition delegation is decided** — which marks the machine may set, on what evidence, and
   which remain the human's permanently. This covers **both** kinds of mark: findings, and the
   deviation dispositions of §3.1. For deviations it also has to answer *which layer* a given
   person may accept against, since accepting one mutates a definition.
6. **The goal is expressed as a goal**: a named set of tasks with acceptance criteria, not a
   backlog to be interpreted.
7. **A stop condition and a resume path exist**, so that halting is a defined outcome rather than
   an abandoned run.

Item 2 is the one with no mechanism at all today, and item 5 is the one that is pure design. Those
two are the graduation blockers `[judgement]`; the rest are work whose shape is already known.

---

## 7. How this re-sequences the previous document's roadmap

The earlier roadmap was cut by competitive gap. Re-cut by the goal chain, the same items land
differently and some change priority sharply:

- **Rises:** getting readings into existing instruments (§2 — it is the evidence for graduation,
  not a marketing claim); the budget cap (§6.4, now on the critical path); model-capability instead
  of model identity (goal 6 makes it structural — an agent naming a model is unrunnable in a
  deployment whose gateway exposes different ones); accelerator distribution (the reuse mechanism
  across *multiple projects*, which is the terminal goal, rather than a feature Spec Kit happens to
  have).
- **New, and absent from the previous roadmap entirely:** divergence detection (§3); disposition
  delegation (§2, §6.5); the practitioner layer (§4); goal-as-unit-of-delegation (§2).
- **Falls:** host portability, which is a deliberate later phase (goal 5) and was wrongly framed as
  a gap; the agentic-subject pillar, demoted to one finding class (§1.1).
- **Unchanged:** finish the brownfield trial first. It was the right next step under the
  competitive framing and it is the right next step under this one, for a better reason — it is the
  first end-to-end observation of outcomes on a project nobody on this side wrote, which is exactly
  the evidence §2 says graduation is built from.

---

## 8. Decisions taken in this session

Five answers from the operator, recorded with what each closes and what it leaves open. Where a
decision needed a boundary the operator did not draw, the boundary below is **proposed, not
decided**, and is marked as such.

### 8.1 The audience spans seniority, and that is why supply matters

> Wanted to make this coding kit available to developers, seniors to juniors, who may find
> optimistic outcomes based on provided project inputs, solution overlay etc.

This sharpens §5's middle stage from a claim about efficiency into the actual value proposition.
**Accelerators and the overlay are the seniority-levelling mechanism**: every decision they supply
is a decision a junior does not have to improvise and a senior does not have to re-make. "Reuse
across projects" undersells it — the same mechanism that reduces variance between two runs reduces
variance between two people.

`[judgement]` Two consequences follow that were not obvious before. **Legibility (§2) has to be
stronger than for an expert audience** — a junior cannot be relied on to know what to look at, so
the kit must surface the checks rather than assume the reader will think of them; this is the
argument for §8.4 below. And **the overlay's completeness matters more**, because §3's failure mode
— an under-specified project running quietly and wrongly — lands hardest on whoever has least
context to notice.

### 8.2 Deviation authority: task acceptance criteria only

A developer adjudicates deviations **against a task's acceptance criteria and nothing else**.
Project-scoped floors and thresholds, and the solution overlay, escalate to whoever owns them.

Closes the first open question of §3.1. It is also the answer that composes with §8.1: it is the
same rule for a junior and a senior, so authority does not have to be reasoned about per person,
and §8.5's deferral of the practitioner layer costs nothing.

### 8.3 Uncertainty default: tier decides, and the rest batches

The operator placed this between "decide by tier" and "batch and ask once". Both, composed:

- **Tier decides whether an uncertain call can wait.** T0 and T1 surface immediately; T2 and T3 are
  recorded and carried.
- **What can wait is batched to one question per goal**, rather than one interruption per event.

`[judgement]` — **proposed boundary, not decided.** Two additions that seem to follow and need
confirming: anything touching a layer the current adjudicator has no authority over (§8.2) surfaces
immediately regardless of tier, because batching a question nobody present can answer only delays
it; and a budget threshold breach surfaces immediately for the same reason it is on the graduation
checklist — unattended plus unbounded is the failure that cannot be noticed late.

The important property is that this adds **no new dial**. The interrupt budget binds to the tier
machinery that already exists, which means it is calibrated by the same decision an operator
already makes per task.

### 8.4 What "appropriate outcome" means — and it includes non-functional conformance

Asked what a developer inspects beyond unit and integration tests, the operator named **all four
offered signals** — runs it and exercises the behaviour; reads the diff and the reasoning; checks
against the plan and acceptance criteria; looks at what it chose *not* to do — **and added a
fifth**:

> latency within prescribed limits, functional and security guidelines compliance in code etc.

**This is the most consequential answer in the session `[judgement]`, and it re-prioritises the
roadmap.** The chain is short and hard to escape: graduation depends on a person judging outcomes
appropriate (§2); that judgement includes non-functional conformance; the kit has **no mechanism**
that makes an absent or breached non-functional requirement visible — it was the dimension where
the competitive comparison found us furthest behind a stated goal. So **non-functional coverage is
not a mid-term improvement. It is a graduation prerequisite**, and it moves ahead of most of what
the earlier roadmap put in front of it.

Three of the five signals also happen to be things the kit could surface rather than leave to
inspection: conformance to plan and acceptance criteria, what was deferred or silently decided, and
non-functional limits. The other two — running the thing, reading the reasoning — stay human, and
should. `[judgement]` The design target is not to replace the inspection but to make the three
mechanisable ones cheap enough that attention is left for the two that are not.

### 8.5 The practitioner layer is deferred

Not needed yet. §4's three-layer model stands as analysis; its third layer is **parked by operator
decision**, not left open. Ship the invariant and project layers first and let the trial say
whether style ever needs to be represented.

Recorded here so a later session does not re-open it as an oversight — and note that §8.2 is what
makes the deferral cheap, since authority does not vary by person.

---

## 9. Open questions this document does not answer

- ~~Where the practitioner layer's boundary sits~~ — **closed by §8.5**: parked, not open.
- ~~Which authority may accept a deviation against which layer~~ — **closed by §8.2**: task
  acceptance criteria only, the same rule for every seniority.
- What evidence justifies moving a control's addressee from human to machine, control by control.
- Whether the two additions proposed in §8.3 hold — immediate surfacing when the adjudicator lacks
  authority over the layer, and on a budget threshold breach.
- Which non-functional dimensions get a mechanism first (§8.4), and whether a breached limit and an
  *absent* limit are the same finding class or two.
- Whether divergence detection is one mechanism across all definition classes or one per class.
- Which authority may accept a deviation against which layer (§3.1), and whether that is expressed
  as a role, a person, or a rule in the profile.
- Whether the deviation vocabulary is literally the finding-disposition mechanism reused, or a
  sibling sharing its guard design — and what the corroborating marker is for
  `accepted-with-changes`, which is the value that most easily launders a silent amendment.
- Whether "planned" and brownfield entry can share one roadmap-to-task-rows mechanism, given both
  need it and neither exists.
- What a stop condition looks like that is not simply "an error occurred".
- Whether goals-as-delegation-unit needs anything beyond the `goal` rows that already exist.
- How a team shares an overlay — the style half of this is parked by §8.5, but the team story
  itself is not designed.
- What a junior developer sees that a senior does not need (§8.1), and whether that is extra
  surfacing or the same surfacing with more explanation.
