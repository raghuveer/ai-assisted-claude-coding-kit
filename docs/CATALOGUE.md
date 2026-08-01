# Library catalogue — proposed, not built, and not part of this kit

> **Status: seeded, not earned.** Nothing here exists. The solution lists below are a
> starting point offered by the architect, not a validated selection. The savings figures
> are derived from one real backlog and are stated with their basis so they can be argued
> with rather than quoted.
>
> **Scope warning up front:** this proposal is larger than the kit. The catalogue is an
> N-languages × M-solutions engineering programme with its own release cadence. The kit's
> role is selection and enforcement — it must not host the code. Read [`VERSIONING.md`](VERSIONING.md)
> for why: coupling a library catalogue to a plugin means every RabbitMQ adapter fix churns
> the plugin version, and the version stops signalling anything about the engine.

## 1. The idea, and where it already connects

Interface first, adapters behind it. A message-queue interface is defined once per
language and committed; concrete implementations for RabbitMQ, AmazonMQ and others follow,
each typically wrapping that vendor's own SDK. Repeat per language. Prioritise which
concretes get built. The result is a catalogue whose methods are contextually similar
across languages while each implementation stays idiomatic in its own.

**This is the pattern accelerator at a later maturity.** `accelerators/pattern/cache-port.md`
lists seven obligations — one owner for degradation, no backend primitives on the port,
state an atomicity requirement, key on the resolved permission set. Those are not review
notes. They are *the specification for a cache library*. An obligation that recurs across
enough projects stops being something each project checks and becomes something every
project depends on.

So the on-ramp already exists. What is new is the destination:

| | form | lives in | the kit's role |
|---|---|---|---|
| Pattern accelerator | knowledge | this repo, or a shared accelerator repo | resolve it to the agents that need it |
| **Catalogue library** | **code** | **its own repositories, per language** | **declare it, select from it, enforce its use** |

## 2. When an interface earns its place

Not everything deserves one, and the UUID example is the clean illustration of both sides.

**The test: is the implementation a deployment decision or a library choice?**

A UUID generator is a *library choice*. Nobody deploys a different UUID service; you pick a
package and you are done. Wrapping it in an interface with adapters buys an abstraction
nobody will ever exercise, and pays for it in indirection forever. Use the language's
native facility, or at most a thin façade so the dependency is named in one place.

A message queue is a *deployment decision*. RabbitMQ or AmazonMQ is chosen by operations,
by cost, by what the client already runs — and it can change after the code is written.
There the interface is load-bearing: switching becomes deploying different infrastructure
and binding a different implementation, with no application change at all.

Apply the test before adding a catalogue entry. An interface with exactly one implementation
that will never have a second is ceremony, and it is the most common way this kind of
catalogue accumulates weight without buying anything.

## 3. Seed catalogue

Offered as a starting point. Two or three concretes per kind, more added by priority.

| Kind | Interface concern | Seed implementations |
|---|---|---|
| **Message queue** | publish, consume, ack/nack, dead-letter, retry budget | RabbitMQ · AmazonMQ |
| **Streams** | append, consume from offset, consumer groups, partition key, ordering guarantee | Kafka · Redpanda · Valkey/Redis Streams · NATS + JetStream |
| **Cache** | get/set/delete, TTL, bounded append, tenant-scoped key construction, degradation owner | Valkey · ElastiCache · Dragonfly |
| **Secrets** | fetch by reference, rotate, envelope encrypt/decrypt | AWS Secrets Manager + KMS · HashiCorp Vault |

Each entry needs, before any code:

- the **interface**, in the language it is being built for, committed on its own
- the **obligations** the interface imposes — this is where a pattern accelerator becomes
  the specification rather than a checklist
- a **conformance suite** every implementation must pass. For a plugin architecture this is
  the highest-leverage asset there is: it makes "implements this interface" a checkable
  claim instead of an aspiration, and it is what lets a fourth adapter be trusted without
  being read. It is also the thing most likely to be skipped.
- the **swap axis** stated explicitly: what actually differs between implementations, and
  what a project gives up by choosing each one.

## 4. Selection

The architect's overlay may fix an implementation. Where it does not, the choice follows
from the project's own facts:

- **required scalability** — Valkey Streams and Kafka are not interchangeable at volume
- **mandate** — a client standardised on AWS is a constraint, not a preference
- **implementation scope** — a POC for a demo and a system with a production timeline
  justify different answers, and the difference should be recorded rather than assumed

Because the boundary is an interface, a fixed choice is not a trap. Changing it later is
deploying different infrastructure and binding a different implementation. That is the
property that makes recording the decision safe: it can be revisited without a rewrite.

## 5. Token savings — grounded, with its basis

Classified against the real 29-task `rag-hu-js` backlog, by whether a catalogue entry
could carry the task:

| | tasks | share |
|---|---|---|
| Catalogue eliminates or heavily shrinks | 11 | **38%** |
| Catalogue cannot help | 18 | 62% |

Eliminated or shrunk: cache port split, adapter conformance suite, cache invalidation
epoch, semantic cache scan, nonce store, Redpanda partitioning and idempotency, DLQ retry
and poison policy, config schema validation, liveness/readiness split, dev stack, interface
definition.

Untouched: tenant isolation policy, ADR consistency, scale-path decisions, audit trail
design, prompt safety, per-tenant quotas, project schema versioning, the OpenAPI contract.

At the measured ~220k per task, 11 tasks is ~2.4M written from scratch. If a catalogued task
collapses to wiring plus configuration plus one integration test — call it ~30k — the same
11 cost ~330k. That is roughly **30–35% off total programme spend**, concentrated entirely
on commodity infrastructure.

**Three qualifications, all of which matter:**

1. `rag-hu-js` is a *platform* project and unusually infrastructure-heavy. A business
   application would be nearer 15–20%, because business logic is not catalogueable.
2. The saving is **moved, not removed.** Someone builds and maintains the catalogue. It
   nets out only across enough projects — the same amortisation bet as the accelerators, at
   larger scale and with a much larger commitment up front.
3. An empty catalogue is worse than none: zero saving, plus the cost of checking whether an
   entry exists.

## 6. Quality — the stronger claim is not uniformity

Uniformity across languages is the stated benefit. The larger one is **structural
impossibility**.

Three tasks in that backlog — chunk cache key not tenant-scoped, semantic cache not scoped
by classification set, `sessionId` used unvalidated as a key segment — are one defect class:
*a key that could be constructed without its isolation dimension*. A catalogue cache library
whose key-construction API **requires** a tenant and a resolved classification set makes all
three impossible to write.

Review catches instances. A type signature catches the class. That is worth more than method
names looking alike, and it is not achievable by review at any budget.

### Two risks to settle before building

**Idiom and uniformity pull against each other.** "Methods look similar contextually" and
"follows the best practices of the specific language" are in tension — Go returns errors,
TypeScript throws, Python has context managers. Settle it explicitly:

> The interface is uniform in **concepts and obligations**, not in signatures.

Without that, the catalogue drifts toward lowest-common-denominator APIs that are idiomatic
nowhere, and teams route around it.

**Defect concentration is uniformity's inverse.** One bug in a catalogue library reaches
every project that pinned it. A catalogue entry is **T3 by construction**, and the number
that matters is its own escape rate — which is the one thing this kit is already built to
measure, provided the findings loop stays closed.

## 7. What actually goes in the kit

Not the catalogue. Four small things, none of which require the catalogue to exist first:

1. **A profile key** declaring which catalogue and which version a project draws from —
   pinned, for the same reason the plugin is pinned: otherwise nobody can tell which version
   a piece of feedback is about.
2. **Pattern entries point at implementations.** Extend the pattern axis so `cache-port`
   names its catalogue libraries per language. That records knowledge graduating into code,
   and makes the graduation visible rather than folkloric.
3. **A review obligation:** *was there a catalogue entry for this, and if not, why was it
   hand-rolled?* Plus a finding class for re-implementing a catalogued capability. This is
   the enforcement, it costs nothing to run, and it is the only part that works on day one.
4. **The overlay pins the choice**, and the interface boundary is what makes pinning safe.

## 8. The gate

This is the fourth large proposal recorded here — after the component model, the solution
overlay and the versioned accelerator library — and none of the first three are built. The
kit currently has ten open tasks, a findings loop that only began working on 2026-08-01, and
its core amortisation bet still unproven at the *knowledge* scale.

The catalogue is that same bet with roughly an order of magnitude more cost up front.

**So the cheap version has to pay first.** Import `accelerators/pattern/cache-port.md` into
an independent project with a comparable design, run the review with and without it, and
measure. The metric is not tokens — it is how many of the seven obligations the unaided run
rediscovers. If seven obligations on one page do not move that number, seven libraries will
not either. If they do, that is the evidence that justifies the far larger investment.

Note the honest constraint on running that test: whoever wrote the accelerator cannot also
author the design it is tested against, and it cannot be tested against the design it was
derived from. It needs an independent case.
