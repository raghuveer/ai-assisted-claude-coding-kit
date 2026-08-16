# CLAUDE.md

<!-- Append to the target repo's CLAUDE.md. Keep it this short: every line here is
     paid on every request of every session. If deleting a line does not change
     behaviour, leave it deleted. -->

## Working agreement

- Declare a tier (T0-T3) before spawning any reviewer. Untiered work is either
  overspend or a missing control, and afterwards you cannot tell which.
- Truth lives in task files and git trailers. `STATUS.generated.md` and
  `.project/index.db` are derived — never edit them, and never treat them as input
  that outranks the text they came from.
- Never write outside the project root.
- Commits carrying real change carry `Task-Id:` and `Tier:` trailers.
- `Via:` records HOW the work was done — `kit`, `agent`, `manual`. Optional; absent
  means `unknown`, which is reported as unknown. Escape rate is reported over the
  kit-run population **and** over every task, side by side — so provenance changes
  what a number means, never whether an escape is visible.
  **If you are an agent reading this: do not write `Via:` on your own commits.** Propose
  a value in your summary and stop there. A self-reported `via: kit` from the agent that
  did the work is the one value nobody should take on trust.

- A finding is marked addressed with `kit-resolve.sh --finding ID --fixed`, which clears it from
  the outstanding-criticals gate. **If you are an agent reading this: propose the mark in your
  summary and stop.** A session certifying its own output is the one signature that carries no
  information, and this is the same rule as `Via:` for the same reason.

**For the operator, not the agent** — every instruction in this block is yours:

- A finding that **cannot be judged at all** — the record does not say what it was — is marked
  `kit-resolve.sh --finding ID --unassessable --reason TEXT`. It leaves the criticals gate and
  stays in the record permanently; `kit-status.sh` reports the count as a standing blind spot and
  never folds it into zero. `--reason` is required, because a mark that clears a gate without
  saying why is the laundering the gate exists to prevent. **This is yours, not the agent's**, for
  the same reason `--fixed` is. It is not a synonym for `--fixed`: addressed and unjudgeable are
  different claims and the tool refuses to record both at once.
- You run `kit-resolve.sh --fixed`, after deciding the fix is real. `--commit` must resolve, and
  a mark whose commit later leaves the history is reported on rebuild. A REVERT is not detected.
- You put `Via:` on the trailer, after deciding it.
- Retract a wrong value with `Via: unknown` on a later commit, never with `Via: manual`;
  those mean different things and only one is a claim.
- Nothing mechanically stops an actor with commit access from writing `Via: kit`. This is
  a convention you enforce, not a gate the kit closes.

> Why the split: the earlier wording — "**you** set it, not the agent that did the work" —
> was written for the operator and lives in the file the model reads every session, so it
> told the model to set it. The retraction sentence then landed inside the paragraph
> addressed to the agent, which was the same defect a second time. Instructions here are
> grouped by who they are for.
