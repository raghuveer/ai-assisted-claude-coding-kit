---
id: T-20260809-a-task-id-containing-a-regex-metacharact
title: A Task-Id containing a regex metacharacter passes the unknown-task gate
epic: validation
tier: T3
lang: bash
paths: tooling/kit-trailers.sh
state: open
---

## Intent

`task_known()` interpolates the id straight into a regex:

    grep -rlq -E "^id:[[:space:]]*$1[[:space:]]*$" "$ROOT/$TASKS_DIR"

so an id carrying a regex metacharacter is matched as a PATTERN rather than compared as a
string, and the gate reports it as a real task. Measured against a repository whose only task
file is `T-real`:

    Task-Id: T-real     silent -- accepted, correct
    Task-Id: T-nope     unknown  Task-Id: T-nope — matches no task, correct
    Task-Id: .*         silent -- accepted, WRONG
    Task-Id: T-re.l     silent -- accepted, WRONG

`T-re.l` is the case that makes this worth a task rather than a note. It is not hostile input:
it is an ordinary typo, one character wrong, of exactly the kind this gate exists to catch. The
control line proves the check works for a plainly wrong id, so this is not the gate being broken
in general — it is fail-open on precisely the inputs it is aimed at.

This is the gate that stops a typo'd `Task-Id` reaching pushed history, where it becomes
permanent and only `T-20260808-a-task-id-matching-no-task-file-is-count` can help. A dot in the
wrong place walks straight past it.

## Why T3

`tier.rule` floors `tooling/kit-trailers.sh` at T3. The floor is right here for its own reason:
this is a gate, the failure is fail-open, and a gate that passes what it exists to stop is worth
more than the sum of what it lets through.

## Acceptance criteria

- [ ] An id is compared as a STRING, not matched as a pattern. `grep -F` on the whole line, or
      a read-and-compare, rather than an interpolated `-E` pattern.
- [ ] The comparison stays anchored: `T-real` must not be reported known by a file declaring
      `id: T-real-2`, which a naive move to `-F` would allow. Both directions need a case.
- [ ] A conformance case covers the metacharacter id. Nothing exercises this path today, which
      is why a defect this simple survived — `T-re.l` and `.*` must both be reported unknown,
      and `T-real` must still be silent, or the fix has only moved the failure.
- [ ] Check the same shape elsewhere before closing: any other place the kit interpolates a
      task id, a path or a tier into a pattern rather than comparing it. `kit-trailers.sh` is
      where it was found, not necessarily where it ends.

## Notes

Found by the security reviewer during the T3 review of
`T-20260808-a-task-id-matching-no-task-file-is-count`, listed there as an out-of-scope
observation, and reproduced before filing. Pre-existing: it is not caused by that change and is
not fixed by it.
