---
id: T-20260808-a-freshly-adopted-repo-defaults-to-warn-
title: A freshly adopted repo defaults to warn so a stranded trailer commits anyway
epic: portability
tier: T1
lang: bash
paths: templates/project-profile.md, INSTALL.md
state: open
---

## Intent

`templates/project-profile.md` ships `git.trailer_enforcement: warn`. This kit's own repo
runs `enforce`. So the protection the kit applies to itself is not the protection it hands an
adopter, and nothing in the adoption path says to change it.

Measured during the first real harness run (2026-08-08), on a repo adopted minutes earlier
with `kit-init.sh` and nothing else touched:

    git commit -m "fix: ...            <- Task-Id/Tier/Task-Status, then a Signed-off-by
                                          paragraph after them"
    kit: commit trailers
      stranded  Task-Id:  present, but not in the final paragraph — git will not index it
      stranded  Tier:  ...
      stranded  Task-Status:  ...
    exit 0 — AND THE COMMIT LANDED

Setting `enforce` and repeating it rejected the same message and accepted the well-formed
one, so the hook is correct. The default is what lets the bad shape through.

## Why this shape and not another

A stranded trailer is the one failure the kit describes as permanent. `git` reads trailers
only from the last paragraph, so the commit indexes as untagged; and once pushed, a commit
message can only be changed by rewriting shared history. `INSTALL.md` already says this
repository "carries a permanent phantom task from exactly that gap", and `pre-push` exists
because it is the last point at which the message can still be amended.

Which means the default is inverted with respect to cost. `warn` is the gentle option for a
mistake that cannot be undone, and `enforce` is the gentle option for one that can — you fix
the message and commit again, five seconds later, while you are still writing it.

## Acceptance criteria

- [ ] Decide the shipped default deliberately and record the reasoning either way. If it stays
      `warn`, the adoption path must tell an adopter to consider `enforce` and say what it
      costs them not to.
- [ ] Whatever is chosen, `INSTALL.md` states it where someone adopting will read it, next to
      the existing explanation of why the stranded shape is unrecoverable.
- [ ] A conformance case covers the DEFAULT posture, not only the configured one. The suite
      today sets `enforce` in its fixture before testing rejection, so the shipped default has
      never been exercised by a test.

## Notes

Found by running the kit through the harness for the first time, on a fresh adoption, exactly
as an adopter would — T-20260731-run-one-real-task-with-the-model-in-the-. It is not a defect
in the hook, which behaved correctly under both settings; it is a defect in what a new project
gets by default.

Related: T-20260808-adoption-paths-for-an-empty-folder-and-f, which owns the adoption text this
would land in.
