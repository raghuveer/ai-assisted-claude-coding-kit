---
description: End-of-work-unit ritual — verify, update the status pointer, commit locally
---

Run the checkpoint ritual to externalize the current state into durable files. Do this at the end of
each meaningful work unit, not just at end of day. The conversation is a scratchpad: it compacts, and it
is lost on restart. Every durable fact belongs in a file.

Steps:

1. **Summarize** what changed in this unit: files touched, decisions made, anything left mid-flight.
   Name anything you left undone or unresolved — a decision the operator interrupted is a checkpoint
   *output*, not a loose end to drop.

2. **Verify.** For any changed product source, run the affected component's test command. If a runtime
   flow changed, drive it. Report actual results — never mark done on "should work". If tests fail, stop
   and surface them.
   - **If no product source changed, say so** rather than implying you re-ran a suite. Verify what you
     *did* change, with the tool that fits it: syntax-check and actually run `--help` for a shell script,
     an import check for a module, a config validator for config, a strict build for a docs site, a
     migration-head check for a migration chain.
   - **Mutation-test the change, not just the parser.** Revert each new guard or call site individually
     and confirm a test goes red. A surviving mutant is a finding, not a formality.

3. **Reconcile item status — it is mechanical, and it is not your job to remember it.**
   If the project derives status from commit trailers, run the sync in check mode and reconcile if it
   reports drift. Git wins; the tracker is derived, not authored.
   - **Do not hand-edit a derived status field.** Doing so re-creates the second source of truth the
     derivation replaced.

4. **Update the live status pointer** (Now / Next / Blocked / Open decisions, and the last-updated line).
   Keep it a *pointer* — link to detail docs, do not duplicate them.
   - 🔴 **The status pointer carries NO per-item status.** "Item X is done" belongs in the tracker. This
     file carries **direction and warnings**: what is in flight, what is next, what is blocked, and what
     will bite the next person. Duplicating item state is how a status file goes quietly stale.
   - **Keep it short.** It is re-read every turn, so cost = size × frequency. When it grows past its
     budget, move the oldest completed-unit detail into a dated archive — **append there verbatim first,
     verify it landed, then compress the copy that stays**. Never delete analysis to hit a line count.

5. **Decision-record check.** If a real decision was made, write or amend the record. Records are
   append-only: a Status field plus a banner is the only sanctioned edit to an existing one, and
   amendments are new dated sections with their own decision IDs. When superseding, **scope it
   precisely** — if a record decided two separable things and only one died, mark it *partially*
   superseded and say which half still stands.

6. **Commit locally** on the current branch (`git add` the intended paths, then commit).
   - **Push only with authorization.** Default is local-only. An explicit "push it" from the operator
     counts for that unit; it does not carry to the next.
   - **Check every repository, not just the one you were working in.** List each one's branch and
     ahead/behind state. A repo you forgot is a repo that silently diverges.
   - **Never commit secrets.** If the project tracks any operator-authored prose (notes, logs), scan it
     for credential patterns before staging and **report hits rather than committing quietly**.
   - `git rm <path>` followed by `git add <same path>` fails on the pathspec and aborts the whole `add`.
     Stage deletions and edits separately, or the commit silently carries half the change.

7. **Regenerate anything derived** from the docs you changed — a docs site, an index, a generated nav —
   and build it strictly. Generated output is never hand-edited; fix the source instead.

8. **Capture cost.** If your harness reports per-session spend, ask the operator for the figure and
   record it against this unit. It is the only faithful number, because it includes subagent tokens the
   transcript does not. If it is not supplied, write "not captured" rather than estimating.

9. **End the session lean — the biggest token lever, and it is quality-neutral.** At a unit boundary,
   clear the context (the next unit rebuilds from files). Mid-unit, compact instead. Do not carry more
   than one unit of context forward: a long window re-reads its growing context every turn, and that
   read tends to dominate spend.

$ARGUMENTS
