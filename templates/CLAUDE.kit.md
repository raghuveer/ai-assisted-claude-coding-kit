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

**For the operator, not the agent** — every instruction in this block is yours:

- You put `Via:` on the trailer, after deciding it.
- Retract a wrong value with `Via: unknown` on a later commit, never with `Via: manual`;
  those mean different things and only one is a claim.
- Nothing mechanically stops an actor with commit access from writing `Via: kit`. This is
  a convention you enforce, not a gate the kit closes.
- Back-filling a task finished before adoption? The frontmatter key is lowercase `via:`.
  `Via:` is the git trailer, and a commit already written cannot gain one.

> Why the split: this file is read by the agent every session, so an instruction addressed
> to "you" is read by the model as its own. Instructions are grouped by who they are for.
