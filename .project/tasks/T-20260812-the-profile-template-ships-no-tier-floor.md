---
id: T-20260812-the-profile-template-ships-no-tier-floor
title: The profile template ships no tier floors so a fresh adoption has none
epic: tiering
tier: T1
paths: templates/project-profile.md, INSTALL.md
state: open
---

## Intent

`templates/project-profile.md` contains **zero active `tier.rule` lines**. Verified on a real
adoption 2026-08-12: after `kit-init.sh` on a 2005-commit Rust repository,
`grep -c '^tier.rule' .claude/project-profile.md` returned **0**.

Every task in a freshly adopted project therefore falls to `tier.default`, and the floor
mechanism — the kit's main defence against under-tiering, which caught a task filed a tier low
**three times in one day** in this repository — is **inert on day one and stays inert until
someone writes rules by hand.**

The kit's own profile has six `tier.rule` lines and they were earned: the indexer, the
commit-msg hook and the trailer checker are floored at T3 because every defect found on
2026-07-31 was in a path that had never run. **None of that reasoning reaches an adopter.**

## Why this is not just "write your own rules"

The brownfield task documents the degradation as *"the tier floors meet paths that already
exist"*. The trial found it is worse: **there are no floors to meet them.** The degradation is
not friction, it is absence — and absence is invisible, because a task assigned `tier.default`
looks assigned rather than unfloored.

`kit-status.sh` reports "below their tier floor", which is silent when no floors exist. So the
one control that would surface the problem is also disabled by it.

## The change

The template must ship rules that are **either real or obviously placeholders**, never absent.
Options, and the choice matters:

- **Commented examples** (the status quo — two commented `tier.rule` lines exist). Demonstrably
  insufficient: they produce zero active floors and nothing says so.
- **A generic starter set** keyed on shape rather than language — anything matching
  `*migration*`, `*auth*`, `*secret*`, plus the project's own build and CI configuration.
  Wrong-ish for every project, and a floor slightly wrong is better than a floor absent.
- **A prompt at adoption**: `kit-init.sh` refuses to finish, or warns loudly, until at least one
  rule exists.

The third is the most in keeping with "absence is a measurement", and combines with the second.

## Acceptance criteria

- [ ] A freshly adopted repository has at least one active `tier.rule`, or `kit-init.sh` says
      plainly that tiering is unfloored and what that means. Silence is not acceptable.
- [ ] `kit-status.sh` distinguishes **"no task is below its floor"** from **"no floors exist"**.
      Today both print nothing, which is the `0 / 0 via:kit` family again.
- [ ] Whatever ships is exercised against a real adoption in a fixture, not asserted — a
      commented-out rule counts as absent and the test must treat it that way.
- [ ] `INSTALL.md` tells an adopter that authoring floors is a step, and why the default is
      dangerous rather than merely conservative.

## Notes

Filed 2026-08-12 from the first execution of the trial protocol
(`docs/TRIALS/2026-08-12-fd-throwaway.md`). Deliberately T1: a template edit plus a warning,
revertible, changing no derived number for existing projects. The *tier of the rules being
added* is a separate question from the tier of adding them.

Interacts with `T-20260810-the-suite-that-gates-every-control-has-n`, which is the same absence
one level in: this repository has no floor for `tests/**` either.
