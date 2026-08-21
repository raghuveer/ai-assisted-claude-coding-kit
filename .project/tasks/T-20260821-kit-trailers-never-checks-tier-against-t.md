---
id: T-20260821-kit-trailers-never-checks-tier-against-t
title: kit-trailers never checks Tier against the floor for the paths a commit touches
epic: measurement
tier: T3
lang: bash
paths: tooling/kit-trailers.sh, tooling/commit-msg, tooling/kit-index.sh
state: open
---

## Intent

`tier.rule` declares floors — `tooling/kit-index.sh T3`, `tooling/** T2` — and the profile says
**floors, never ceilings.** `kit-trailers.sh` validates the `Tier:` trailer against the *vocabulary*
`T0|T1|T2|T3` and **never against `tier.rule` at all**. `tooling/commit-msg` carries no tier logic.

So with `git.trailer_enforcement: enforce` set and the hook installed, **the floor is advisory at
the only moment it could bind.**

Demonstrated by this repository on itself: `051fc31` modified `tooling/kit-index.sh`, whose floor is
**T3**, and shipped under `Tier: T2`. Trailer validation passed, CI passed on both platforms, and
the change reached `main`. The under-tiering was noticed only because the operator asked for a
review chain afterwards and the chain had to be re-scoped from T2 to T3 — a human catch, not a
mechanical one. A gate-clearing mechanism is exactly the change that should not slip a tier.

## What already works, and why it is not enough

`kit-index.sh:1293` raises `task.tier_floor` from **`touches` edges**, which come from commit
trailers — so the floor is NOT derived only from a task's declared `paths:`, and `kit-status.sh`
reports tasks below floor by that route today. **An earlier note on
`T-20260819-a-finding-whose-subject-no-longer-exists` claimed otherwise and was wrong**; an
approach review refuted it and the note is corrected.

The real gap is timing. A `touches` edge exists only **after** the commit is made and the index
rebuilt, so the report is **late, not blind**: it tells you a landed commit was under-tiered. The
one place the information could change the outcome — before the commit is written — has no check.

## Acceptance criteria

- [ ] `kit-trailers.sh` computes the floor for the paths the commit **actually touches** and
      compares it to the `Tier:` trailer. `git diff-tree --name-only` plus the same `tier.rule`
      glob matching `kit-index.sh` already performs.
- [ ] **One home for the predicate.** The glob-matching rule exists in `kit-index.sh`; a second
      copy in `kit-trailers.sh` is the drift this project has already paid for twice. Either
      extract it to `kit-lib.sh` or have one call the other, and assert in conformance that no
      second copy exists — the discipline `kit_via_vocab` and the finding vocabulary already use.
- [ ] Decide `warn` versus `enforce` deliberately, and honour `git.trailer_enforcement`. A commit
      below its floor is not malformed; it is under-reviewed. Blocking it at `commit-msg` may be
      right, but it is a policy choice and must be one.
- [ ] It works in the **pre-push** path too, or says why not. `pre-push` is the last point where a
      trailer can still be amended cheaply.
- [ ] A check that can fail: a fixture commit touching a `T3`-floored path with `Tier: T2` must be
      refused, and the same commit with `Tier: T3` accepted. Both directions, or the check would
      pass against a validator that refused everything.

## Notes

Found 2026-08-21 by the `security-reviewer` in the T3 chain on `051fc31`, filed at **major**
severity under `compliance`. Its wording: *"a gate-clearing mechanism reached `main` under a T2
trailer and this security review is running after the fact; nothing present prevents the next
one."*

Tiered **T3** itself, on its own rule: it changes `tooling/kit-trailers.sh`, whose floor is T3.
