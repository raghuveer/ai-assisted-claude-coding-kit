# Library catalogue — proposed, not built, and not part of this kit

> **Status: seeded, not earned.** Nothing here exists. The solution lists below are a
> starting point offered by the architect, not a validated selection. The savings figures
> are derived from one real backlog and are stated with their basis so they can be argued
> with rather than quoted.
>
> **Scope warning up front:** this proposal is larger than the kit. The catalogue is an
> N-languages × M-solutions engineering programme with its own release cadence. The kit's
> role is selection and enforcement — it must not host the code. See [`VERSIONING.md`](VERSIONING.md):
> coupling a library catalogue to a plugin means every RabbitMQ adapter fix churns the
> plugin version, and the version stops signalling anything about the engine.

## 1. The driver is deployment portability

The goal is that **the same application source runs unchanged whether it is deployed on
AWS, on another cloud, or on-premises** — only the deployed infrastructure and the bound
implementation differ. Interfaces and adapters are the mechanism that makes that claim
true rather than aspirational.

This ordering matters, because it changes what the proposal has to be judged against:

| | |
|---|---|
| **Primary** | portability — no code change across deployment targets |
| Secondary | reuse across projects, and the token savings that follow |
| Secondary | uniform quality across languages |

If portability is a product requirement — selling the same system to a client who mandates
AWS and another who mandates on-premises — then the catalogue is not an optimisation that
must pay for itself in saved tokens. It is the thing that makes the requirement satisfiable
at all, and the savings are a side effect worth measuring but not worth waiting for.

### Why it has to be a catalogue and not a practice

Portability promised per engagement is a per-engagement tax, and it is charged at exactly the
wrong moment. The interface work lands early, before the deadline is real; the pressure to
"just call the SDK directly, we can abstract it later" arrives late, when the abstraction is
the only thing standing between the team and a shipped feature. Later does not come, and the
portability that was sold is quietly not delivered — usually without anyone deciding to drop
it.

A catalogue moves that cost off the project entirely. The interface already exists, the
adapters already exist, and using them is the path of least resistance rather than the
disciplined path. That inversion is the point: portability survives schedule pressure only
when the portable option is also the easy one.

It also changes what can be shown to a client. "We designed it to be portable" is an
assertion. "No vendor SDK is imported outside its adapter, and here is the check that proves
it" is a deliverable — see section 5, which needs no catalogue to be useful.

The rest of this note assumes that framing.

## 2. Which capabilities need an interface

An earlier draft of this note proposed: *is the implementation a deployment decision or a
library choice?* Portability sharpens that into something you can apply mechanically:

> **Does this capability have a vendor-specific managed service?**

A UUID generator does not. Nobody deploys a UUID service; you pick a package, and wrapping
it buys an abstraction nobody will ever exercise while charging indirection forever. Use the
language's native facility, or a thin façade so the dependency is named in one place.

A message queue does. So do cache, streams, object storage, secrets, and identity — those
are precisely the surfaces every cloud vendor sells a managed version of, and precisely the
surfaces that pin an application to a vendor when used directly.

The corollary is a rule the seed list below already follows but which should be stated:

> **Every kind needs at least one self-hostable implementation and at least one managed
> one. Otherwise the portability claim is false for one of the two deployment targets.**

RabbitMQ and AmazonMQ. Valkey and ElastiCache. HashiCorp Vault and Secrets Manager + KMS.
A kind with only managed implementations cannot deploy on-premises; a kind with only
self-hosted ones gives up the operational reason to be on a cloud at all.

## 3. The consumption model is the kind boundary

Vendors market "messaging". That is not one kind, and treating it as one with capability
tiers between the members is the first mistake available. There are two, divided by how a
consumer gets a message and what happens to it afterwards:

| | **Queue** | **Stream / log** |
|---|---|---|
| Consumption | destructive — acked and gone | non-destructive — a cursor moves |
| Position | the broker owns it | the consumer owns it |
| Replay | no | yes, within retention |
| Retention | until consumed | time or size, independent of consumption |
| Scale-out | competing consumers on one queue | partitions, one consumer per partition per group |
| Members | RabbitMQ · AmazonMQ · SQS | Kafka · Redpanda · Valkey/Redis Streams · NATS JetStream |

**Portability exists within a consumption model and never across one.** This is the rule the
whole catalogue design rests on.

An application that acks and forgets is structurally different from one that replays from a
stored offset on restart — different failure handling, different idempotency requirements,
different recovery story. You cannot move between them by changing configuration, because
the difference is in the application, not the binding. So they are two catalogue kinds with
two interfaces, and an interface spanning both would be an interface for neither.

### Push and pull are transport, not semantics

Within the queue kind the delivery mechanism still differs, and this is the distinction that
looks fundamental but is not:

- **RabbitMQ and AmazonMQ push.** The broker drives delivery via a subscription, with
  prefetch controlling flow. AmazonMQ runs the same engines, which is why it is a genuine
  drop-in for RabbitMQ rather than a lookalike.
- **SQS pulls.** The consumer polls, long-poll included, and unacked messages return after a
  visibility timeout rather than being requeued on a channel close.

Both are still *destructive consumption with per-message acknowledgement*. That is what an
interface can span: a handler invoked per message, an ack, a nack. Whether the library runs
a polling loop or holds a subscription is an implementation detail, and hiding it is
legitimate.

What cannot be hidden is redelivery: a visibility timeout and an ack/requeue are not two
spellings of one behaviour. That belongs in the declared guarantees below, not papered over.

### Portability tiers inside a kind

Implementations of one kind are not equidistant. They fall into tiers, and the tier decides
what work a swap actually costs:

| Tier | What differs | Swap cost | Examples |
|---|---|---|---|
| **1 — protocol-identical** | operator, not protocol | configuration only | RabbitMQ ↔ AmazonMQ (RabbitMQ engine) · Kafka ↔ Redpanda |
| **2 — same model, different protocol** | wire format, redelivery, partitioning | the adapter absorbs it | RabbitMQ ↔ SQS · Kafka ↔ NATS JetStream · Kafka ↔ Valkey/Redis Streams |
| **3 — different consumption model** | the application's own structure | not a swap | queue ↔ log |

Tier 1 is where a managed service pairs with the engine it manages, and it is why the seed
list pairs them that way. Tier 2 is where the interface earns its keep. Tier 3 is section 3's
rule: not portable, by construction.

### Absorb, then declare, then separate

For each difference between two implementations, in this order:

1. **Absorb it.** The adapter reconciles the difference so the application never sees it.
   SQS long-polling presented as a per-message handler; a visibility timeout derived from the
   interface's redelivery-delay; a partition key mapped onto a NATS subject. Cost is adapter
   complexity, paid once, by the catalogue rather than by every project.
2. **Declare it.** Where absorption would be a lie, the interface states the guarantee it
   *requires* and each implementation states what it *provides*, and binding **fails at
   startup** on a mismatch. Replay is the clean example: it cannot be synthesised on SQS
   without becoming a broker.
3. **Separate it.** Where the difference is the application's own architecture, it is a
   different kind. Queue against log.

**Prefer absorption.** Every difference absorbed widens the portable set, and that is the
whole point — a difference the adapter swallows is one no project ever pays for again.

### The line absorption must not cross

Absorption is a lie when it holds in the happy path and breaks under failure, concurrency or
load. Two tests:

- **Does it survive the operational characteristic the implementation was chosen for?** An
  adapter that emulates ordering by single-threading has technically absorbed the difference
  and destroyed the throughput someone chose Kafka for. That is a lie by performance.
- **Does it survive failure?** An adapter that emulates replay by buffering messages itself
  has become a broker, with its own durability and its own failure modes, and nobody
  reviewed it as one.

If absorption cannot pass both, escalate to declare. This is the judgement the conformance
suite exists to check: a suite that only runs the happy path certifies exactly the absorption
that is about to fail in production.

So each implementation carries a **guarantee profile** recording what it provides natively,
what its adapter absorbs, and at what cost. The swap cost between any two is the delta
between profiles, and an entry without a profile is one nobody can safely swap.

## 4. Seed catalogue

Offered as a starting point. Two or three concretes per kind, more added by priority.

| Kind | Model | Tier 1 pair (config-only) | Tier 2 reach (adapter absorbs) |
|---|---|---|---|
| **Message queue** | destructive, per-message ack | RabbitMQ ↔ **AmazonMQ** | SQS |
| **Streams** | cursor, replayable | Kafka ↔ **Redpanda** | NATS JetStream · Valkey/Redis Streams |
| **Cache** | — | Valkey ↔ **ElastiCache** | Dragonfly |
| **Secrets** | — | HashiCorp Vault ↔ **HCP Vault** | Secrets Manager + KMS |

Managed in bold. Each row has a tier-1 pair that proves the interface cheaply and a tier-2
reach that proves it abstracts. Build the tier-1 pair first for every kind: it is the
smallest thing that produces a working interface, a conformance suite and a portability
test, and it is the evidence needed before committing to tier 2.

Interface concerns per kind:

| Kind | The interface has to express |
|---|---|
| Message queue | publish · consume · ack/nack · dead-letter · retry budget · redelivery semantics |
| Streams | append · consume from position · consumer groups · partition key · ordering guarantee · retention |
| Cache | get/set/delete · TTL · bounded append · tenant-scoped key construction · degradation owner |
| Secrets | fetch by reference · rotate · envelope encrypt/decrypt |

Each entry needs, before any code:

- the **interface**, committed on its own, in the language it is built for
- its **declared guarantees**, and a **guarantee profile per implementation** — the part that
  makes portability checkable and swap cost visible
- the **obligations** it imposes, which is where a pattern accelerator becomes the
  specification rather than a checklist
- a **conformance suite** every implementation must pass — the highest-leverage asset in a
  plugin architecture, because it makes "implements this interface" checkable instead of
  claimed, and it is the thing most likely to be skipped

## 5. The vendor-boundary check

One rule, mechanically checkable:

> **A vendor SDK may only be imported inside its own adapter.**

One `import boto3` in a service, one `AmazonSQSClient` in a handler, and the portability
claim is **false** — not degraded, false, because that deployment target now requires a code
change. This is the same shape as the tenant-key argument in section 7: a property enforced
by structure rather than by review.

**It is the cheapest item in this proposal and the only one that pays before the catalogue
exists.** A project that never adopts a single catalogue library still benefits from knowing
where its lock-in lives. On an inherited codebase it is a survey; on a new one it is a gate.

### What gets declared

In the project profile:

```
deploy.target: aws
deploy.target: on-prem                  # repeatable — portability is meaningless
                                        # against an unstated set, and "we might go
                                        # on-prem one day" is not a target
adapter.path: src/adapters/**           # repeatable — where vendor SDKs ARE allowed
adapter.path: src/infrastructure/**
```

**The SDK patterns themselves do not belong in the kit.** `boto3`, `@aws-sdk/*`,
`github.com/aws/aws-sdk-go`, `software.amazon.awssdk`, `Amazon.*` are stack-specific, and a
stack-agnostic kit that hardcodes them stops being stack-agnostic. They belong in the
**technology accelerator** for each language, which is exactly the axis that already exists
for "what is true of this language":

```
# in accelerators/technology/typescript.md
vendor.sdk: @aws-sdk/          -> aws
vendor.sdk: @azure/            -> azure
vendor.sdk: @google-cloud/     -> gcp
```

The kit supplies the mechanism; the accelerator supplies the patterns. That keeps the check
extensible to a stack nobody anticipated without touching the plugin.

### What counts as a violation

Three, in descending order of detectability:

1. **A vendor SDK imported outside `adapter.path`.** Grep-detectable, unambiguous, and the
   overwhelming majority of real leaks.
2. **A vendor type in an interface signature.** `Task<SendMessageResponse>` on a port means
   every implementation must produce an SQS response object. Detectable by inspecting the
   interface files only, which is a small and stable set.
3. **Vendor-specific configuration read outside an adapter** — an environment variable named
   for a service, a region string, an ARN parsed in business logic. Hardest to detect and
   worth stating as a review obligation rather than pretending to automate.

### Where it runs, and the ladder answer

Both, and the split follows the kit's existing rule rather than inventing one:

- **As a mechanical check** where the language's tooling supports it — a lint rule, a grep
  over the import graph, a module-boundary plugin. This is a rung-3 style *wiring proof*.
- **As a review obligation** where it does not. `verify-ladder` already handles this case:
  a rung with no tooling is **declared unavailable and the tier rises**. An unautomatable
  boundary check means more adversarial reading, not a skipped check.

A violation is a `compliance` finding with `pattern: vendor-boundary`, which puts it in the
same table as everything else and lets its recurrence be counted across projects.

### The limits, stated

**Transitive dependencies are the real gap.** Your code can be clean while a library you
depend on imports the vendor SDK itself. The check sees your import graph, not your
dependency tree, and closing that properly means walking the lockfile — which is worth
doing later and worth *saying* now, because a green check that only covers first-party code
is exactly the kind of assurance that gets over-read.

**Dynamic imports, reflection and generated code defeat it.** Like the write guard, this is
a net rather than a proof, and it should say so where it reports.

**And the deeper limit:** a clean import graph does not mean a portable design. An interface
can contain no vendor types and still be shaped entirely around one vendor's semantics —
visibility timeouts, ARNs as identifiers, at-most-once assumptions. The check proves
containment. **Only the tier-2 conformance test in section 9 proves abstraction.** The two
are complementary and neither substitutes for the other.

### Build order

Even this small piece has a sequence, and the first step is useful alone:

1. **Declaration only.** `deploy.target` and `adapter.path` in the profile, and nothing
   reads them yet. This is already documentation with a purpose: it forces someone to state
   which targets are actually supported, which is a question most projects have never
   answered explicitly.
2. **Review obligation.** Reviewers are told to check the boundary and record a
   `compliance` finding. Works on every stack immediately, no tooling.
3. **Mechanical check** where the stack allows, sourcing patterns from the technology
   accelerator. This is where it becomes a deliverable a client can be shown.
4. **Transitive walk**, last, and only if the first three prove worth keeping.

## 6. Token savings — real, and not the reason

Classified against the real 29-task `rag-hu-js` backlog, by whether a catalogue entry could
carry the task:

| | tasks | share |
|---|---|---|
| Catalogue eliminates or heavily shrinks | 11 | **38%** |
| Catalogue cannot help | 18 | 62% |

At the measured ~220k per task, 11 tasks is ~2.4M written from scratch. If a catalogued task
collapses to wiring plus configuration plus one integration test — call it ~30k — the same
11 cost ~330k. Roughly **30–35% off total programme spend**, concentrated entirely on
commodity infrastructure.

Three qualifications, all of which matter: `rag-hu-js` is a *platform* project and unusually
infrastructure-heavy, so a business application would be nearer 15–20%; the saving is **moved
rather than removed**, since someone builds and maintains the catalogue; and an empty
catalogue is worse than none, costing the check without the benefit.

Under the portability framing these numbers are a bonus, not a justification. A catalogue
that saved nothing would still be required if the same code must deploy to a cloud and to a
customer's own data centre.

## 7. Quality — structural impossibility beats uniformity

Uniform method names across languages are the stated benefit. The larger one is that a
well-shaped interface makes a defect class **unwritable**.

Three tasks in that backlog — chunk cache key not tenant-scoped, semantic cache not scoped
by classification set, `sessionId` used unvalidated as a key segment — are one defect class:
*a key that could be constructed without its isolation dimension*. A cache library whose
key-construction API **requires** a tenant and a resolved classification set makes all three
impossible to write.

Review catches instances. A type signature catches the class.

### Two risks to settle

**Idiom and uniformity pull against each other.** Go returns errors, TypeScript throws,
Python has context managers. Settle it explicitly: *the interface is uniform in concepts,
guarantees and obligations — not in signatures.* Otherwise the catalogue drifts toward APIs
that are idiomatic nowhere and teams route around it.

**Defect concentration is uniformity's inverse.** One bug in a catalogue library reaches
every project that pinned it. A catalogue entry is **T3 by construction**, and the number
that matters is its own escape rate — which this kit is already built to measure, provided
the findings loop stays closed.

## 8. What actually goes in the kit — nothing new

The libraries are their own projects. The interface for a kind is committed on its own, in
its own repository, and each implementation is a separate repository behind it. They version
independently, they release on their own cadence, and none of it belongs to this plugin.

**The technology accelerator is the index.** No new kit mechanism is needed, because the
accelerator is already the per-language axis, already resolved per agent and per component,
and already the place SDK patterns were going to live:

```
# accelerators/technology/typescript.md

## Portable libraries
queue     interface: github.com/<org>/queue-ts@2.1        impls: rabbitmq@2.1 · amazonmq@2.0 · sqs@1.4
streams   interface: github.com/<org>/streams-ts@1.3      impls: kafka@1.3 · redpanda@1.3 · jetstream@0.9
cache     interface: github.com/<org>/cache-ts@3.0        impls: valkey@3.0 · elasticache@3.0
secrets   interface: github.com/<org>/secrets-ts@1.1      impls: vault@1.1 · secretsmanager@1.0

## Vendor SDK patterns
vendor.sdk: @aws-sdk/      -> aws
vendor.sdk: @azure/        -> azure
```

Selection then falls out of machinery that already exists, with nothing added:

1. The **overlay** states the stack and may pin an implementation — a client mandating AWS
   is a constraint, and pinning is safe because the interface makes it reversible.
2. The **technology accelerator** for that stack names the interface and the implementations
   available for it.
3. Where the overlay has not pinned, the choice follows the project's own facts — required
   scalability, deployment targets, whether this is a demo or has a production timeline — and
   is recorded rather than assumed.

**This removes the profile key an earlier draft proposed.** "Which catalogue, which version"
becomes "which technology accelerator, which version", which is already declared, already
pinned, and already resolved. One fewer mechanism, and language-specific facts stay on the
language axis where the rest of them are.

So the kit's entire share of this proposal reduces to:

1. **The vendor-boundary check** (section 5) — the only genuinely new thing, and it works
   with no libraries at all.
2. **A review obligation** — *was there a catalogue entry for this, and if not, why was it
   hand-rolled?* — plus a finding class for re-implementing a catalogued capability.
3. **Accelerator content**, which is authoring, not engineering.

### Why separate repositories, and it is not governance

An earlier draft of this note called repository-per-implementation a governance choice with a
cost, and suggested a monorepo per language by default. That was wrong for a delivery context,
and three reasons override the CI overhead:

**Licence isolation.** Underlying clients differ — AGPL, GPL, MIT, Apache-2.0 — and the
licence of an adapter is the licence of what it wraps. A client who cannot accept copyleft
must be able to *prove* it never entered the build, not argue that the package they consumed
happened not to include it. When the boundary is the repository, the proof is the dependency
graph of one artifact rather than an argument about which subset of a monorepo shipped.

**Attack surface and SBOM.** A project pulls the interface plus only the adapters it deploys.
Its SBOM then contains exactly what it runs, and a vulnerability in the AmazonMQ adapter's
transitive dependencies never appears in an on-premises deployment's report. In a monorepo
the published packages can achieve this, but the audit trail is weaker and the burden of proof
sits with the consumer.

**Approval granularity.** An implementation wrapper can be reviewed, approved and pinned on
its own. A client security team approving "the queue interface plus the RabbitMQ adapter" is
approving two artifacts with two dependency sets, not a subset of a larger repository they
must then verify was not otherwise used.

The CI and release overhead is real — four kinds × four languages × three implementations is
upwards of sixty repositories — and it should be automated from a template rather than
absorbed by hand. But it buys provable licence and dependency isolation, which is not
something a monorepo can offer at the same strength.

## 9. The acceptance test

Portability makes this proposal falsifiable in a way the savings argument never was:

> The application's integration suite passes against implementation A, then against
> implementation B, with **only configuration changed** — no diff in application source.

That is mechanically checkable, it is the level the failure actually lives at, and it is the
only evidence that the interface did its job. An interface that has never been exercised
against a second implementation has not been shown to abstract anything.

Run it in CI for at least one kind, early, against one self-hosted and one managed
implementation. If it cannot pass there, the catalogue is documentation.

**Start inside tier 1** — Kafka against Redpanda, or RabbitMQ against AmazonMQ. A shared
protocol means the swap is nearly free, so the test isolates whether the *interface* is sound
rather than whether two dissimilar brokers can be reconciled. If it cannot pass there,
nothing further down will, and the fault is the abstraction rather than the distance.

**Then cross into tier 2** — RabbitMQ against SQS, or Kafka against NATS JetStream. That is
where absorption is actually exercised: push subscription against poll-with-visibility-timeout,
explicit partitions against subject routing. Passing tier 1 proves the interface is coherent;
passing tier 2 proves it abstracts something.

Run the tier-2 suite under failure and concurrency, not only the happy path. Absorption that
holds when nothing goes wrong is exactly the absorption that fails in production, and a green
happy-path suite is how it gets certified on the way there.

## 10. The gate on everything else

This is the fourth large proposal recorded here — after the component model, the solution
overlay and the versioned accelerator library — and none of the first three are built. The
kit has ten open tasks, a findings loop that only began working on 2026-08-01, and its
amortisation bet unproven at the *knowledge* scale.

Section 8 item 1 is the exception and should be built regardless: it is cheap, it works
without a catalogue, and it tells a project where its lock-in already is.

The rest waits on evidence. Import `accelerators/pattern/cache-port.md` into an independent
project with a comparable design, run the review with and without it, and count how many of
the seven obligations the unaided run rediscovers. If seven obligations on one page do not
move that number, seven libraries will not either.

The constraint on running that test honestly: whoever wrote the accelerator cannot author
the design it is tested against, and it cannot be tested against the design it came from.
