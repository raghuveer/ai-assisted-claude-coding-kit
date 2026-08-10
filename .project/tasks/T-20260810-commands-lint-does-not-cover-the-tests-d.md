---
id: T-20260810-commands-lint-does-not-cover-the-tests-d
title: commands.lint does not cover the tests directory it gates
epic: validation
tier: T0
lang: bash
paths: .claude/project-profile.md, templates/project-profile.md
state: open
---

## Intent

`.claude/project-profile.md` declares:

    commands.lint:  bash -n tooling/*.sh tooling/commit-msg templates/*.sh

`tests/*.sh` is not in that list. The verification ladder's lint rung therefore reports success
without having parsed `tests/conformance.sh` — 1,400 lines of the most-edited bash in the repo,
and the file every other control's result comes from.

Observed 2026-08-10 on `T-20260809-conformance-cannot-run-one-step-so-every`, a task whose entire
diff was in `tests/conformance.sh`: the declared lint gate passed without reading a single line
of the change. `bash -n tests/conformance.sh` was run by hand, which is exactly the kind of
by-hand step that stops happening on the day it matters.

This is the shape `docs/LESSONS.md` §1 names — a check that reports success over work it never
examined — with the twist that the check is correct about what it does examine. The defect is in
the declaration, not the checker.

## The change

Add the tests directory to `commands.lint`. Prefer a form that cannot go stale the next time a
directory is added, e.g. driving the list off `git ls-files '*.sh'` rather than naming three
globs, so a fourth directory of shell is covered the day it appears rather than the day someone
notices.

Note the exec-bit gate already took the general form of this lesson: it reads the git index
rather than a hardcoded list. Lint should match.

## Acceptance criteria

- [ ] `commands.lint` covers every `*.sh` tracked in the repo, including `tests/`, and does not
      enumerate directories by hand.
- [ ] Introducing a deliberate syntax error in `tests/conformance.sh` makes the declared lint
      command exit non-zero. Without this the change is untested configuration — the fix and its
      proof are one line each and there is no excuse for skipping the second.
- [ ] The command still exits 0 on a clean tree, on both GNU and BSD userlands.
- [ ] `templates/project-profile.md` carries the same improved form, since every adopting project
      inherits this gap from the template.

## Notes

Filed 2026-08-10 alongside `T-20260810-the-suite-that-gates-every-control-has-n`; both are the
same omission seen from two directions — the test surface is absent from the tier rules and from
the lint command. Fixing one does not fix the other.

T0: one configuration line, mechanical, revertible, stated behaviour. The acceptance criterion
that the lint can actually fail is what keeps it from being a vacuous edit.
