---
description: Detect drift between the docs (status pointer, backlog, roadmap) and the real code/git state
---

Read-only sanity check. **The docs are claims; git and the code are ground truth.** Find where they
disagree, report it, and propose the reconcile — do not edit anything unless the operator confirms.

Steps:

1. Read the live status pointer and note **every concrete claim** it makes about what is done, in
   progress, or next.
2. Establish ground truth: recent commits, tags, and working-tree state for each repository the project
   spans.
3. Spot-check the truth-docs the status pointer links — the backlog, the relevant decision records —
   against that git reality. Does a document call something "planned" that the commits show shipped, or
   "done" that the working tree contradicts?
4. For anything referenced by identifier (a file, a decision-record number, a migration, an env var, a
   pull request), **verify it exists** rather than trusting the document.

Report as a short table: **Claim → where it is stated → actual state (git/code) → verdict (matches /
STALE / unverifiable)**. For each STALE row, propose the one-line fix.

Two cautions worth carrying:

- **Structural evidence cannot establish intent.** "No reader, no writer, no rows" distinguishes
  *abandoned* from *deliberately reserved* not at all. Where a finding depends on intent, the answer is
  a question for the designer, not a conclusion.
- **A mechanical check that compares derived state to git is cheaper and more reliable than this one**,
  and should run automatically. Use this command for the *narrative* claims a script cannot judge.

End by asking whether to apply the proposed reconciles. $ARGUMENTS
