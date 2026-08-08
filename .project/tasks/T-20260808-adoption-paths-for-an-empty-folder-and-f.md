---
id: T-20260808-adoption-paths-for-an-empty-folder-and-f
title: Adoption paths for an empty folder and for an existing codebase
epic: portability
tier: T1
paths: INSTALL.md, README.md
state: open
---

## Intent

`INSTALL.md` has two adoption sections and neither is the case an adopter usually has.

**§B "Starting a NEW project"** opens `cd your-repo` and runs `kit-init.sh`, which calls
`git rev-parse --show-toplevel` and exits if there is no repository. It is not a path from an
empty folder; it is a path from a repository that already exists.

**§C "JOINING an existing project"** means a repository that has ALREADY adopted the kit —
the profile, backlog and event log arrive with the clone. It is not a path for an existing
codebase that has never seen the kit.

So the two cases actually being asked for are both missing: an empty directory with no git and
no code, and a legacy codebase with history that is adopting for the first time.

## Acceptance criteria

- [ ] Three named cases, not two: empty folder, existing codebase adopting, and clone of an
      already-adopted repository. Say which one a reader is in before telling them what to run.
- [ ] The empty-folder path starts before `git init` and is honest about what is inert until
      there is code: `commands.*` name tools that do not exist yet, `tier.rule` globs match
      nothing, co-change has no history, and the planner's ordering is at its measured worst —
      22 tasks collapsed to 2 layers with the scaffold everything depends on ranked eleventh
      (T-20260801-kit-plan-has-no-notion-of-prerequisite-w). Say so and give the workaround
      rather than letting the adopter discover it.
- [ ] The existing-codebase path states the brownfield degradations WHERE SOMEONE ADOPTING
      WILL READ THEM. They are currently only in `kit-index.sh` comments:
      - `touches` edges need a `Task-Id` trailer, so a freshly adopted repo has an empty edge
        table, blast radius is unknown for everything, and unknown floors at T2 — the whole
        backlog over-tiers until history accumulates.
      - co-change exists to fill exactly that gap and needs no trailers, but it needs history,
        and it withholds itself entirely if the graph comes out too dense.
- [ ] It covers choosing `git.adopted_at`. That single value decides what the kit believes
      about history, it is the brownfield-specific decision, and nothing currently discusses it.
- [ ] It covers what to do with a backlog that already exists — a roadmap document, an issue
      tracker, a tree of analysis and task-description files. `ingest.tasks` adapters are the
      built-for-this answer (`docs/ADAPTERS.md`) and the adoption path never mentions them.
- [ ] It covers back-filling status for work already finished before adoption, including work
      not done with the kit. See T-20260808-record-how-a-task-was-executed-so-kit-wo — an
      inventory that cannot say "done, but not by this pipeline" reports a false escape rate.
- [ ] Nothing in it is aspirational. Every claim is either something the kit does today or is
      labelled as a known limit with the task that owns it.

## Notes

The three-cases framing came from the operator on 2026-08-08, describing how the kit would
actually be rolled out: an empty folder for greenfield, and an existing codebase for
application modernization.

Deliberately T1 and documentation-only. It changes no behaviour — but it is what stands
between the kit and being tried on a real codebase, and the trial task depends on it.
