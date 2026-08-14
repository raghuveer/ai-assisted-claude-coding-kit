# Design notes — proposed, not built

> **Status: seeded, not earned.** Nothing here is implemented. The field names, key names
> and edge names below are deliberately provisional: they were derived from two described
> projects and one architect's experience, not from a project this kit has run. By the
> kit's own standard that makes them hypotheses, and shipping them as schema would be the
> same mistake the `[seeded]` / `[earned]` marking exists to prevent.
>
> The *shapes* are argued from code that exists and constraints that are measured. The
> *names* should be fixed by the first real project that needs them, not by this document.

Read `HANDOFF.md` first for why the kit is built the way it is. This note only covers work
that follows from it.

**Summary.** Four proposals, none implemented. **§1** binds accelerators to *components* rather
than whole projects, so a polyglot or partly-modernised repository loads the right guidance per
part. **§2** is the **solution overlay** — the reference architecture supplied as an input by the
solution architect: confirmed stack, cloud mandates, and the decisions that are not the coding
agent's to re-open. It is *given* where an accelerator is *earned*, it is project-scoped and must
never be exported, and it carries the constraint that outranks the rest — the product must be
maintainable by a team with **no assistant of any kind**, which is a requirement on the code and
docs; process artefacts are separately required to be tool-neutral, and the two are not the same
requirement. §2 also sets out how
knowledge enters (many sources, two states) and what a published accelerator must carry to be
safely loadable by another project. **§3** versions accelerators independently of the plugin so a
project can pin one. **§4** treats context line budget as a prerequisite rather than a follow-up.

---

## 0. The constraint everything here has to satisfy

Resident cost is ~1,259 tokens per session: ~440 for five skills, ~840 for eight agents.
Agent descriptions are resident because that is how routing works, so **an agent is a
permanent standing charge and a reference file is not**. Every proposal below therefore
adds reference material and edges, never agents, and never skills where a file will do.

The second constraint is measured rather than assumed: the caching thesis is close to its
ceiling — cache-read ratio 97.5%, effective input multiplier 0.129× against a 0.100× floor,
so **≤22% headroom**. The remaining levers are peak context window and model mix. A design
that adds structure without touching either is not a token improvement, whatever else it is
worth.

---

## 1. Components — the missing binding axis

### The problem, stated from code

`accelerator.technology` is already repeatable, with agent binding:

```
accelerator.technology: .claude/accelerators/react.md -> implementation-reviewer,coder
```

`<path> [-> agent,agent]`, and `kit-accel.sh resolve --agent X` returns only X's set. That
works for a single-stack project. It cannot work for a polyglot one, for a reason visible
in any modernization target:

> Source: .NET 5 MVC + MSSQL, monolith.
> Target: React UI, .NET 8 services, PostgreSQL (OLTP), Redshift (OLAP), AWS Glue,
> RabbitMQ, Valkey, Redpanda — event-driven microservices, database-per-service.

`implementation-reviewer` reviews **both** the React UI and the .NET services. Binding by
agent cannot separate them, which leaves two bad options: load all eight accelerators for
that agent — paying for them on every invocation and inviting a reviewer to cite a React
rule against C# — or run one reviewer agent per stack, which multiplies the ~840 tok
standing charge by eight.

The binding axis has to be the **component**, resolved from the task, not the agent.

This is not specific to modernization. It is the same gap in any polyglot greenfield build.

### What the described projects demand beyond "two stacks"

**Topology changes, not stack swaps.** Example 1 is one source component becoming many.
Example 2 is three becoming two — *the local hub is eliminated*, absorbed into the client
and the server. Redshift, Glue and Redpanda in example 1 have no source counterpart at all.
A `source`/`target` pair of fields expresses neither case. The relation is many-to-many and
must be able to say **eliminated** and **newly introduced**.

**Stack is not language.** Example 2 is .NET → .NET 8: same language family, but
Windows→Linux, MSSQL→MySQL, plus a new Android target via MAUI, plus SQLite on device.
`task.lang` cannot select the right obligations for "the MAUI client on Android". The
dimensions that matter are language, framework, datastore and runtime/OS.

**Data fan-out is its own workstream.** One MSSQL becomes PostgreSQL-per-service plus
Redshift plus Glue. Schema mapping is many-to-many, and the migration work is not code work.

**Architecture rules are checkable invariants.** "Database-per-service", "adapter pattern
over interface-first", "no service reads another service's store" are not stacks. They are
obligations a reviewer can check, and a violation is a `compliance`-class finding.

### Proposed shape

A `component` node type; components carry a stack and a role. Tasks name a component.
Accelerator declarations gain a component predicate alongside the existing agent one.
`commands.*` become resolvable per component, with the bare form as the default.

Illustrative only — names are not decided:

```
component: hub-legacy     stack: dotnet5,mssql,windows        role: source
component: client-maui    stack: dotnet8,maui,sqlite          role: target
component: server         stack: dotnet8,mysql,valkey,linux   role: target

migrates: hub-legacy -> client-maui, server

accelerator.technology: .claude/accelerators/maui.md  -> @client-maui
accelerator.technology: .claude/accelerators/mysql.md -> @server
```

A task tagged `component: client-maui` then resolves MAUI and SQLite obligations and
nothing about MySQL.

### Why this is additive

Section 1 of `kit-index.sh` reads frontmatter through `v["id"]`, `v["lang"]`, `v["tier"]`
style lookups — **unknown keys are ignored, not errors**. So a new optional `component:`
key is readable by older kits, which simply skip it.

| Change | Bump under `VERSIONING.md` |
|---|---|
| optional `component:` on task frontmatter; `lang` retained, derived from component when set | MINOR |
| new repeatable `component.*` profile keys | MINOR |
| `component` node type, `migrates_to` edge rel | MINOR — index-only, and rebuild is lossless |
| `-> @component` predicate; existing `-> agent` form untouched | MINOR |

An earlier draft of this note claimed the model forced a MAJOR bump. That was wrong: it is
only breaking if `lang` is removed or repurposed, and there is no reason to do either. The
whole model can ship incrementally, which removes any argument for deferring it to a 2.0.

### Free hooks already in place

`constrained_by` and `covers` are **queried by `task-context` and written by nothing**. The
edge vocabulary already anticipated architectural invariants and test-coverage links. Both
slots are empty and neither needs a schema change to fill.

---

## 2. The solution-architect overlay

**Terminology, fixed 2026-08-14.** In this kit "overlay" means THIS — the **solution overlay**,
the reference architecture and target solution shape supplied as an INPUT by the solution
architect: the confirmed technology stack, cloud mandates and whether they are vendor-dependent
or vendor-agnostic, and whatever else about the target shape is already decided and is not the
coding agent's to re-open. The 0.1 agent-composition sense of the word is retired and its
document deleted, so the term is unambiguous. It is **not** an accelerator: accelerators are
*earned* from findings that recurred across projects, an overlay is *given* and authoritative
from the first commit. The overlay names the chosen stack and industry, and that choice is what
selects which technology and industry accelerators apply.

**What decides the stack, beyond architecture.** Two parameters sit alongside it and belong in
the overlay because they outlive the engagement: **business growth projections** — what the
system must absorb — and **developer choice** — what the team can actually maintain. Both feed
the same two questions: does the choice stay maintainable, and does it serve the purpose.
Reusable-asset development is a separate activity; the technology accelerators *reference* those
assets rather than containing them.

**The constraint that outranks the rest.** A maintenance team may continue with this kit, adopt a
different one, use a different coding agent with no kit at all, or maintain the code by hand as
teams did before any of this existed. **All four must work.** That is two separate requirements
on two different things, and collapsing them — as an earlier draft of this paragraph did — hides
the one that actually binds.

**AI-independence is a property of the PRODUCT.** The code and the docs — decision records,
runbooks, tests — must be ordinary software that a team can read, change and ship with **no
assistant of any kind**. Hand maintenance is not the edge case; it is the baseline and the
strictest of the four, because it assumes nothing is available. What that forbids in the
delivered application: a runtime dependency on a model or an SDK; tests that need a network or a
model call; a decision record that is a score-card rather than prose a person reads; docs that
defer to an assistant instead of explaining; and structure that a senior engineer would not
recognise, chosen because an agent found it convenient.

The rule this puts on the kit: **it must leave the product ordinary.** The kit reviews, records
and orders work — it does not decide the application's shape, which belongs to the developer and
the overlay. Anything that would push the product into a form only intelligible with the kit is
out of bounds, however convenient.

**Tool-neutrality is a property of the PROCESS RESIDUE.** Task files, git trailers and
`events.ndjson` are artefacts *about* the work, not part of it. They exist so a different kit, a
different agent, or a later reader can pick up the thread. In the hand-maintenance case they
become simply irrelevant — deletable in full without touching the product — which is why
un-adoption has to be possible, and why nothing in the product may ever depend on them.

Derived state (`index.db`, the generated status view, cluster packs) is a rebuildable cache and
is disposable by construction. And a decision recorded only in a model's context, or only in that
database, is not recorded at all — which is why decisions land as ADRs and trailers rather than
as chat.

A third accelerator kind, not a new subsystem:

```
accelerators/technology/   shared across projects
accelerators/industry/     shared across projects
accelerators/solution/     PROJECT-SCOPED — never shared
```

The binding mechanism is the one that already exists: large at rest, loaded only by the
agents and components that must obey it, never reaching the orchestrator.

The overlay is what populates `constrained_by`. An SA who declares "no service reads another
service's store" is declaring a checkable obligation, and a violation of it is a
`compliance` finding like any other — which means it flows into the same findings table,
the same vindication, the same promotion.

### The one rule that must be structural

Technology and industry accelerators are shared, and `kit-accel.sh propose` exports
aggregates from them. That export is safe because the redaction is **structural**: the query
*cannot* select finding text, paths, task ids or titles — not by convention, by construction.

A solution overlay is the opposite kind of thing. It is client architecture. It must be
excluded from `propose` **by construction too**, the same way instance data already is. Not
by a filter someone remembers to apply, and not by a naming convention.

### Same mechanism, all three project types

Greenfield, brownfield and modernization differ only in what feeds the overlay, not in how
it binds. Greenfield starts with no derived context; brownfield starts with analysis of
existing code, schema, diagrams and solution documents; modernization starts with that plus
a target architecture. In every case the overlay is project-scoped context resolved per
component.

---

## 3. Versioned accelerator library

`HANDOFF.md` §8 records this as blocked:

> Cross-project accelerator aggregation. `export` writes per-project NDJSON; something must
> collect across projects and count distinct project hashes. Blocked on a layout decision:
> public marketplace folder vs private collection repo. Recommendation given the client mix
> — private collection, public promotion.

`kit-accel.sh export` already emits a well-formed aggregate —
`{kind, key, class, n, vindicated, refuted, project, kit}` with a salted project handle —
and currently exports nowhere. This section proposes the destination.

### Public library, private evidence

Keep §8's recommendation, because the halves carry different risk.

**The library is public.** Versioned accelerator files anyone can import. These are
conclusions, and conclusions carry no client data.

**The export stream stays private.** It is aggregate-only by construction, but aggregate is
not the same as non-sensitive: `{industry: bfsi, class: fail-open, n: 17}` still asserts a
fact about an engagement, and some clients would object regardless of how the handle is
hashed. Publish what was learned; do not publish who taught it.

### Version each accelerator independently of the plugin

`VERSIONING.md` classes accelerator changes as MINOR. If the library ships inside the plugin
and improves after every project, the plugin's minor version churns on content that never
touches the engine — and the version stops signalling anything about the engine, which is
the entire reason it is pinned.

The cadences are genuinely different. The engine changes slowly. A .NET accelerator should
improve whenever a project teaches it something, without asking anyone to upgrade tooling.

So: frontmatter carrying `id`, `version` and `source`, alongside the per-line
`[seeded]`/`[earned]` marking that already exists. An imported copy keeps its version
header, so a year later the file itself answers *which version was this project reviewed
against* — the property that made pinning the plugin worth doing, applied one level down.

A `kit-accel.sh import <id>@<version>` fetches into the project. Whether the library lives
in its own repository or a folder of this one is then packaging, not versioning. Lean to its
own repository so accelerator releases do not appear in the engine's release feed.

### Where this ends up

A pattern accelerator that recurs across enough projects stops being a checklist and
becomes the specification for a library. `accelerators/pattern/cache-port.md` is already
written as obligations a cache implementation must satisfy, which is a spec in all but
name. [`CATALOGUE.md`](CATALOGUE.md) records what that would mean -- and why the code
belongs outside this kit even when the knowledge belongs inside it.

### Two provenance states, not three

Knowledge from projects delivered outside this kit enters as `[seeded]` — a hypothesis,
honestly labelled — and promotes to `[earned]` when findings confirm it across distinct
projects. Resist a third tier for "expert-provided". The operational question is only
*has this system observed it*, and an experienced architect's judgement is still a
hypothesis until the findings table agrees. Record attribution as metadata if useful; keep
the two states.

### Sources are many; states are two

A separate axis, and confusing it with the one above has already caused an argument. **Where
knowledge comes from** is open-ended; **what the system claims about it** is binary.

Three sources are in view:

1. **Supplied for analysis** — an accelerator handed over from work delivered outside this kit.
2. **Derived project to project** — the promotion ladder, the only source that can reach
   `[earned]`.
3. **Best practice gathered from public material, analysed by an agent, then discussed with the
   architects who maintain accelerators.** Advisory and optional — an accelerant for drafting,
   not an authority. Whatever a model was trained on already influences its output, so material
   it re-summarises is a starting hypothesis and nothing more.

All three enter as `[seeded]`. None of them shortcut promotion. The architect's binding channel
is not accelerator publication at all — it is the **solution overlay** (§2), which is given,
project-scoped and authoritative from the first commit. That is what makes the two-state rule
survivable: an architect who needs a decision obeyed does not need it promoted to `[earned]`,
because the overlay already outranks evidence for that project.

### Accelerator stewardship — what a published asset has to carry

An accelerator that is shared across projects is a distributed artefact, and the failure mode is
a stale one being loaded into work that then inherits its assumptions. The kit's three seed files
carry none of this yet; what a real one needs, and what the schema should hold:

- **Status and lifecycle.** `experimental` → `approved` → `deprecated`, with a review date, and a
  deprecation block naming a successor rather than leaving a dead asset loadable.
- **An owner.** A maintaining team and a named maintainer, so "who may publish this" has an
  answer.
- **A promotion gate with measured values beside thresholds.** Not "quality is good" but
  `threshold_min: 0.85` against `measured_value: 0.72` — which keeps the asset `experimental`,
  visibly, by arithmetic rather than by opinion. This is the same discipline as escape rate: the
  number that decides is recorded next to the number required.
- **Applicability, stated in both directions.** Domains and regions it suits, and the ones it
  does **not** — plus explicit `known_limitations` and `known_gotchas`. An accelerator that only
  advertises what it can do will be loaded where it must not be.
- **A cost envelope.** Token and wall-clock ceilings plus measured p50/p95, so binding one is a
  priced decision. The kit already treats context as the scarce resource; an unpriced accelerator
  contradicts that.
- **Overlay compatibility.** Which client mandates it can satisfy — portability, data residency,
  crypto requirements, SSO shape — and which it cannot.
- **Dependencies with reasons.** Version constraints on other accelerators, each with a sentence
  saying why, so a graph of assets does not become a mystery.

None of this is built. It is recorded here because the promotion ladder is meaningless without a
gate, and the gate is meaningless without a measured value to compare against — which is the
same argument `T-20260808-co-change-has-no-eval-harness-so-its-sco` makes for co-change.

### Line budget is a prerequisite, not a follow-up

`HANDOFF.md` §8 also records:

> Accelerator line budget and eviction. Every mechanism currently only adds; an accelerator
> that grows monotonically eventually costs more than it buys, **multiplied across every
> project that pins it.** Eviction order: refuted → stale → lowest occurrence.

A central library that improves continuously is a library that grows continuously.
Versioning protects a project from *drift* — it pins and stays put — but the head version
keeps accreting, so every new project starts heavier than the last. Eventually an
accelerator costs more per invocation than the defects it prevents, and nothing in the
system would say so.

The library therefore ships with a per-accelerator line budget, the eviction order above,
and a **published size per version**, so the cost of pinning is visible before pinning.

---

## 4. What must be true before any of this is built

Every defect found on 2026-07-31 — the trailer parser, the enforcement fail-open, the four
breaks in the findings pipeline, the hardcoded version — was in a path that had never been
executed. None was found by reading. That is evidence about method, and it applies directly
to everything above.

**Gate 1 — one real run.** One task, model in the loop, on a real repository. Not a parallel
track; a precondition. It is the only activity that has reliably found defects here.

**Gate 2 — co-change edges must be shown to help before they are shipped.** `touches` edges
require a `Task-Id` (`kit-index.sh`), so a brownfield repo starts with an empty edge table
and blast radius reports *unknown*. Deriving co-change edges from raw history would fix that
without needing trailers — **but co-change is correlation, not dependency**. In a legacy
monolith where commits routinely touch dozens of files, every file co-changes with every
other, and the result is a hairball that reports "everything" with false confidence. That is
worse than today, because *unknown* is at least honest.

Two measurements decide it, both cheap and both runnable against an existing repository
before any plugin code changes:

1. **Degree distribution.** If the median file co-changes with hundreds of others, the idea
   is dead for monoliths and should be reported as dead.
2. **Predictive power.** For a sample of historical commits, does the graph rank the files
   that actually changed above chance?

### Result — measured 2026-07-31: conditional pass

Method: train on the oldest 80% of commits, test on the newest 20%, no leakage. For each
test commit, rank candidates by co-change with one of its files and measure recall@10
against the rest. The control is a **popularity baseline** — ranking by raw change
frequency — because co-change may do nothing but recapitulate "these files change a lot".

Primary repository: 747 commits, 901 files, polyglot microservices.

| | recall@10 | vs popularity | vs chance | median degree |
|---|---|---|---|---|
| commit cap 50, no damping | 0.239 | **2.44×** | 18.8× | 13 |
| + hub cap at 15% of commits | 0.245 | **2.49×** | — | 13 |

**Not a hairball, and not merely popularity.** Both gates pass where measured.

Parameter findings:

- **Commit size cap matters for the tail, not the median.** Recall is flat at 0.237–0.243
  across caps of 30/50/100, but the cap is what prevents bulk commits from connecting
  everything. On a second, much smaller repository (37 usable commits) the *uncapped* graph
  had median degree 472 of 706 files, with 89% of files having more than 100 partners —
  the hairball failure mode, exactly as feared, and produced entirely by large commits.
- **A minimum edge weight hurts.** Requiring weight ≥2 drops lift from 2.44× to 1.91× and
  coverage from 787 files to 336. Single co-occurrences carry real signal; do not threshold.
- **A light hub cap helps slightly, an aggressive one hurts.** Excluding files that appear
  in more than 15–25% of commits removed one file, nudged recall up and cut maximum degree
  from 329 to 249. At 10% recall fell to 0.208, at 5% to 0.196. This is the same remedy
  `cluster.hub_cap` already applies for the same reason.
- The hubs are the expected class: a roadmap doc, `docker-compose.yml`, service entry
  points, a barrel `App.tsx`, a backlog CSV.

**What this does not establish, and must be said with the result:**

- **n=1.** One repository had enough history to evaluate. The second did not.
- **Neither is a legacy monolith.** The primary repository is microservices — the case of
  most concern, where everything plausibly changes together, remains untested.
- **recall@10 = 0.24 means 76% of co-changed files are not in the top ten.** Co-change
  edges must therefore **add to** blast radius and never bound it. The "unknown, not small"
  reporting stays; what changes is that some neighbours become known, not that the set
  becomes complete.
- **Cold start was ~50%** — half the query files had no co-change history in training. For
  legacy modernization the files being touched are old and would have history, so this is
  plausibly better in the real case. Plausibly, not measured.
- Co-change predicts *changed in the same commit*, which is a proxy for blast radius rather
  than blast radius itself.

**Design conclusion.** Ship it with a commit-size cap and a light hub cap, no weight
threshold — and have the indexer **measure its own degree distribution and refuse to emit
a graph that is a hairball**, reporting the source as uninformative for that repository
instead. That is what makes the untested monolith case safe: the failure mode is
detectable from the data itself, so it does not have to be predicted.

**Gate 3 — component field names are bound by the first real polyglot project**, not by this
note.

---

## 5. Open questions

**Is the backend moving?** GitHub Issues, a REST API, or a hosted database have been raised
as future tracking options. If that move is likely, deepening the *task-file* schema with
components and migration edges is work that migrates badly, and the explicit ingest adapter
boundary should come first. The derived-index invariant is what makes an alternative backend
cheap at all — the derivation, planning, clustering and status logic downstream of ingest
are already source-agnostic — but the seam is currently implicit, hardcoded to markdown
frontmatter and `events.ndjson` in `kit-index.sh`. **This question should be answered before
section 1 is built, not after.**

**Behaviour preservation has no rung.** For modernization the real acceptance criterion is
whether the new component reproduces the old one's observable behaviour. The ladder's five
rungs do not include equivalence or characterization testing against the source system.
`covers` is the natural edge and is currently unwritten.

**Non-Claude models are out of scope, and that is a protocol fact rather than a decision.**
Claude Code accepts Anthropic Messages, Bedrock InvokeModel and Google Agent Platform
formats. OpenAI's `/v1/chat/completions` is not among them, gateway model discovery ignores
ids that do not begin with `claude` or `anthropic`, and routing to non-Claude models through
a gateway is explicitly unsupported. Translating wire formats is a proxy by definition.

What this *does* mean for design: the agents pin `model: opus|sonnet|haiku`, and those are
**aliases**, remapped by `ANTHROPIC_DEFAULT_OPUS_MODEL` and its siblings. The agents depend
on three tiers — deep reasoning, working, cheap — not on three products. **Never pin a full
model id in agent frontmatter**, because that converts a remappable alias into a hard
dependency for every operator downstream.
