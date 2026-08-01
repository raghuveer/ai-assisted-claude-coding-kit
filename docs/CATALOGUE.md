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

### Swap cost is not uniform inside a kind

The stream kind makes this obvious, and the catalogue should record it rather than implying
that everything behind one interface is equally interchangeable:

- **Kafka ↔ Redpanda** is close to free. Redpanda speaks the Kafka wire protocol, so the
  same client library binds to either. This is the cheapest swap in the entire seed list and
  the best first proof that an interface works.
- **Kafka ↔ Valkey/Redis Streams** is a reimplementation. Consumer groups exist in both and
  do not mean the same thing; partitioning, retention and ordering guarantees all differ.
- **Kafka ↔ NATS JetStream** differs again, with its own consumer and acknowledgement model.

So each implementation carries a **guarantee profile**, and the swap cost between any two is
the delta between their profiles. An entry that does not record its profile is an entry
nobody can safely swap.

### Which leaves the design decision

Given profiles, three ways to define an interface, one dishonest:

1. **Intersection.** Define on what every member can meet. Portable, and you give up what
   you paid the vendor for.
2. **Declared guarantees.** The interface states what it *requires* — ordered-per-key,
   replayable, at-least-once, exactly-once-effective — and each implementation states what it
   *provides*. Binding **fails at startup** on a mismatch. More work, and the only design
   that stays honest as the catalogue grows.
3. **Leak the strongest member's model and hope.** What most such layers do, and why
   "cloud-agnostic" so often means "runs on the one we built it against".

Recommend (2). **Portability is a property of a declared guarantee set, not of an interface
name.** A project needing replay is not portable to SQS, and the system should say so at bind
time rather than in production.

## 4. Seed catalogue

Offered as a starting point. Two or three concretes per kind, more added by priority.

| Kind | Model | Interface concern | Self-hostable | Managed |
|---|---|---|---|---|
| **Message queue** | destructive, per-message ack | publish, consume, ack/nack, dead-letter, retry budget, redelivery semantics | RabbitMQ | AmazonMQ · SQS |
| **Streams** | cursor, replayable | append, consume from offset, consumer groups, partition key, ordering, retention | Kafka · Redpanda · Valkey/Redis Streams · NATS JetStream | MSK · managed equivalents per vendor |
| **Cache** | — | get/set/delete, TTL, bounded append, tenant-scoped keys, degradation owner | Valkey · Dragonfly | ElastiCache |
| **Secrets** | — | fetch by reference, rotate, envelope encrypt/decrypt | HashiCorp Vault | Secrets Manager + KMS |

Each entry needs, before any code:

- the **interface**, committed on its own, in the language it is built for
- its **declared guarantees**, and a **guarantee profile per implementation** — the part that
  makes portability checkable and swap cost visible
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

**Start with Kafka and Redpanda.** They share a wire protocol, so the swap is close to free
and the test isolates whether the *interface* is sound rather than whether two very different
brokers can be reconciled. If the suite cannot pass across those two, nothing further down
the list will pass either, and the failure is in the abstraction rather than in the distance
between implementations.

Then RabbitMQ against SQS as the second proof, because that pair genuinely differs — push
subscription against poll with a visibility timeout — while remaining one consumption model.
Passing both is evidence the interface spans real difference and not just a rebrand.

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
