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

## 3. The hard problem: semantics, not signatures

This is where vendor-agnostic abstraction layers usually fail, and it deserves to be
decided before any code is written.

Implementations of the same kind do not offer the same guarantees:

- SQS has a visibility timeout; RabbitMQ has ack/nack with requeue. Different redelivery
  models, not different spellings of one model.
- Kafka has partitions and replayable offsets. SQS has no ordering outside FIFO queues and
  no replay at all. NATS JetStream has its own consumer semantics again.
- Managed services impose quotas and message-size ceilings that a self-hosted broker
  does not.

An interface that exposes `offset` cannot be implemented on SQS. An interface that exposes
only `ack` throws away the replay you chose Kafka for. So there are two honest designs and
one dishonest one:

1. **Intersection.** Define the interface on the guarantees every implementation can meet.
   Portable, and you give up what you paid the vendor for.
2. **Capability tiers.** The interface declares what it requires — ordered-per-key,
   replayable, at-least-once — and an implementation declares what it provides. Binding
   fails at startup when a project asks for a guarantee its chosen implementation cannot
   give. More work, and it is the only design that stays honest as the catalogue grows.
3. **Leak the strongest vendor's model and hope.** This is what most such layers do, and it
   is why "cloud-agnostic" so often means "runs on the one we built it against".

Recommend (2), and record the decision: **portability is a property of a declared guarantee
set, not of an interface name.** A project that needs replay is not portable to SQS, and the
system should say so at bind time rather than in production.

## 4. Seed catalogue

Offered as a starting point. Two or three concretes per kind, more added by priority.

| Kind | Interface concern | Self-hostable | Managed |
|---|---|---|---|
| **Message queue** | publish, consume, ack/nack, dead-letter, retry budget | RabbitMQ | AmazonMQ |
| **Streams** | append, consume from offset, consumer groups, partition key, ordering | Kafka · Redpanda · Valkey/Redis Streams · NATS + JetStream | (managed equivalents per vendor) |
| **Cache** | get/set/delete, TTL, bounded append, tenant-scoped keys, degradation owner | Valkey · Dragonfly | ElastiCache |
| **Secrets** | fetch by reference, rotate, envelope encrypt/decrypt | HashiCorp Vault | Secrets Manager + KMS |

Each entry needs, before any code:

- the **interface**, committed on its own, in the language it is built for
- its **declared guarantees**, per section 3 — the part that makes portability checkable
- the **obligations** it imposes, which is where a pattern accelerator becomes the
  specification rather than a checklist
- a **conformance suite** every implementation must pass — the highest-leverage asset in a
  plugin architecture, because it makes "implements this interface" checkable instead of
  claimed, and it is the thing most likely to be skipped

## 5. The invariant that makes portability real

One rule, and it is mechanically checkable:

> **A vendor SDK may only be imported inside its own adapter.**

One `import boto3` in a service, one `AmazonSQSClient` in a handler, and the portability
claim is false — not degraded, false, because that deployment target now requires a code
change. This is the same shape as the tenant-key argument in section 7: a property enforced
by structure rather than by review, verifiable by a grep or a lint rule rather than by
someone remembering.

This is what the solution overlay and `constrained_by` edges are for. An architect declaring
"no vendor SDK outside `adapters/`" is stating a checkable obligation, and a violation is a
`compliance`-class finding that flows into the same table as every other.

**It is also the cheapest part of this entire proposal to build, and it works before a single
catalogue library exists.** A project that has not adopted the catalogue at all still
benefits from knowing where its vendor lock-in lives.

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

## 8. What actually goes in the kit

Not the catalogue. Five things, and the first works with no catalogue at all:

1. **The vendor-SDK boundary as a checkable invariant** — declared in the overlay, enforced
   as a `compliance` finding. Useful on day one, on any project, adopted or not.
2. **A profile key** naming the deployment targets a project must support. Portability is
   only meaningful against a stated set, and "we might go on-prem one day" is not one.
3. **A profile key** declaring which catalogue and version a project draws from, pinned —
   for the same reason the plugin is pinned.
4. **Pattern entries point at implementations**, so knowledge graduating into code is
   visible rather than folkloric.
5. **A review obligation** — *was there a catalogue entry for this, and if not, why was it
   hand-rolled?* — plus a finding class for re-implementing a catalogued capability.

## 9. The acceptance test

Portability makes this proposal falsifiable in a way the savings argument never was:

> The application's integration suite passes against implementation A, then against
> implementation B, with **only configuration changed** — no diff in application source.

That is mechanically checkable, it is the level the failure actually lives at, and it is the
only evidence that the interface did its job. An interface that has never been exercised
against a second implementation has not been shown to abstract anything.

Run it in CI for at least one kind, early, against one self-hosted and one managed
implementation. If it cannot pass there, the catalogue is documentation.

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
