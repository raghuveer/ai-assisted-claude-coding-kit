# The three-artifact model, accelerator distribution, and the road to unattended operation

Design input, 2026-08-16. Produced from a working session between the operator and the coding
agent. It records **decisions, their reasons, and the state of the code each was checked against**
— not a summary of a conversation. Where something was verified by running it, the command and its
result are given; where something remains undecided, it is named as open rather than smoothed over.

Written because the session settled several questions that existed only in chat, and a decision
recorded only in a model's context is not recorded.

---

## 1. Three artifacts, and why they were being confused

`project-profile.md`, the solution overlay, and accelerators had been discussed as though they
were one layer. They are three, with different authors, mutability and standing.

| | Author | Lifetime | Standing |
|---|---|---|---|
| **`project-profile.md`** | A human's initial thinking, **or** the agent's observations after analysing existing code. Either, or both. | Mutable; added to and updated throughout | Operational configuration. Paths, tier floors, ingest sources, trailer enforcement |
| **Solution overlay** | Solution architect **with** the lead developer | Given before the project starts; amended by ADR | **Authoritative from the first commit.** Not the coding agent's to re-open |
| **Accelerators** | Earned across projects, or seeded from architect input | Versioned, evolved project after project | Reference material. Seeded content is hypothesis until earned |

**The second author on the overlay is not ceremony.** Stack choice has two non-architectural
parameters — business growth projections, and what the team can actually maintain. The lead
developer is who knows the second. An "ideal" stack the maintaining team cannot own is a wrong
answer, not a brave one.

### 1.1 The overlay is a route, not only a destination

Earlier drafts treated the overlay as target-state: confirmed stack, cloud mandates, what is
already decided. It is more than that. It also carries:

- the design patterns considered a **baseline** for implementing functionality;
- the **answers** the architect and lead developer gave to questions the coding agent asked —
  the human+AI discussion, recorded rather than left in a transcript;
- whether technical debt is removed **phased or big-bang**, which is decided per project, **and
  the rationale for that choice**;
- which accelerators apply, by reference.

The operator's default posture on modernization is **re-architect major portions** — reuse
existing code and data models where applicable, then rebuild to remove technical debt and to
escape the abstraction potholes a twenty-year evolution accretes.

**Consequence for the modernization delta.** A delta measured against a static target answers
"are we there yet". A delta measured against a declared route answers "are we where the route
said we would be at this phase, and did the debt we said we would remove actually go". Only the
second is checkable, and it is only possible because the route is written down.

### 1.2 The hard inventory problem this creates

Building fresh is how you skip accreted accidental complexity. It is also how you lose a business
rule nobody wrote down. So the kit's job on a modernization target is **not** a source→target
stack mapping — that is the easy half. It is a per-component **disposition** — reuse as-is /
adapt / re-express / retire — with the evidence for each, **and an explicit category for the
components it cannot classify**. That last category is the valuable output, and it is what the
entry mechanism's questions artefact is for.

Related but not the same object: `T-20260808-task-state-cannot-express-no-longer-rele` is about
*task* state, where `abandoned` judges the attempt and "no longer relevant" judges the work.
Component disposition is a different object with the same kind of vocabulary problem. Worth
deciding together; not one task.

### 1.3 Scope of the deliverable, so the work terminates

**The kit's deliverable on a modernization target is a defensible inventory, plan and risk map —
not a completed migration.** If the success criterion drifts to "we rewrote it", the programme
never ends and what gets evaluated is the rewriter's skill rather than the kit.

---

## 2. Accelerator distribution

### 2.1 Most of the intended model already exists

Verified in this repository on 2026-08-16:

- `accelerators/README.md`: *"Accelerators are **imported per project, never installed
  globally.**"* Vendored placement — download the file, put it in the repo, reference it — is
  the designed path, not a fallback.
- Declaration is three repeatable profile keys: `accelerator.technology`, `accelerator.industry`,
  `accelerator.pattern`.
- Agent binding is inline:
  `accelerator.pattern: .claude/accelerators/cache-port.md -> approach-reviewer,researcher`.
- `kit-accel.sh resolve [--agent NAME]` is a deterministic path lookup. Its own comment: *"the
  project declares which accelerators apply, so selection is never a model judgement and never
  reads the wrong file."*
- File format is markdown with frontmatter `id` (`pattern/cache-port`), `version` (`0.1.0`),
  `kind`, `source`.
- Provenance is per line. `accelerators/pattern/cache-port.md` carries
  `source: seeded from one design review; not yet earned across projects`, and every obligation is
  prefixed `[seeded]`.
- `kit-accel.sh propose` emits candidates for human review — *"CONTRIBUTION IS A PROPOSAL, NEVER
  A WRITE."*

**So the seeded path is already built.** An accelerator drafted by the agent from an experienced
architect's input, marked as hypothesis and earned over subsequent projects, is exactly the
existing promotion ladder. No new mechanism is needed; the discipline is that seeded content must
never silently become permanent.

### 2.2 The import chain

**Solution overlay names which accelerators apply → `project-profile.md` binds them to paths and
agents → subsequent changes are recorded as ADRs.**

**Known drift risk.** The overlay decides *which*; the profile carries the binding; a human
transcribes between them and **nothing checks they agree**. This is the same drift shape that has
already bitten this repository twice — tier floors, and the finding vocabulary drifting across
four locations. A check belongs with the overlay work, not after it.

### 2.3 Accelerators are not skills — settled

Publishing accelerators "as skills of the respective coding agent" was raised and **withdrawn**:
it was an analogy for a hosted registry anyone can publish to, not a packaging proposal.

The reasoning that stands is `accelerators/README.md`'s, and it is a token argument: *"a skill
costs roughly 100 tokens of resident metadata in every project on the machine, whether or not it
is used, while a reference file costs nothing until read. If accelerators arrive as skills,
resident cost grows linearly with the catalogue and eventually eats the advantage the baseline
was built to get."*

**If a registry ever needs an agent-side component, it is ONE skill for discovery — never one per
accelerator.** Resident cost then stays flat regardless of catalogue size.

### 2.4 What a registry must carry that the format cannot express

Nothing indexes available accelerators today; `resolve` reads paths a human already wrote.

| Field | Why | Today |
|---|---|---|
| Namespace / publisher | `pattern/cache-port` collides the moment two organisations publish one | Absent |
| Origin | Which repository and which **commit SHA** a vendored file came from | Absent; `source:` is free prose |
| Integrity | Whether the vendored copy still matches upstream, or was edited locally | Absent |
| Version semantics | `version:` exists but nothing reads or compares it | Declared, unused |
| Earned-vs-seeded at the boundary | A line earned in someone else's estate is still a hypothesis in yours | Per-line marks exist; no boundary rule |
| Agent applicability | The `->` binding names Claude Code agents | Claude-specific |

Two open tasks sit on this ground and get more urgent with a registry, because a defect in a
published accelerator propagates to every consumer:
`T-20260811-an-accelerator-authoring-template-and-se` and
`T-20260814-the-promotion-ladder-has-no-gate-so-an-a`.

### 2.5 Agent-neutrality: content versus packaging

Generalising the kit to other coding agents remains **a later, separate project**. But the
*distribution format* must be agent-neutral **now**, because it is expensive to change once other
people publish into it.

- **Content is already portable** — markdown, YAML frontmatter, prose obligations. Nothing
  Claude-specific.
- **Packaging and binding are not** — the `-> agent-name` suffix, the notion of a "skill", and the
  resident-metadata cost model are Claude Code specifics.

**Recommendation: do not put agent names in a published accelerator file.** Put role or capability
intent in the file, and let the consuming project's profile map role → its own agent names. One
indirection, and it is the difference between a format others can publish into and one only this
kit can read.

### 2.6 Network posture

`SECURITY.md` states the kit "has no network service, no runtime dependency on a model provider,
and stores nothing outside the project directory." Optional fetch changes the last two.

**Vendoring stays the default**, which preserves that claim for anyone who does not opt in — and
that matters most in the regulated and air-gapped environments where this kit's value is highest.
If fetch is built: pin to commit SHAs rather than branches or tags, record the resolved SHA in the
vendored file's frontmatter, verify on read, and treat a fetch failure as fail-closed with a named
cause rather than a silent fall-through to no-accelerators.

---

## 3. Validation programme

Two projects have been used already: actix-web (Rust) and Prometheus (Go). Agreed candidates and
the order argued for, smallest-first so the census is debugged cheaply rather than on the hardest
case:

| Order | Project | Stack | What it stresses |
|---|---|---|---|
| 1 | Fastify | Node | Baseline. Mid-size, clean history. If the census is wrong here it is wrong everywhere |
| 2 | FastAPI | Python | Second language, similar size. First check that `lang` attribution is not Node-shaped |
| 3 | amphp *or* Workerman | PHP | Async PHP. Pick one — they stress the same axes |
| 4 | Swoole | PHP + C | **The real polyglot test.** Mixed-language tree, which is what the component model must survive |
| 5 | WordPress | PHP | **Scale and age.** Expect `cochange.max_degree` to withhold and the census to be slow. Both are findings |

### 3.1 Legacy modernization candidates

Illustrative pairings, chosen to give three genuinely different **migration strategies** rather
than three instances of one:

- **ASP.NET WebForms → React + .NET 9** — a **rewrite**. WebForms was never ported to .NET Core;
  ViewState, the postback lifecycle, server controls and `System.Web` have no forward path.
- **JSP → React + Spring Boot** — a **strangler**. JSP still runs, so migration can be
  incremental and the question becomes sequencing and coexistence.
- **PHP SSR → React + ReactPHP/amphp** — a **runtime inversion**. Same language; shared-nothing
  per-request becomes a long-lived event loop, and global state, superglobals, connection lifetime
  and blocking I/O all change meaning at once.

Target stack is chosen per engagement and depends on who maintains it afterwards; staying on the
same stack is correct when the client's team owns it, provided that stack still supports
evolution. `.NET Framework → React + Node.js` is acceptable where the team agrees.

**Known gap:** all three hold language roughly constant. A VB.NET source would add a language
change for free; otherwise the limit should be accepted explicitly rather than discovered.

**Availability, not suitability, is the binding constraint** on the WebForms and JSP ends.
Candidates must be researched rather than assumed.

### 3.2 Databases

Paid Oracle/MSSQL are out of scope — not primarily for licensing (both have free editions and
official containers) but for image size, cold-start latency and licensing ambiguity in CI. Older
MySQL and PostgreSQL to current versions give real breaking changes: `ONLY_FULL_GROUP_BY` on by
default, `caching_sha2_password`, new reserved words, `md5` → `scram-sha-256`, removed
`WITH OIDS`.

**A version bump is the shallow delta.** The real data-architecture test is business logic living
*in* the database — stored procedures, triggers, views — moving to the application layer. That is
where modernization projects bleed, and it comes free with the chosen candidates: WebForms and
JSP-era applications are the generation that put logic in stored procedures. **Do not test a
database migration in isolation; pair it with the application that uses it.**

### 3.3 Method: archived projects plus injected functionality

Trial subjects should be **archived or unmaintained** open-source projects, with **small
functionality generated into them** for the trial.

The second half is the important one. Injecting known functionality creates a **ground-truth
oracle**: you know exactly what you put in, so "did the census find it, classify it, and place it
correctly in the plan" has a falsifiable answer. Without that, every trial ends in "the inventory
looked reasonable", which is unmeasurable. The precedent is already in this repository — the
localiser measurement used twelve sites nominated by a read-only agent as ground truth,
specifically so the result could come out wrong.

Archived subjects are also better than maintained ones for two further reasons: real accreted
debt, and a frozen target, so two trials months apart remain comparable.

### 3.4 Running them

- **Container per trial** — the established path here is Rancher Desktop with `nerdctl`. It also
  settles the leaf-symlink question that Windows cannot test.
- **No remote on the subject copy** — `kit-preflight.sh --isolated` checks the property rather
  than trusting the intention.
- **Baseline first** — without a before-figure, "the kit helped" is unfalsifiable.
- **One project through the full loop before starting the second**, or the trial protocol has
  nothing to make runs comparable with.

---

## 4. Sequencing, and what gates what

**Greenfield is cheap; modernization is not.** Greenfield sits behind one T1 task
(`T-20260801-kit-plan-has-no-notion-of-prerequisite-w`). Modernization runs through three unbuilt
things in order: the solution overlay, then
`T-20260731-component-model-for-polyglot-and-moderni`, then the modernization delta (AC6 of the
entry task, deferred and recorded `[~]`).

**Build and prove the overlay against greenfield first, not modernization.** Greenfield has no
derived context, so the overlay is the *entire* input — no census noise, no legacy confounds, no
argument about whether a finding came from the code or from the constraints. It is the cleanest
test of whether the mechanism binds. Modernization is the hardest case and the worst place to
debug a new mechanism.

This also means greenfield is not the cheap third variation; it is the **proving ground for the
load-bearing component**.

### 4.1 The overlay answers an existing open task

`kit-plan` has no notion of prerequisite work on a greenfield repo. That is unsolvable from the
repository itself — "stand up CI, choose the framework, pick the data store" cannot be derived
from an empty directory. It **can** be derived from a declared target architecture. The overlay is
not adjacent to that task; it is the missing input the task is describing.

### 4.2 Brownfield is finished except for one thing

`tooling/kit-entry.sh` works — census, comment runs, `--check` — with conformance coverage and two
ADRs behind it. **Nothing invokes it.** Every reference outside the script is documentation:
`.gitignore`, two ADRs, three design-input files, `ENTRY-PROPOSAL.md`, `LESSONS.md`. `INSTALL.md`
§C — the section a brownfield adopter reads — never mentions it, and none of the five skills
covers it.

The design deliberately made `ENTRY-PROPOSAL.md` a reference file rather than a skill, to keep the
model half ungated. That was right; but a reference nothing points at is unreachable. **The
decision to settle: §C gains a walkthrough step, or entry becomes a sixth skill.**

---

## 5. Unattended operation

Thirteen features were identified as prerequisites, in four groups. The grouping is by *why* each
blocks, because that is what decides whether one can be deferred.

- **Safety** — the adapter execution path; guard coverage over every matched tool; privileged
  event kinds refused; the criticals gate able to reach zero.
- **Token economy** — cluster packs wired and measured
  (`T-20260808-cluster-packs-are-generated-and-read-by-`, currently *generated and read by
  nothing*, so context economics is unmeasured); accelerator line budget and eviction.
- **Unattended visibility** — session state restored from checkpoint commits; status given a time
  dimension. These two are what remove the operator's manual transcript note-taking.
- **Integrity of the record** — `SECURITY.md` §2 made true; export leak closed; an unsupported
  causal claim in `docs/MEASUREMENTS.md` retracted; the checkpoint skill's missing guard on
  `kit-vindicate.sh`.

**Explicitly not prerequisites:** the solution overlay, the component model, the modernization
delta, the entry §C wiring, the trial programme, and the accelerator registry. Vendored
accelerator placement already works, so nothing there blocks unattended operation — though the
naming and provenance decisions should land before anyone publishes into the format.

### 5.1 Two signatures that stay human

Agreed for unattended operation:

1. **The agent files only defects it has reproduced**, at a stated tier, reported in each summary.
   Speculative, design-shaped or scope-expanding work stays a proposal. This keeps
   `kit-task.sh`'s gate where it matters — the backlog's *shape* — without requiring approval of
   each verified bug.
2. **The agent never marks a task done.** It runs the reviews, acts on findings, and hands over a
   close-recommendation with evidence.

The second was earned the day it was written: the agent reported four of five acceptance criteria
met on `T-20260815-security-md-claims-allowedtools-enforces`, and a blind review established it
was one of five. A session that both does the work and certifies it removes the only check that
found that.

---

## 6. Open decisions

1. **Overlay form** — prose, or prose plus a derived projection the planner reads? "Shapes and
   plans the to-do" implies mechanical consumption; maintainable-without-GenAI says the durable
   artefact is prose a person reads. The kit already resolves this exact tension for task files
   and `index.db`: text is truth, the derived form is disposable. Applying the same pattern is the
   proposal unless overridden.
2. **Where the overlay lives.** Not `accelerators/solution/` — `DESIGN-NOTES` §2 states in bold
   that an overlay is *not* an accelerator, and siting it there contradicts that in the
   filesystem. The word "overlay" has already collided twice in this repository. It wants its own
   path key.
3. **Whether unattended runs fan out**, which decides if parallel-execution isolation is a
   prerequisite or deferrable.
4. **The nine pre-summary criticals** — a policy call on findings that predate the summary field.
5. **Legacy candidate selection**, once availability has been researched.
