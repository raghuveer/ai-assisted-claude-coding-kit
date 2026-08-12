---
id: T-20260812-kit-init-leaves-a-footprint-in-an-adopte
title: kit-init leaves a footprint in an adopted repo with no way to remove it
epic: components
tier: T2
lang: bash
paths: tooling/kit-init.sh, docs/TRIAL-PROTOCOL.md
state: open
---

## Intent

`kit-init.sh` writes into the repository it adopts and there is **no command to undo it**.
Measured 2026-08-12 immediately after adopting a clean subject:

    M .gitignore
    ?? .claude/
    ?? .gitattributes

plus `commit-msg` and `pre-push` hooks in `.git/hooks/`, which `git status` does not show at all.

For a project that chose to adopt the kit, that footprint is the point. For **a trial**, it is
contamination: `docs/TRIAL-PROTOCOL.md` §4 requires that anything produced for the subject is
"a proposal, delivered as files for review, never applied" — and a trialist following the
protocol to the letter still hands back a working copy with modified `.gitignore`, two installed
hooks and two new files, with no step telling them to strip it and no command that would.

## Why this is not only a trial concern

- **Evaluation.** Someone trying the kit on a branch to see whether they like it has no clean
  way back, which makes trying it a bigger decision than it should be. That is adoption
  friction in the place adoption friction hurts most.
- **The hooks are invisible.** `.git/hooks/` is not tracked, so `git status` reports a clean
  tree while `commit-msg` still rejects commits. Someone who deletes `.claude/` believing they
  have removed the kit gets a repository that now fails commits for a missing profile.
- The recommendations register asked for `uninstall --dry-run` as part of a selective installer
  (`T-20260811-selective-installer-with-per-project-com`). This is the same need, arriving from
  a different direction and confirmed in the field.

## The change

`kit-init.sh --uninstall`, or a sibling script, that:

- restores `.gitignore` to its pre-adoption state rather than deleting the file — the kit
  appends, so removal must be surgical and must not touch lines it did not add;
- removes `.claude/project-profile.md` and the generated hooks, **naming each thing it removes**;
- **refuses to delete anything it cannot prove it created** — a task file, an edited profile, a
  `.gitattributes` the project already had. Deleting a project's own work to clean up after a
  trial would be the worst possible outcome of a tool whose constraint is "do not destabilise
  the subject".

A `--dry-run` that lists the removals is the safer default, and probably the only mode a trial
should ever use.

## Acceptance criteria

- [ ] Adopt a fixture, uninstall, and `git status --short` is **empty** — byte-identical to
      before adoption, including `.gitignore`.
- [ ] The generated hooks are gone, verified by attempting a commit that `commit-msg` would have
      rejected and watching it succeed.
- [ ] A pre-existing `.gitattributes` or `.gitignore` line is **not** removed. Proved by a
      fixture that has both before adoption.
- [ ] A hand-edited profile or any task file is refused, not deleted, with a message naming what
      was kept and why.
- [ ] `--dry-run` lists exactly what the real run would remove and removes nothing.
- [ ] `docs/TRIAL-PROTOCOL.md` §4 and §7 tell a trialist to run it, and §7's "delete the copy"
      step says what to do when the copy is being kept.

## Notes

Filed 2026-08-12 from the first execution of the trial protocol
(`docs/TRIALS/2026-08-12-fd-throwaway.md`, finding T-4), and independently raised as a minor by
the protocol re-review. In the trial itself this cost nothing, because the whole copy was
deleted — which is exactly why it is easy to miss on a subject someone wants to keep.
