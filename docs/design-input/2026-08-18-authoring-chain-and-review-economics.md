# The authoring chain, when to re-enter it, and what review should cost

Design input, 2026-08-18. Produced from a working session between the operator and the coding
agent. **A proposal, not a decision.** It records the chain agreed in that session, the conditions
that re-enter it, a cheaper rule for invoking the security reviewer, and the operator's account of
why modernization projects fail — which is domain input the kit currently has nowhere to put.

Companion to `2026-08-18-the-plan-is-the-unreviewed-artifact.md`, which covers the sequencing gap
this chain is meant to close. Where a figure was measured, it is given with its source.

---

## 1. The chain, agreed

```
research → ADR → approach-review → breakdown (proposed, human-confirmed) → sequence-review → implement
```

**Sequencing sits after approach review** because a REJECTed approach makes any ordering work
wasted.

**The breakdown step keeps its human gate.** `kit-task.sh`'s own header states the rule: *a
researcher proposes a breakdown, a human confirms and edits, then this writes the confirmed tasks;
the confirmation is the gate, because a model writing straight to disk means the model is setting
your backlog.* The chain must not quietly remove that by putting a sequencer downstream of an
unconfirmed breakdown.

**The sequencer challenges; it does not produce.** `kit-plan.sh` already sequences — topology into
layers, score into ranks. A sub-agent that also produces an ordering creates two sequencers that
can disagree, which is the two-sources-of-truth failure this repository has paid for repeatedly
(the schema comment against the code, the writer against the reader in ADR 0004, the finding
vocabulary in four places). Its job is to read the plan and try to refute it — the relation
`approach-reviewer` has to a design.

## 2. When the chain is re-entered

Three conditions, in descending order of how planned they are:

1. **A new feature is discussed.** Full chain.
2. **A change to an existing feature.** Full chain — the change is a new framing, not a new task.
3. **Unplanned complications or deviations found during implementation.** Re-enter as a **last
   resort**, not a reflex. This is the expensive case and the one auto-mode will hit most.

After the chain has run, work proceeds on a **shorter cycle**:

```
implement → implementation-review → test
```

with the security reviewer invoked on the rule in §3 rather than per task.

## 3. What review costs, and a cheaper trigger

**Measured this session**, from the three reviewers run against one T3 change:

| reviewer | tokens |
|---|---|
| implementation | 140,718 |
| security | 134,882 |
| approach | 106,119 (+117,743 on a resume) |

So the operator's recollection of 70k–160k per security review is confirmed by measurement rather
than memory. **Per-task security review is not defensible at that price.**

**The kit already says so.** `agents/security-reviewer.md` frontmatter: *"Use for HIGH-STAKES
changes ONLY (per the project profile's risk tiering) — crypto/key custody, authn/authz decision
points, any fail-closed path, DB migrations, the request hot path, and quota/limit enforcement.
Skip for routine CRUD/UI/docs."* The policy exists. What is missing is that **nothing computes
whether a change is high-stakes** — it is left to operator judgement, which in auto-mode collapses
to always or never.

**Proposed trigger: trust-boundary change, not a timer.** `SECURITY.md` §1 enumerates the trust
boundaries. The question *"does this change add or modify a row in that table — a new input parsed,
a new path executed, a new path an agent is told to load?"* is evaluable, and it is strictly better
than periodicity: a periodic rule reviews a quiet fortnight and misses the week a new input class
landed. **That is exactly what happened here** — ADR 0004 turned the plan file into a new untrusted,
committed, auto-ingested input, and that was the week the security reviewer earned its cost.

## 4. Security guidance in `researcher`, and its limit

**Proposed:** OWASP and comparable baselines become standing input to `researcher`, so security
obligations land in the ADR, so the coder implements against them rather than deviating and being
corrected later.

**Worth doing, and this session is direct evidence it is not sufficient on its own.** The security
review's REJECT found a `goal_id` that became a filesystem path an agent loads verbatim, a `score`
of `1e999` that emitted `+inf` and took the whole index build down, and an ignored `awk` exit
status that silently restored the very defect the change existed to fix. **None of those was the
coder ignoring a checklist.** They were emergent properties of a new input class that neither the
ADR nor its author anticipated while writing it.

A checklist catches known classes. A novel surface produces novel defects. So the two proposals
compose rather than substitute: **bake the baseline in to reduce known-class defects, and key the
review on surface change so the unknown-class ones are still caught** — which together permit one
pass on most work without dropping the pass on the week it matters.

## 5. Milestones are goals, and MVP is optional

The kit already has the mechanism and has never used it: `goal` plus `plan_item.goal_id`. **Only
`default` exists.** A goal is a milestone — a named subset of the backlog with its own ordering.

**MVP is one optional use of that, not a stage every project passes through.** Some projects go
straight to v1.0; a brownfield adoption may have no MVP at all; a modernization runs in phases that
are not "MVP" in any sense. The mechanism should carry any of those without privileging one.

**The greenfield→brownfield transition is computable and independent of naming.** Greenfield has no
`touches` edges, an empty co-change graph, and no findings. When those become non-empty the project
is brownfield, whatever the milestone is called.
`T-20260814-one-entry-mechanism-brownfield-is-the-ge` already argues brownfield is the general case
and the other two are its starting conditions; this is that argument over time rather than at
adoption.

ADR 0004 is a precondition here: goals became durable and committed on 2026-08-17. Multi-goal use
was not safely possible before that, because a rebuild deleted the plan.

## 6. Modernization — the operator's account, recorded because the kit has nowhere to put it

**The failure mode**, in the operator's words and from their project experience: modernization
efforts tend to upgrade or swap the technology while giving minimal attention to resolving the
**business** pain points, and that is why the success rate is poor.

**The approach they apply instead**, and want the kit to support:

- consciously **re-use what is valid**
- **improve** where improvement is warranted
- **no hesitation to re-architect from scratch** where that is the right answer
- throughout, stay conscious of **data-migration** consequences
- and reach a **mutual agreement with the client team** on the disposition, per project

The artifact none of the kit's current mechanisms produces is a **per-component disposition** —
reuse / improve / re-architect, each with its data-migration consequence — which is what makes that
mutual agreement reviewable rather than verbal.

**User-authored data models** belong in the same frame. They are not expected on every greenfield,
but are likely on brownfield and near-certain on modernization. `paths.design_input` (ADR 0001)
already gives them a home; nothing currently requires them to be reviewed, or detects that one has
changed.

**The persona this kit serves** is a solution architect, enterprise architect, lead developer, or
some combination of those in one project — not a solo coder. That is a stated design target and it
should be visible in what the kit asks for and what it produces.

> **Caveat this document must carry, from the component-model task's own Notes:** field names there
> are *"seeded, not earned — from two described projects and one architect's experience, not from a
> project this kit has run"*, and the instruction is to bind them to the first real polyglot
> project. The disposition taxonomy above comes from that same architect. It is better-grounded
> input than an invented one, and it is still not earned from a project the kit has run. Treat it
> as the seed it is.

## 7. What this proposal does not claim

- **Not that the sequencer sub-agent should be built.** The companion document's cheap order stands:
  measure thrash → dependency lint → premise re-derivation → agent for the residue. A sub-agent is
  the most expensive of the four and it is proposed first only in conversation.
- **Not a cost for the chain.** Running researcher + adr-scribe + approach-reviewer + sequencer per
  feature is unpriced. §3's figures cover reviewers, not the authoring half.
- **Not that chain depth should be uniform.** Tying it to tier, as `verify-ladder` already ties
  verification depth, is the obvious economy and is untested.
- **Not a modernization method.** §6 records one architect's approach so it stops living in chat.
  Whether the kit should encode it is a decision, and an unmade one.
