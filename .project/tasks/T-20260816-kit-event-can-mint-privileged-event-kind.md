---
id: T-20260816-kit-event-can-mint-privileged-event-kind
title: kit-event can mint privileged event kinds that bypass every validator
tier: T3
lang: bash
paths: tooling/kit-event.sh, tooling/kit-index.sh, tests/conformance.sh, SECURITY.md
state: open
---

## Intent

`kit-event.sh <task-id> <kind> [json-payload]` takes the **kind** as a free argument and splices
the **payload** in as raw JSON (`tooling/kit-event.sh:10-12`). It is documented as a generic
note-writer. It is in fact a skeleton key: any event kind the indexer honours can be minted through
it, skipping `kit_findings.py` — the validation, the sanitiser, the closed vocabulary, and the
operator-only convention on fix-marks.

Reproduced 2026-08-16 in a throwaway clone. **A fix-mark, forged by a `printf` writer:**

```
$ TARGET=$(sqlite3 .project/index.db "select id from finding where fixed_at is null limit 1;")
$ # BEFORE: fixed_at NULL | fixed_note NULL
$ bash tooling/kit-event.sh T-fake finding-fixed \
    "{\"finding\":\"$TARGET\",\"fixed\":1,\"note\":\"marked by printf, not kit_findings.py\"}"
$ bash tooling/kit-index.sh
$ # AFTER : 2026-08-16T06:30:27Z | marked by printf, not kit_findings.py
```

`kit-index.sh` matches `k=="finding-fixed"` and reads the `finding` key out of the spliced payload.
`kit_findings.py` never ran.

**Why this one matters more than an escaping bug.** A fix-mark is the artefact `.claude/CLAUDE.md`
reserves to the operator — *"An agent proposes the mark and does not record it — clearing the gate
that gates your own work is the one certification the author cannot give."* That convention is
enforced by asking `kit-resolve.sh` nicely. `kit-event.sh` does not ask. The same route mints
`finding` rows carrying a `class` and `severity` outside `kit-finding.sh --vocab`, which is the one
vocabulary the accelerators are derived from.

## Acceptance criteria

- [x] **A privileged kind cannot be minted through the generic writer.** `finding`, `finding-gap`
      and `finding-fixed` — and any future kind the indexer acts on rather than merely records —
      are refused by `kit-event.sh`, or the indexer ignores them unless they carry proof they came
      through `kit_findings.py`. Decide which, and say why in the change.
- [x] **The decision names the boundary rather than blacklisting today's kinds.** A hardcoded list
      of three strings is a list that goes stale the next time a kind is added. Prefer a rule the
      indexer can state — e.g. kinds that mutate a row are a closed set the generic writer cannot
      address — over an enumeration in a second file.
- [x] **A test forges each privileged kind through `kit-event.sh` and asserts the index is
      unchanged**, and goes RED when the refusal is removed. Assert on the *database state*, not on
      the script's exit code: a refusal that exits 2 while still appending is the failure mode.
- [x] **`SECURITY.md` §2's JSON-writer claim is corrected to whatever survives.** As written —
      "Every `finding`, `finding-gap` and `finding-fixed` line is serialised by `kit_findings.py`" —
      it is false, and it is the claim that *replaced* the last false claim in that slot.
- [x] **The operator-only convention on fix-marks is stated where it can be relied on, or admitted
      as unenforced.** `.claude/CLAUDE.md` and `skills/checkpoint/SKILL.md` both present it as a
      rule; today any writer can bypass it. Convention is an acceptable answer — an undocumented
      bypass is not.

## OVERLAP — read before filing, this may belong to an existing task

`T-20260816-two-shell-writers-build-event-json-unesc` already covers `kit-event.sh`, and its AC3
says the raw-JSON third argument must be "validated, escaped, or removed". **Removing that argument
would close most of this task as a side effect.**

They are not the same defect. That task is about *escaping* — untrusted text producing a line whose
two readers disagree. This one is about *privilege* — the generic writer being able to address
event kinds that mutate state, which escaping does not touch. A perfectly escaped forged fix-mark
is still a forged fix-mark.

**Recommendation: file this separately, and if the other task is picked up first, close this one by
reference rather than re-doing it.** The alternative — folding this into that task as a sixth
criterion — is defensible and cheaper, and the operator may prefer it. What must not happen is the
privilege dimension disappearing into "we escaped it", which is the likelier outcome if it is a
bullet inside someone else's task.

## Notes

Found by the implementation reviewer during the T2 review of
`T-20260815-security-md-claims-allowedtools-enforces`, and reproduced independently before being
accepted.

**How the sweep missed it, recorded because the method is the lesson.** The check asked *which
scripts emit these kinds by literal name* — `grep -rn 'finding-fixed|"kind":"finding' tooling/*.sh`
returns only reads and log messages, so the claim read as true. The right question was *which paths
can produce these kinds*, and `kit-event.sh` produces any of them because the kind is an argument.
A grep for a literal cannot find a value that arrives as a parameter.

`.project/events.ndjson` is committed and `merge=union`, so a forged line travels to every clone
and cannot be cleanly rewritten once pushed.
