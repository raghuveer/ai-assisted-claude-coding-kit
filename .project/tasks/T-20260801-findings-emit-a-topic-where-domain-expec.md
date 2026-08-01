---
id: T-20260801-findings-emit-a-topic-where-domain-expec
title: Findings emit a topic where domain expects an industry
epic: agent-contracts
tier: T2
lang: typescript
state: open
---

## Intent

The agents are told to emit `class|severity|lang|domain` and are given the vocabulary for
`class` and `severity`. Nothing says what `domain` is, so both models tested filled it
with the subject they were reviewing: `caching` pre-inlining, `cache-adapter-design`
post-inlining.

`domain` seeds the INDUSTRY accelerator. `kit-accel.sh propose` groups by it:

    SELECT 'industry', domain, class, COUNT(*) ... WHERE domain IS NOT NULL AND domain <> ''

so a topic in that field becomes a fake industry with earned-looking evidence behind it.

This is worse than the class problem in one specific way. An unknown class is rejected
loudly and the finding is lost, which is visible. A wrong domain is accepted SILENTLY and
pollutes the accelerator it feeds, which is not.

## Acceptance criteria

- [ ] the agents state what domain means and that it is optional
- [ ] a domain outside the project's declared industry is rejected or blanked, not stored
- [ ] the industry accelerator cannot be seeded by a value no project ever declared
- [ ] whatever list is used lives in one place, checked by tests/conformance.sh like the class list

## Notes

Found by re-testing defect 3 (vocabulary unreachable below opus). That retest confirmed
inlining fixes class compliance -- sonnet went from 2 recorded / 6 rejected to 7 recorded /
0 rejected on identical input -- and the domain problem was only visible BECAUSE the rows
started being accepted. The previous failure mode was masking it.

Likely the right shape: domain is not free text. It should come from the project profile
(accelerator.industry, or a new key) and be validated against it, since a project knows its
industry and a reviewer does not.
