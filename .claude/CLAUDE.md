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

- **Verify on the fast platform first. Work on a branch, push, and read CI before starting the
  local suite.** Not a reordering of "verify then publish" — CI *is* the fast verifier here:

      ubuntu-latest   ~45s     full suite
      macos-latest    ~1m50s   full suite
      Windows, local  ~1 hour  full suite, and the only Windows signal there is

  Both matter and neither substitutes for the other — Windows is in no CI matrix, and CI covers
  two platforms this machine cannot. So run them **in parallel**: commit, push, and start the
  local run in the same breath. Committing does not modify the working tree, so there is never a
  reason to serialise them.

  **If CI goes red, stop the local run rather than letting it finish.** Fixing means editing the
  files it is reading, which invalidates it anyway; a run whose tree changed under it measured a
  state that never existed. Iterate against CI until green, then let Windows confirm.

  **A branch push alone triggers nothing** — the workflow fires on `pull_request` and on pushes
  to `main`. Open the PR, or CI never starts. PRs are also what keep `main` green: only verified
  work merges.

  This is written down because knowing it was not enough. The order was inverted twice in one
  session after the lesson had already been recorded, and both times the correction came from the
  operator asking rather than from the note. Treat it as a precondition on the ACT of running the
  suite locally — *is this pushed?* — not as a strategy to remember.

  **Temporary.** It is shaped by the Windows suite costing an hour against CI's 45 seconds. When
  that gap closes, this belongs in history rather than in the working agreement.
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
- A finding whose **subject was withdrawn** — the design it reviewed was rejected, the revision it
  criticised was replaced — is marked
  `kit-resolve.sh --finding ID --superseded --by NAME`. A fourth claim, not a synonym for any of
  the three above: `--fixed` would say it was addressed and nothing was, `--unassessable` says
  nobody can tell what it said and these are perfectly legible, `--false` says it was never real
  and **it was — being real is why the subject died.** Collapsing that into "fixed" erases the
  most valuable thing a review does.

  **The guard is a marker in the tree, not the flag.** `--superseded` is refused unless the
  finding's own `file_path` carries a `Superseded-by:` line naming the same thing `--by` does. So
  the withdrawal is reviewable in a diff and lands in front of the next reader of the subject.
  It is refused outright when the finding records no `file_path`, and when the file is **absent** —
  deleting the evidence must not be the cheapest way out of the gate. Like `--unassessable`, it
  leaves the criticals gate, stays in the record permanently, and `kit-status.sh` counts it
  separately rather than folding it into zero. **Yours, not the agent's**, for the same reason.
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
