---
id: T-20260816-kit-guard-fails-open-on-notebookedit-bec
title: kit-guard fails open on NotebookEdit because it reads only file_path
tier: T2
lang: bash
paths: tooling/kit-guard.sh, hooks/hooks.json, tests/conformance.sh, SECURITY.md
state: open
---

## Intent

`hooks/hooks.json:5` fires `kit-guard.sh` on `Write|Edit|NotebookEdit`. The guard extracts the
target path with a single pattern (`tooling/kit-guard.sh:20`):

```sh
grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"'
```

**`NotebookEdit` does not carry `file_path`. It carries `notebook_path`.** So `P` is empty, line 23
(`[ -n "$P" ] || exit 0 # no file_path in payload: nothing to check`) takes the fail-open branch,
and the write proceeds unexamined.

Reproduced 2026-08-16:

```
$ printf '{"tool_name":"Write","tool_input":{"file_path":"C:\\Windows\\Temp\\pwn.txt"}}' \
    | bash tooling/kit-guard.sh ; echo $?
kit: refusing write outside project root: C:\Windows\Temp\pwn.txt
2
$ printf '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"C:\\Windows\\Temp\\pwn.ipynb","new_source":"x"}}' \
    | bash tooling/kit-guard.sh ; echo $?
0
```

`SECURITY.md` §2 names this tool explicitly — "`kit-guard.sh` refuses `Write`, `Edit` and
`NotebookEdit` outside it" — under **What is enforced mechanically**. One third of that sentence
is false, and the guard is the kit's only write boundary.

## The conformance check pins the wrong thing, and that is half the defect

`tests/conformance.sh:2245` asserts:

```sh
grep -q '"matcher": "Write|Edit|NotebookEdit"' "$KIT/hooks/hooks.json"
check $? "the guard still matches only Write|Edit|NotebookEdit, as the protocol states"
```

**That check passes while the guard is broken**, because it tests the matcher *string* rather than
the guard's *behaviour*. It would go green on a guard that refused nothing at all. It is a fifth
instance of the shape `LESSONS` records: a control keyed on evidence that cannot separate pass from
fail. Fixing the extraction without replacing this check leaves the same blind spot for the next
tool the matcher gains.

## Acceptance criteria

- [x] **The guard examines every tool its matcher fires on.** `NotebookEdit` payloads are resolved
      and refused outside the root, exactly as `Write` and `Edit` are. Extract the path by trying
      each key the matched tools can carry, rather than assuming one name.
- [x] **A behavioural test replaces the string check**, table-driven over the matcher's tools: for
      **each** tool, an outside path exits 2 and an inside path exits 0. It must go RED when the
      `notebook_path` handling is removed — prove that by removing it, not by asserting it exists.
      The existing `:2245` string assertion may stay as a *separate* protocol check, but it does
      not count toward this criterion.
- [x] **The matcher and the extractor cannot drift apart silently.** Either derive the key list
      from one place, or add a check that fails when the matcher names a tool the extractor has no
      key for. Today they are two lists in two files agreeing by luck.
- [x] **Whatever else the harness can write with is enumerated and recorded** — at minimum decide
      about `MultiEdit` (if this harness version has it, it is not in the matcher at all) and any
      MCP-provided write tool. Absent ones go in `SECURITY.md` §4 as known-absent rather than being
      silently out of scope.
- [x] **`SECURITY.md` §2 is corrected before or with the fix**, and returns to a mechanical claim
      only with the behavioural test named as its evidence, per §5 rule 8.

## Notes

Found by the security reviewer during the T2 review of
`T-20260815-security-md-claims-allowedtools-enforces`, and reproduced independently before being
accepted. **The `*Demonstrated:*` line that was supposed to prove this claim exercised `Write` and
inferred `NotebookEdit`** — it is written directly above a third case it never ran, under a rule
saying a check that passes on hostile and benign input alike proves nothing.

**Do not treat the fail-open as the bug to remove.** Failing open on an unparseable payload is
deliberate and documented at `kit-guard.sh:3-5` — "a guard that blocks every edit on a malformed
payload is a guard people remove". The defect is that a *well-formed* payload for a matched tool
takes that branch. Keep the fail-open; stop reaching it by accident. If the fail-open path is ever
taken for a tool in the matcher, that is worth a warning on stderr — silence is what let this sit.

`.claude/settings.local.json` may or may not have the hook wired in any given repo; this task is
about the guard being correct where it does run, not about ensuring it runs.
