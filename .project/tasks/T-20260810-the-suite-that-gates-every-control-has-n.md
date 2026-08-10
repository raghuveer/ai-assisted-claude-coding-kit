---
id: T-20260810-the-suite-that-gates-every-control-has-n
title: The suite that gates every control has no tier floor
epic: validation
tier: T1
lang: bash
paths: .claude/project-profile.md, templates/project-profile.md
state: open
---

## Intent

`tier.rule:` in `.claude/project-profile.md` floors `tooling/kit-index.sh`, `tooling/commit-msg`
and `tooling/kit-trailers.sh` at T3, and `tooling/**`, `.claude-plugin/**` and `hooks/**` at T2.
**Nothing covers `tests/**`.**

So a change to `tests/conformance.sh` — the suite that decides whether every other control in
this kit works — falls through to `tier.default: T1`, and the kit computes `tier_floor` as NULL.
Observed on 2026-08-10 while closing
`T-20260809-conformance-cannot-run-one-step-so-every`: the recorded T1 was reported with
`(no floor)`, meaning the kit had no opinion rather than agreeing.

That is the wrong shape for this file specifically. A defect here does not produce a wrong
answer; it produces a **green one**, across every check at once, and the escape it hides could
be in any tier. The profile's own comment for the T3 rules says the indexer and validator are
"where a silent wrong answer is most expensive" — the suite that grades them is at least as
expensive, and it is the one path in the repo with no rule.

This matters more now that `--only` exists. A filtered run is a supported development mode, so a
defect in the filter can make a mutation proof pass for the wrong reason — the exact failure
mode `docs/LESSONS.md` §1 and §2 are about — and that filter is reachable only from this file.

## The change

Add a floor for the test surface. The tier is the open question and is the reason this is filed
rather than fixed:

- **T2** treats it like `tooling/**`: gates, tests, wiring proof, one adversarial reviewer.
- **T3** treats it like the indexer: adds a blind second reviewer.

T2 is the likelier answer. The argument for T3 is that this file grades the T3 files; the
argument against is that it is not irreversible and not security relevant, and flooring it at T3
would put a two-reviewer round on every fixture tweak, which is how a floor stops being obeyed.

Whichever is chosen, `templates/project-profile.md` should carry the same rule commented, since
adopting projects have the same asymmetry between their code and the tests that grade it.

## Acceptance criteria

- [ ] `tests/**` has a `tier.rule:` floor in `.claude/project-profile.md`, and the chosen tier is
      justified in the profile comment rather than only in this task.
- [ ] `kit-index.sh` reports a non-NULL `tier_floor` for a task whose `paths:` names a file under
      `tests/`. Verified by query, not by reading the profile — the two floor sources have
      disagreed before (see the non-ASCII path step in the conformance suite).
- [ ] A task filed below that floor is reported as below it, proving the rule can fire rather
      than merely existing.
- [ ] `templates/project-profile.md` carries the equivalent rule for adopting projects.

## Notes

Filed 2026-08-10, found while closing the conformance filter task. Not found by a control —
found by reading the closing query output and noticing the floor column said `(no floor)`, which
is itself worth recording: the absence of a floor is invisible unless someone looks for it.

Deliberately T1: it edits configuration, changes no code path, and is revertible in one line.
The tier of the RULE being added is a separate question from the tier of adding it.
