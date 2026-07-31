---
id: T-20260731-adopt-the-kit-into-its-own-repository
title: Adopt the kit into its own repository
epic: validation
tier: T2
state: open
---

## Intent

Run the kit against its own development, so its claims are exercised rather than asserted,
and so HANDOFF stops carrying a hand-maintained backlog that is a second source of truth.

Scoped with git.adopted_at so the nineteen pre-adoption commits are not retroactively
non-compliant.

## Acceptance criteria

- [ ] the commit-msg hook rejects an untrailered commit in this repository
- [ ] CI validates trailers on push and pull request, and skips pre-adoption history
- [ ] HANDOFF §8 points at the backlog instead of listing open work
- [ ] the open work that was in §8 exists as task files with intent and acceptance criteria
- [ ] co-change reads pre-adoption history despite git.adopted_at

## Notes

Found two defects immediately, which is the point:

1. `kit-trailers.sh range` did not respect `git.adopted_at`, so CI failed every commit
   written before the convention existed. A gate that fails on history nobody could have
   complied with is a gate that gets removed.
2. Co-change was bounded by `git.adopted_at` because it rode on the same git log pass as
   the trailer parser. That defeated its entire purpose -- it exists to read history with
   no trailers, and a repository adopting today has all of its structural signal behind
   that boundary. Now a separate pass over full history, bounded only by `cochange.since`.

