---
id: pattern/cache-port
version: 0.1.0
kind: pattern
source: seeded from one design review; not yet earned across projects
---

# Cache port — reusable design obligations

A pattern accelerator. It is about a **design**, not a language and not an industry, which
is why it lives on neither of the other two axes. Every line below is `[seeded]` until the
findings table shows it recurring across distinct projects.

## Obligations

- [seeded] **One owner for degradation.** Decide whether adapters swallow transport errors
  or a manager wraps every call, and write it down. Two owners means neither is
  responsible, and the failure only shows up when the backend is actually down.
- [seeded] **Do not put backend primitives on the port.** `scan`, `delPattern`, `listPush`,
  `listRange` are Redis mechanics. A port carrying them can only ever be implemented by
  Redis, whatever the interface claims.
- [seeded] **State an atomicity requirement, or state its absence.** A bounded append built
  from get-modify-set is a read-modify-write race. If the contract does not require
  atomicity, an implementer will introduce that race without violating anything written.
- [seeded] **The cache key is an access-control boundary.** Key on the resolved permission
  set, not on a role name. A key-shape change alters who can read what and fails silently:
  nothing errors, the wrong answer is simply served.
- [seeded] **Every key is tenant-scoped, or the invariant is false.** One unscoped key makes
  a stated isolation guarantee untrue, and an invariant people believe is more dangerous
  than one they check.
- [seeded] **Invalidation must not be O(keyspace).** A scan per write is a cost that grows
  with what is cached rather than with what changed. An epoch folded into the key is O(1).
- [seeded] **Say whether a failed invalidation is fatal.** If invalidation inherits
  degrade-to-no-op, a failure acknowledges the write and serves stale data afterwards.

## Where these came from

The first six were raised independently by two reviewers on one cache-port redesign; the
last by the security reviewer alone. Recorded here because the design is reusable across
stacks, which is the axis `lang` and `domain` cannot express.
