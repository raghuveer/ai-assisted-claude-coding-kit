---
id: T-20260819-nothing-computes-whether-a-change-is-hig
title: Nothing computes whether a change is high stakes so the security reviewer runs always or never
epic: agent-contracts
tier: T2
lang: bash
paths: agents/security-reviewer.md, templates/project-profile.md, tooling/kit-status.sh
state: open
---

## Intent

`agents/security-reviewer.md` already carries the correct policy in its own frontmatter: *"Use for
HIGH-STAKES changes ONLY (per the project profile's risk tiering) — crypto/key custody,
authn/authz decision points, any fail-closed path, DB migrations, the request hot path, and
quota/limit enforcement. **Skip for routine CRUD/UI/docs.**"*

**Nothing computes it.** The judgement is left to the operator, and in unattended operation that
collapses to always or never — one wastes the budget, the other removes the gate.

The price is measured, not estimated. 2026-08-17, one T3 change, three reviewers:
**security 134,882 tokens**, implementation 140,718, approach 106,119. Per-task security review is
not defensible at that rate; nor is skipping it on the change that needed it.

## The proposal: trigger on TRUST-BOUNDARY CHANGE, not on a timer

`SECURITY.md` §1 enumerates the trust boundaries. The question *"does this change add or modify a
row in that table — a new input parsed, a new path executed, a new path an agent is told to
load?"* is evaluable, and it is strictly better than periodicity.

**A periodic rule reviews a quiet fortnight and misses the week a new input class lands.** That is
not hypothetical: ADR 0004 made `.project/plans/*.tsv` a committed, auto-ingested, agent-facing
input, and that was exactly the week the security review earned its cost — it returned REJECT with
a path traversal into an agent's context, a `1e999` score that killed the index build, and an
ignored `awk` exit status.

## Acceptance criteria

- [ ] The high-stakes question is **computed and recorded**, not left to recall — from the changed
      paths against declared risk surfaces, and from whether `SECURITY.md` §1 gained or changed a
      row.
- [ ] The declaration lives in the profile in the same flat `key: value` shape as `tier.rule`, and
      a project that declares nothing gets a **stated default rather than silence**. Silence here
      means "never invoke", which is the failure mode with no symptom.
- [ ] The rule has **one home** and the agent file reads from it rather than restating it. The
      finding vocabulary drifted across four locations once and produced agents whose output the
      recorder rejected.
- [ ] `kit-status.sh` reports when the reviewer was last invoked and on what basis, so "it did not
      run" is distinguishable from "it ran and found nothing" — the same distinction
      `T-20260808-make-the-security-assurance-cadence-a-po` requires of the assurance layers.
- [ ] **A check that can fail**, and it must cover the quiet direction: a change touching only
      documentation must NOT trigger, and a change adding a parsed input MUST. A trigger that only
      ever fires is the always-on warning people learn to skip.

## Notes

Filed 2026-08-19 after an audit found it referenced but unwritten:
`T-20260819-researcher-carries-no-security-baseline-` explicitly defers the trigger question to
`T-20260808-make-the-security-assurance-cadence-a-po`, and that task covers **scope and cadence**
— which layers a project runs and how often — with nothing on when the per-diff reviewer is
invoked. Two tasks pointed at a criterion that existed in neither.

Proposal recorded in `docs/design-input/2026-08-18-authoring-chain-and-review-economics.md` §3.

**Not a licence to loosen the gate.** The reviewer becomes cheaper because fewer known-class
defects survive design (see the researcher task), not because the trigger is relaxed. If this ends
up invoked less often on the same change profile, that is a regression wearing the shape of a
saving.
