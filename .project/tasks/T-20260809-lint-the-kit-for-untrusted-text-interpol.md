---
id: T-20260809-lint-the-kit-for-untrusted-text-interpol
title: Lint the kit for untrusted text interpolated into a pattern
epic: validation
tier: T1
lang: bash
paths: tests/conformance.sh
state: open
---

## Intent

This kit has shipped the same defect shape **three times in one day** (2026-08-09), the third and
fourth instances written hours after the first was filed:

1. `kit-trailers.sh` `task_known()` — a task id interpolated into `grep -E`, so `T-re.l` matched
   `T-real` and the gate reported a typo'd id as a known task.
   Filed as `T-20260809-a-task-id-containing-a-regex-metacharact`.
2. `kit-review-findings.sh:81-82` — `agent_id` from a hook payload interpolated into a `grep`
   pattern. Reproduced: agent `A.9` suppressed agent `AB9`'s findings entirely, with no warning
   and no gap event.
3. `kit-review-findings.sh:75` — the same field interpolated into `find -name`. Reproduced: an
   `agent_id` of `*` harvested a DIFFERENT agent's transcript and filed its findings under `*`.

The filed task carries an acceptance criterion reading "check the same shape elsewhere before
closing". Filing a class is not sweeping for it, and a human sweeping by memory is how instances
2 and 3 were written while instance 1 sat open.

## The check

A conformance step that fails when a variable is interpolated into a pattern context. The kit
already lints itself in exactly this style — agent `tools:` entries resolve to real tools, the
finding vocabulary has not drifted, every script is 100755 in the index — so this sits beside
controls that already exist rather than introducing a new idea.

Shapes to catch, at minimum:

    grep ... "...$VAR..."        pattern built from a variable
    grep -E/-e ... "$VAR"
    find ... -name "...$VAR..."
    case "$x" in $VAR)           unquoted variable as a glob pattern

Legitimate uses exist — `grep -F -- "$VAR"` is a fixed-string comparison and is fine, as is a
pattern assembled entirely from kit-controlled literals. The check must distinguish those or it
will be turned off, which is worse than not having it.

## Acceptance criteria

- [ ] The check fails on all three known instances when they are reintroduced, and passes on the
      fixed forms. Prove it by reverting each fix in turn, not by reading the regex.
- [ ] `grep -F --` and other genuinely fixed-string comparisons do not trip it. A lint with false
      positives gets an exemption comment, and then the exemption spreads.
- [ ] Any exemption mechanism names the reason inline, so a reader can judge it. An unexplained
      suppression is the defect wearing a comment.
- [ ] The check itself cannot silently pass. Assert it fires on a deliberately planted instance —
      the failure mode of 2026-08-09 was controls that could not fail, including a `grep` whose
      pattern began with `-` and which therefore exited 2 without reading its file.

## Notes

Deliberately T1 and deterministic. This is the machine half of the pair filed with it:
`T-20260809-a-claim-audit-before-a-task-closes-names` is the judgement half. The split follows
the rule the retrospective settled on — models for judgement, deterministic code for data — and
this shape is mechanical, so a model should never be asked to find it twice.

See `docs/LESSONS.md` §4 and §7.
