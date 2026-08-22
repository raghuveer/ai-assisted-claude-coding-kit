---
id: T-20260822-a-task-has-no-authored-assignee-so-a-cla
title: A task has no authored assignee so a claim cannot be expressed or merged
epic: planning
tier: T2
paths: templates/task.md, tooling/kit-task.sh, tooling/kit-index.sh, INSTALL.md
state: open
---

## Intent

Nothing in the kit lets a person or an agent say **"I am taking this."** Verified 2026-08-22:

    grep -n 'v\["owner"\]\|v\["assignee"\]' tooling/kit-index.sh   # nothing: frontmatter is never read for it
    grep -nE '\-\-owner|\-\-assign'         tooling/kit-task.sh    # no flag
    grep -nE 'owner|assignee'               templates/task.md      # no field
    grep -n  'owner'                        tooling/schema.sql     # ALTER TABLE task ADD COLUMN owner -- DERIVED only

Ownership exists **only** as a derived column, and that column is separately defective
(`T-20260822-derived-owner-flips-to-whoever-committed`). So responsibility can be inferred after
the fact and never declared in advance, which is the wrong way round for coordinating work.

## Why this matters more once agents run unattended

The intended way of working is a human developer and a coding agent both picking up tasks, in the
same repository, sometimes at the same time. That needs a claim, and a claim has three properties
the kit cannot currently provide:

1. **Declared before the work**, not inferred after it. A derived value cannot prevent anything.
2. **Visible to the other party.** This is the constraint that decides the design:
   **`.project/index.db` is gitignored and per-machine.** A status or flag held in the cache is
   invisible to a second clone, so a claim recorded there coordinates nobody while looking as
   though it does. The claim must live in committed text.
3. **Contested safely.** Two claimants must produce a *conflict*, not a silent last-writer-wins.
   Frontmatter in a task file gives this for free — git raises the conflict. `events.ndjson` does
   not: it is `merge=union` (`.gitattributes:20`), deliberately, so two concurrent claim events
   would both merge and both appear valid.

**A new task state is the wrong mechanism, and there is evidence.** `blocked` and `unblocked` have
**zero uses across 130 tasks**, because `blocked_by:` already carries blockedness structurally. A
`claimed` state would repeat that mistake: a state duplicating something structural, unenforceable,
and — if read from the cache — authoritative-looking and wrong. See docs/adr/0008.

## Acceptance criteria

- [ ] A task can carry an **authored** assignee in its frontmatter, distinct from any derived
      contribution record, and `kit-task.sh` can set it at creation.
- [ ] It is a SET, not a single name. The operator's framing is contributors, and two people on
      one task is already the measured case: 9 tasks carry 2 distinct event actors today.
- [ ] Contested claims **conflict rather than merge**. State plainly which file the claim lives in
      and why that file's merge behaviour is the one wanted — `events.ndjson` is `merge=union` and
      is therefore the wrong home, and that reasoning belongs in the task file, not in a session.
- [ ] It is stated, where an adopter reads it, that a claim is **advisory** and that the only
      mutual exclusion in a distributed repository is the push. Anything stronger claimed here
      would be a control that cannot fail — the shape `docs/LESSONS.md` §1 exists to refuse.
- [ ] An agent may PROPOSE a claim and never self-certify one, consistent with `Via:` and with
      finding dispositions. The same reason applies: a self-reported claim from the actor that
      benefits from it carries no information.

## Notes

Filed 2026-08-22 from a working session on ADR 0008, on the operator's framing that work is done
by **contributors** — multiple people, multiple commits per task — rather than by a single owner.

Not a blocker for `T-20260808-trial-the-kit-on-one-unfamiliar-brownfie` and deliberately not added
to its `blocked_by`. The trial is single-operator; this matters when the kit is used by a team or
by unattended agents, which is later.

Related: `T-20260808-parallel-task-execution-has-no-isolation` (can two run at once safely),
`T-20260822-derived-owner-flips-to-whoever-committed` (recording who did, after the fact), and
`T-20260808-record-how-a-task-was-executed-so-kit-wo` (`via:` — HOW, not WHO).
