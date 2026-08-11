---
id: T-20260811-team-mode-bootstrap-so-a-second-develope
title: Team mode bootstrap so a second developer gets the kit
epic: portability
tier: T2
lang: bash
paths: tooling/kit-init.sh, INSTALL.md
state: open
---

## Intent

Sharing the kit with a teammate currently means telling them to install it and hoping they
install the same version. Each copy then diverges, and the measurements stop being comparable
across the team — which is most of what the kit is for.

## The change

A repo-level init that marks the kit required or optional **for that repository**, vendors
nothing into it, and does a throttled, failure-safe update check at session start. Failure-safe
matters: a version check that breaks the session when the network is down is worse than no
check.

Reconcile with the existing one-checkout-per-project destination guard. The guard prevents two
projects writing to one destination; team mode lets several people share one project's
configuration. They are not in conflict but they must agree on who owns the destination, and
that agreement should be written down rather than discovered.

## Acceptance criteria

- [ ] A second developer clones the project repo and gets the same agents, commands and
      settings without being told to.
- [ ] Nothing from the kit is vendored into the project repo — verified by a clean `git status`
      after bootstrap.
- [ ] With the network unavailable, the session starts normally and says the check was skipped.
- [ ] A version mismatch between two developers is reported, not silently tolerated.
- [ ] The destination guard and team mode are documented together, including which wins.

## Notes

Filed 2026-08-11 from R-04. Premise verified: `INSTALL.md` exists and covers adoption, but
nothing addresses a *second* person on the same project.

Related to the trial: a trial run by one person proves less than one a team can reproduce.
