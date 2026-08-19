---
id: T-20260819-researcher-carries-no-security-baseline-
title: researcher carries no security baseline so obligations reach the coder only as review findings
epic: agent-contracts
tier: T2
lang: markdown
paths: agents/researcher.md, agents/adr-scribe.md, templates/project-profile.md
blocked_by: T-20260808-make-the-security-assurance-cadence-a-po
state: open
---

## Intent

`agents/researcher.md` produces the design-input document that `approach-reviewer` attacks and
`coder` implements against. Verified 2026-08-19: it mentions security **once**, at line 25, and
only in passing — *"a sibling control that survived a security review"* — as an argument for
reusing in-repo solutions. There is no security obligation in the document it produces.

The consequence is an economic one. Security requirements currently reach the implementation as
**review findings**, after the code exists, which is the most expensive point at which to learn
them. Measured 2026-08-17 on one T3 change: the security review cost **134,882 tokens**, the
implementation review 140,718, the approach review 106,119. A defect prevented at design time
costs a paragraph in an ADR; the same defect caught at review costs a review plus a rework.

Shifting the baseline left means the obligation lands in the ADR, the coder implements against it,
and the reviewer's job narrows to what a checklist cannot anticipate.

## Blocked by the scope decision, and this ordering is the point

`T-20260808-make-the-security-assurance-cadence-a-po` carries the criterion *"the scope selects
which checklist `researcher` loads"*. That must land first, because **"include OWASP" without a
scope is a firehose that teaches an agent to skim**: ASVS is levelled (L1/L2/L3), the OWASP LLM
Top 10 applies only where there is an LLM surface, and the relevant chapters depend on the target
stack, the maturity of its ecosystem, and the third-party dependencies in play.

Doing this first produces a longer prompt, not a better design input. The dependency is declared
rather than described for the reason recorded in
`docs/design-input/2026-08-18-the-plan-is-the-unreviewed-artifact.md`: a dependency that lives only
in prose does not exist, because `kit-plan.sh` reads `blocked_by` and cannot read a paragraph.

## Acceptance criteria

- [ ] The design-input document `researcher` produces carries the security obligations that apply
      **to this change**, selected by the project's declared scope — not a recital of a standard.
- [ ] The obligations are **cited** (control ID and chapter), so `approach-reviewer` can check the
      selection and `security-reviewer` can see what was already argued rather than re-deriving it.
- [ ] The vocabulary lives in **one place** and `researcher` reads it, rather than restating it.
      The finding vocabulary drifted across four locations once and produced agents whose output
      the recorder rejected; a standards list is the same shape and a larger surface.
- [ ] **This is necessary and NOT sufficient, and the agent file must say so.** Verified on the
      2026-08-17 T3 review: the security REJECT found a `goal_id` that became a filesystem path an
      agent loads verbatim, a `score` of `1e999` that emitted `+inf` and took the whole index build
      down, and an ignored `awk` exit status. **None was a checklist violation** — all were
      emergent properties of a new input class nobody anticipated. A baseline that reads as
      complete coverage would make the periodic review feel optional, which is the failure this
      change would cause rather than prevent.
- [ ] `security-reviewer`'s invocation rule is **not** loosened as part of this. It becomes cheaper
      because fewer known-class defects survive to review, not because the trigger is relaxed —
      the trigger question belongs to the blocking task.
- [ ] A check that can fail. At minimum: the standards list has exactly one home, and the agent
      file references it rather than duplicating it, asserted the way `kit-finding.sh --vocab` is
      already asserted against the agent files.

## Notes

Filed 2026-08-19 at the operator's request, having confirmed it existed only as §4 of
`docs/design-input/2026-08-18-authoring-chain-and-review-economics.md` and had no task.

**Cannot be validated until the chain runs on real work.** This changes what an agent *authors*, so
its effect is only observable in an ADR produced for a genuine feature — and agent definitions only
take effect under `--plugin-dir`. A plugin deployment test is therefore a practical precondition
for judging it, and one is separately overdue: ADR 0004, option D, `--packs`, the pack withhold and
the new clustering rules have **never run through the plugin**, because `tests/conformance.sh`
invokes the scripts directly and never exercises `skills/task-context` as a session would.

`adr-scribe.md` is in `paths:` because the obligation has to survive into the ADR to reach the
coder; putting it only in the design input leaves it one hand-off short of where it is needed.
