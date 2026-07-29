---
description: Start-of-session ritual — rebuild context from files, not old conversation
---

Rebuild working context from durable files. **Do NOT rely on any prior conversation state** — it is
stale, it was compacted, and it may be from a different unit entirely.

Steps:

1. Read the project's **live status pointer** — Now / Next / Blocked / Open decisions.
2. Establish ground truth from git, which always wins over any document:
   - recent history: `git log --oneline -15`
   - working state: `git status --short`
   - if the project spans several repositories, do this for each one and note any that have diverged.
3. Open **only** the truth-docs the status pointer links for the item about to be worked — the backlog
   section, the relevant decision record, the topic doc. **Do not read broadly.** Pull the specific
   thread; a wide read at the start of a session is context you pay for on every subsequent turn.
4. For anything referenced by identifier — a file, a decision-record number, a migration, an env var, a
   flag — **verify it exists** with a search rather than trusting the document. Documents age against a
   moving codebase exactly like comments do.
5. Give a short orientation, five lines at most: where we are, what is next, and **anything that looks
   stale or contradictory between the status pointer and git**. Flag it explicitly — the code is the
   tie-breaker for "what exists", and a contradiction found here is cheaper than one found later.

Then wait for direction. Task to focus on (optional): $ARGUMENTS
