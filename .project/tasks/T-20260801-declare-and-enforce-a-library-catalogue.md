---
id: T-20260801-declare-and-enforce-a-library-catalogue
title: Declare and enforce a library catalogue
epic: accelerators
tier: T2
state: open
---

## Intent

The kit's four-part share of the catalogue proposal in docs/CATALOGUE.md. Deliberately
scoped to selection and enforcement: the catalogue itself is code in its own repositories,
per language, with its own release cadence, and coupling it to a plugin would churn the
plugin version on every adapter fix.

None of these four require the catalogue to exist first, and the third works on day one
against an empty catalogue -- it just always answers "no entry".

## Acceptance criteria

- [ ] deploy.target and adapter.path are declared in the profile (step 1, useful alone)
- [ ] reviewers check the vendor boundary and record a compliance finding (step 2)
- [ ] SDK patterns come from the technology accelerator, never hardcoded in the kit
- [ ] a mechanical check exists where the stack allows, and where it does not the rung is
      declared unavailable and the tier rises rather than the check being skipped
- [ ] the report states its limits: transitive dependencies are not covered
- [ ] a profile key declares which catalogue and which version a project draws from, pinned
- [ ] a pattern accelerator entry can name its catalogue implementations per language
- [ ] reviewers are obliged to ask whether a catalogue entry existed for the work
- [ ] a finding class exists for re-implementing a catalogued capability
- [ ] the solution overlay can pin an implementation, and the pin is recorded not assumed
- [ ] an empty or undeclared catalogue costs nothing and warns nothing

## Notes

The driver is deployment portability, not savings: the same application source must run on
a cloud or on-premises with only configuration and the bound implementation differing. That
reordering matters -- a catalogue that saved zero tokens would still be required if the same
system is sold to a client mandating AWS and another mandating their own data centre.

docs/CATALOGUE.md section 5 is the buildable spec, including the four-step build order and
the limits. Two things there are easy to get wrong and are called out: the SDK patterns are
stack-specific and belong in the technology accelerator, not in a stack-agnostic kit; and a
clean import graph proves containment, not portability -- an interface can hold no vendor
types and still be shaped entirely around one vendor's semantics. Only the tier-2 conformance
test proves abstraction.

The first acceptance criterion is the one to build first. It is cheap, it needs NO catalogue
to exist, and it works on any project: one `import boto3` in a service and the portability
claim is false, not degraded. Structurally checkable by grep or lint, exactly like the
tenant-key argument, and it tells a project where its lock-in already lives before anyone
commits to building libraries.

Blocked in spirit, not mechanically, on the amortisation test in docs/CATALOGUE.md section
8. The catalogue is the same bet as the pattern accelerators with roughly an order of
magnitude more cost up front, so the cheap version should demonstrate a return first.

The measured share, against the 29-task rag-hu-js backlog: 11 tasks (38%) could be carried
by a catalogue entry, 18 could not. That is a platform project and unusually
infrastructure-heavy; a business application would be nearer 15-20%.

The strongest argument is not token savings. Three tenant-isolation defects in that backlog
are one class -- a key that could be constructed without its isolation dimension. A cache
library whose key API REQUIRES a tenant and a resolved classification set makes all three
impossible to write. Review catches instances; a type signature catches the class.
