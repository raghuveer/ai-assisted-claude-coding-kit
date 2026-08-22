---
id: T-20260822-a-truncated-slug-makes-two-different-tit
title: A truncated slug makes two different titles share one task id
epic: planning
tier: T2
lang: bash
paths: tooling/kit-task.sh
state: created
---

## Intent

`kit-task.sh:37` builds the id as `T-<UTC date>-<title slug, cut to 40 chars>`. Two different
titles whose first 40 slug characters agree, filed on the same UTC day, get the **same id**.

**Reproduced 2026-08-22**, not argued:

    "Legacy state spellings in task files should drain to canonical"
    "Legacy state spellings in task files should be removed entirely"
      -> both: T-20260822-legacy-state-spellings-in-task-files-sho

The comment above that line claims more than the scheme delivers:

    # Date-plus-slug: no central counter, so two branches never collide on an id

The *no central counter* half is true and is the good property — nothing has to be allocated,
so branches can create tasks independently. **"Never collide" does not follow from it**, and
truncation to 40 characters makes the collision likelier than a full slug would.

## What actually happens on a collision, which is the part that decides the tier

- **Same worktree:** `[ -e "$f" ]` refuses and exits 1. Correct, and loud.
- **Two branches:** both create the same *path*. Git raises an add/add conflict on merge, so it
  is noisy rather than silent — but it surfaces at merge time, after both tasks have accumulated
  commits carrying that `Task-Id`, and those trailers are now ambiguous between two tasks with
  no way to tell which meant which.

So this is not corruption, and it is not urgent. It is a papercut with a bad tail.

## Why NOT to switch to UUIDv7, recorded so it is not re-proposed

Raised and considered on 2026-08-22. **The id is not only a key.** It is the filename, and it is
the value a human or an agent types into a `Task-Id:` git trailer by hand. Two properties depend
on it being readable:

- **A typo is visible to the eye.** `T-20260822-legacy-state-spellings-in-task-files-sho` reads
  as what it is; `01920a1b-7c3d-7e8f-...` does not. This repository has whole machinery for a
  `Task-Id` matching no task file, and its diagnostics are far more useful when the id is legible.
- **`git log` is where the id is actually read**, which is the reason the current scheme gives.

A time-ordered opaque id would remove collisions and cost both. Not worth it.

## Acceptance criteria

- [ ] Two different titles sharing a 40-character slug prefix cannot produce the same id on the
      same day. Whatever the mechanism, the id stays **legible** — that constraint is the point,
      and a solution that reaches for an opaque id fails this criterion rather than meeting it.
- [ ] The comment at `kit-task.sh:33` states what the scheme actually guarantees. It currently
      claims branches never collide, which is false and is the reason nobody looked.
- [ ] A check that can fail: two `kit-task.sh` invocations with titles agreeing to 40 slug
      characters, asserting two distinct ids exist afterwards. That test fails on today's code.
- [ ] Existing ids are NOT rewritten. They appear in commit trailers in immutable history, which
      is the same constraint that made ADR 0008 alias rather than migrate.

## Notes

Filed 2026-08-22 after the operator asked whether ids were UUIDs or integers. They are neither,
and the question surfaced both the collision and the overstated comment.

**Not a blocker for `T-20260808-trial-the-kit-on-one-unfamiliar-brownfie`** and deliberately not
added to its `blocked_by`. A trial files few enough tasks that a same-day 40-character prefix
collision is not a realistic risk there.
