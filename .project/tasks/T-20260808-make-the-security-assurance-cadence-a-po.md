---
id: T-20260808-make-the-security-assurance-cadence-a-po
title: Make the security assurance cadence a policy the kit can state and check
epic: agent-contracts
tier: T2
paths: agents/security-reviewer.md, templates/project-profile.md, tooling/kit-status.sh
state: open
---

## Intent

`agents/security-reviewer.md` already carries the right position, in prose, in one agent file:

    Dependency CVEs / SBOM / supply chain  -> SCA, per release or major dependency change
    Broad mechanical pattern sweep         -> SAST, per commit
    Runtime / black-box                    -> DAST, preview/nightly/per-major-change
    Creative cross-cutting chains, red-team at scale -> a VAPT engagement

with the instruction to name them in "What I did not check" rather than half-doing them, and
the line that makes it work: *"I reviewed this diff" is never "this is pentested"*.

That is a cadence, and the kit does nothing with it. It is not declared per project, nothing
records when each layer last ran, and nothing reports the gap. A reviewer therefore says
"DAST owns this" into a void — the sentence is honest about what the diff review did not
cover, and completely silent about whether anything else covered it.

The economics are the reason to fix it rather than to leave it as prose: SAST is cheap enough
to run per commit, VAPT is expensive enough that it happens on a cadence, and a kit whose
whole argument is spending tokens deliberately should be able to say which layers a project
has actually bought.

## Acceptance criteria

- [ ] The cadence is declared per project, in the profile, in the same flat `key: value` shape
      as everything else. A layer a project does not run is DECLARED absent, not left blank —
      the same rule `ladder.rung3` / `rung5` already follow, where an unavailable rung is
      declared and RAISES the tier rather than lowering the bar.
- [ ] The vocabulary lives in ONE place and the agent file reads from it rather than restating
      it. The finding vocabulary drifted across four locations once and produced agents whose
      output the recorder rejected; this is the same shape.
- [ ] `kit-status.sh` reports which layers are declared, which have a recorded run, and how
      long ago. A layer that has never run must read differently from one that ran and found
      nothing — that distinction is the whole point.
- [ ] The per-diff reviewer's "What I did not check" can then name the layer AND its state,
      so a reader learns "DAST owns this and DAST last ran never" rather than only the first
      half.
- [ ] No new mechanism if an existing one fits. Recording a layer run is an event; the event
      table already takes arbitrary kinds.

### Added 2026-08-18 — the declaration needs a DERIVATION, not just a slot

A cadence declared with no reasoning behind it is a guess wearing the shape of a policy, and it
will be copied between projects unchanged — which is the failure mode the profile template has
already produced once for tier floors.

- [ ] The declaration records **what it was derived from**, and the inputs are the operator's:
      **target tech stack · maturity of that ecosystem · third-party dependencies and solutions
      being considered**. A project whose scope cannot be traced to those has not scoped, it has
      copied.
- [ ] **The three project types scope differently, and the difference is not cosmetic:**
      *greenfield* chooses its stack, so the security surface is an **input to that choice** and a
      mature ecosystem is a way to buy a smaller one; *brownfield* inherits the surface, so scoping
      is **discovery** rather than choice; *modernization* is the decision itself, per component.
      A single scoping procedure that ignores which of the three it is will be wrong for two.
- [ ] **In modernization, the security scope is a function of the component disposition** — see
      `T-20260731-component-model-for-polyglot-and-moderni`. *Reuse* inherits that component's
      dependency surface and its CVE history; *re-architect* chooses a new one; *improve* is
      partial. These are the same decision viewed twice, and recording them twice without linking
      them is how they drift apart.
- [ ] **A third-party solution moves the boundary, it does not remove it.** Adopting a managed
      identity provider takes authn off the diff and adds a trust boundary plus a dependency on
      somebody else's assurance. The scope must record what moved **out** and what came **in**;
      `SECURITY.md` §1 is where the incoming half belongs.
- [ ] **Ecosystem maturity is recorded as a two-sided input, not a score.** A mature ecosystem has
      more *known* CVEs and better-hardened defaults; a young one has fewer known CVEs, more
      unknown ones, and fewer safe defaults. **A low SCA finding count in a young ecosystem is
      silence, not safety**, and a scope that treats maturity as a single number will read that
      silence as a pass.
- [ ] The scope decision is **ADR-shaped and goes through the chain** — it has options and
      consequences, so `researcher` produces it and `approach-reviewer` reads it, per
      `docs/design-input/2026-08-18-authoring-chain-and-review-economics.md`. It is not a profile
      value somebody types once.
- [ ] **The scope selects which checklist `researcher` loads.** ASVS is levelled and the LLM Top 10
      applies only where there is an LLM surface, so "include OWASP" without a scope is a firehose
      that teaches an agent to skim. This is what makes the baseline-in-researcher proposal
      actionable rather than aspirational.
- [ ] Scope stays: the kit **declares and checks** the scope. It does not perform SCA, SAST, DAST
      or VAPT, and must not grow toward doing so — the Notes below already draw that line.

## Notes

Confirmed with the operator 2026-08-08, whose stated position matches the agent file almost
exactly: VAPT, SBOM and DAST on a periodic basis, SAST possibly per commit, judged on cost
against outcome quality.

The kit is a per-diff semantic gate and must not grow into a security programme. The point of
this task is the opposite — to let the kit state precisely how little it covers, so the
layers it does not own are visible rather than assumed.
