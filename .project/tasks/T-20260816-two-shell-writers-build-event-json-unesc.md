---
id: T-20260816-two-shell-writers-build-event-json-unesc
title: Two shell writers build event JSON unescaped so one log line reads differently to each reader
tier: T3
lang: bash
paths: tooling/kit-vindicate.sh, tooling/kit-event.sh, tests/conformance.sh, SECURITY.md
state: open
---

## Intent

`kit_findings.py` exists because `printf`-built JSON interpolated model text unescaped into the
committed event log. That fix covered `finding`, `finding-gap` and `finding-fixed`. **It did not
cover the other event kinds, and two of those writers are still unescaped.**

`tooling/kit-vindicate.sh:29` interpolates `--task` and `--class` straight into a `printf` format
with no escaping of any kind:

```sh
printf '{"task":"%s","kind":"vindication","at":"%s","class":"%s","vindicated":%s}\n' \
  "$task" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$class" "$verdict" \
  >> "$ROOT/$STATE_DIR/events.ndjson"
```

Reproduced 2026-08-16 in a throwaway clone:

```
$ bash tooling/kit-vindicate.sh --task 'T-x' --class 'style","kind":"spend","tok_in":999999,"x":"' --real
$ tail -1 .project/events.ndjson
{"task":"T-x","kind":"vindication","at":"...","class":"style","kind":"spend","tok_in":999999,"x":"","vindicated":1}
```

**The line now carries two `kind` keys, and the two readers of this file disagree about which one
it is.** `kit-index.sh`'s `jf()` matches `"kind"[ ]*:[ ]*"[^"]*"` and takes the FIRST match, so the
indexer recorded `kind=vindication` (`event.seq 620`). Python's `json.loads` takes the LAST, so it
reads `kind=spend` — the same log counts **11 spend events or 12** depending on which reader you
ask. The fabricated `tok_in` did not reach the `spend` table on this path, so the demonstrated
damage is disagreement rather than a corrupted total; that containment is incidental, not designed.

`tooling/kit-event.sh:10-12` is the second writer. It escapes its first two fields, then splices
its **third argument in as raw JSON** with no escaping and no validation:

```sh
"${3:+,\"payload\":$3}"
```

## Reachability — the two writers are NOT equally exposed

**`kit-vindicate.sh` is reachable by a model today. This is not latent.** Three facts compose:

1. **The kit instructs an agent to run it.** `skills/checkpoint/SKILL.md:72` — a skill loaded into
   an agent's session — says "If a review call was later shown wrong, or right, say so:
   `kit-vindicate.sh --task <id> --class <class> --real|--false`."
2. **That instruction carries no propose-don't-run guard.** The skill *does* guard the neighbouring
   command fourteen lines later: "**If you are an agent reading this: list the ids and PROPOSE the
   marks. Do not run `--fixed`**". That guard is scoped to `kit-resolve.sh --fixed` and does not
   mention `kit-vindicate.sh`. So the file that splits agent instructions from operator
   instructions — after the wrong-addressee defect was found in it twice — leaves this one on the
   agent's side of the line.
3. **Nothing validates `--class`.** `kit-vindicate.sh` checks only that `task`, `class` and a
   verdict are non-empty. There is no vocabulary check, no charset check, no length check, and no
   escaping. `kit-finding.sh --vocab` is the authoritative class list and this script never
   consults it.

`SECURITY.md` §1 classifies agent output as **untrusted**. Composed, the above is untrusted model
output reaching the committed append-only log unescaped, down a path the kit points the model at.
**That is the original critical, alive** — not a variant of it, and not waiting on a future caller.

**`kit-event.sh` is genuinely latent** and should be scoped accordingly. Nothing in the repository
passes it a third argument; `tests/conformance.sh:908` passes two. Its raw-JSON splice is a hole
with no path to it today. Fix both, but do not let the latent one set the urgency of the live one,
or the reverse.

**Do not soften this to "an operator types it".** That was the first read of this defect and it was
wrong — it came from grepping `tooling/` for callers, finding none, and stopping before checking
`skills/`. Scripts are not the only thing that invokes a script.

## Acceptance criteria

- [ ] **A test proves the two readers agree, and it goes RED when the escaping is removed.** Inject
      a duplicate-key payload through every shell writer that takes caller-supplied text, then
      assert that `kit-index.sh`'s awk reader and a JSON parser return the *same* `kind` for that
      line. Mutation-proof it: revert the escaping and the test must fail. **This criterion exists
      because the obvious one is vacuous** — "`kit-vindicate.sh` calls `esc()`" is satisfied by
      grepping for `esc`, which is true whether or not the output is correct.
- [ ] **The fix is chosen deliberately and the choice is recorded**, because the two options are
      not equivalent:
      · **(a) add `esc()`** to the unescaped writers. Cheap, local, keeps five JSON writers alive.
      · **(b) route these kinds through `kit_findings.py`** and delete the shell writers. More
        work, and it is what `SECURITY.md` §5 rule 2 actually asks for — that rule now says the
        five writers are "a debt to pay down, never a precedent to cite".
      **Recommendation: (b) for `kit-vindicate.sh`, (a) is acceptable only with a reason written
      down.** Adding a fifth hand-rolled escaper to a codebase whose stated rule is "one JSON
      writer" is how the debt became five in the first place.
- [ ] **`kit-event.sh`'s raw-JSON third argument is closed** — validated, escaped, or removed. It
      currently has zero callers passing it, so removing the parameter is on the table and is the
      cheapest way to make the hole unreachable. If it stays, a test passes hostile text through it.
- [ ] **The two writers that are NOT defective are assessed and explicitly left alone.**
      `kit-spend.sh` escapes every interpolated field through its own `esc()`, in both its shell
      and awk writers; `kit-checkpoint.sh` escapes nothing but interpolates only a timestamp, a
      SHA and a count. Neither is a defect. Say so in the change, so this task does not become an
      unscoped rewrite of all five writers.
- [ ] **`--class` is validated against `kit-finding.sh --vocab`, or the task records why not.**
      Escaping alone makes the injection inert; it still stores a class no vocabulary contains,
      which is a silent data defect in the column the accelerators are derived from. The one
      definition already exists and this script does not ask it.
- [ ] **`SECURITY.md` §4 is updated to match what is then true.** The bullet "No single JSON writer
      for the whole event log" is currently accurate and must not be left describing a fixed
      defect. It returns to §2 **only** with a demonstration attached, per §5 rule 8.
- [ ] **`SECURITY.md` §1 is re-checked against this path.** The trust table says agent output is
      untrusted; this task exists because one agent-reachable writer did not treat it that way.
      Confirm no other script named in a skill takes agent-supplied text without validation — and
      if the sweep finds more, file them rather than folding them in here.

## Notes

Filed out of the sweep in `T-20260815-security-md-claims-allowedtools-enforces`, whose AC3 asked
for the section rather than the instance. That sweep found the `SECURITY.md` claim "the shell
builds no JSON" to be false; this task is the code defect behind the false claim. **The document
was corrected first and separately** — the claim now reads narrowly and this gap is recorded in
§4 — so nothing here is blocked on that, and closing this does not re-open the documentation work.

`.project/events.ndjson` is committed and `merge=union`, so a malformed line **travels to every
clone and cannot be cleanly rewritten** once pushed. That raises the cost of a bad line above the
usual "delete it and rebuild": the derived index can be rebuilt, the log's history cannot.

**Do not fix this by hardening the awk reader.** First-match semantics are what made the indexer
read the injected line as a `vindication`, which looks like the reader defending itself. It is
not a defence — it is one of two readers guessing differently. The writer is the defect.

**Tier is T3, one rung above this path's T2 floor, deliberately.** The floor is computed from
the path; the rung is chosen from what the change touches. This one takes untrusted model text out
of a live agent-reachable path and into a committed, `merge=union`, unrewritable log, and its
central criterion is a mutation-proof test. Recorded T2 first, then raised on finding the skill
path — under-tiering is this project's documented failure mode, not over-tiering.

**A SEPARATE defect was found while establishing reachability, and is NOT in scope here.**
`skills/checkpoint/SKILL.md` guards `kit-resolve.sh --fixed` with an explicit "if you are an agent
reading this, propose and do not run", and leaves `kit-vindicate.sh` fourteen lines earlier
unguarded — although vindication is the same shape of self-certification, and the skill's own
block quote says the wrong-addressee defect had already been made twice by the same hand and
caught by a reviewer. Escaping the writer does not answer whether an agent should be marking its
own review calls right or wrong at all. **Proposed as its own task; do not fold it in.** If it is
never filed, this one still holds — they fail independently.

Related: `T-20260815-an-ingest-adapter-can-insert-a-task-row-` is the same shape one layer out —
a writer reaching the store without passing the validation the store's own comments assume.
