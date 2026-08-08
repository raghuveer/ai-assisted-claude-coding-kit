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

## Notes

Confirmed with the operator 2026-08-08, whose stated position matches the agent file almost
exactly: VAPT, SBOM and DAST on a periodic basis, SAST possibly per commit, judged on cost
against outcome quality.

The kit is a per-diff semantic gate and must not grow into a security programme. The point of
this task is the opposite — to let the kit state precisely how little it covers, so the
layers it does not own are visible rather than assumed.
