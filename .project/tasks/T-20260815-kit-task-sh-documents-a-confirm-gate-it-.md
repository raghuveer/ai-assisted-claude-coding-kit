---
id: T-20260815-kit-task-sh-documents-a-confirm-gate-it-
title: kit-task.sh documents a confirm gate it does not implement
tier: T2
lang: bash
paths: tooling/kit-task.sh, docs, INSTALL.md, SECURITY.md
state: open
---

## Intent

`tooling/kit-task.sh:8-10` says:

> Intended use: a researcher proposes a breakdown, a human confirms and edits, then
> this writes the confirmed tasks. **The confirmation is the gate** — a model writing
> straight to disk means the model is setting your backlog.

There is no gate. Lines 30-52 validate `--title` and `--tier`, build the id, and write the file.
The only refusal in the script is `[ -e "$f" ] && exit 1`, which catches an id collision. Any
actor that can run the script — including a model holding Bash — writes a task file, and the
"confirmation" is a sentence describing what a human is expected to have done beforehand.

The comment is not wrong about the INTENT. It is wrong about where the gate lives, and it is the
comment a reader trusts, which is why this is `false-rationale` rather than a doc nit.

It has already been leaned on as though it were a mechanism. The entry-mechanism design cites
`kit-task.sh` as "the confirm gate it already documents itself to be" and builds Option 4's
entire structural-prevention argument on it. Found by the blind approach reviewer on 2026-08-15
(finding 3). The first reviewer checked whether the header *documents* a gate, found that it
does, and recorded the claim as verified — a verification of the wrong proposition, which is
worth keeping as evidence for `T-20260809-a-claim-audit-before-a-task-closes-names`.

## Acceptance criteria

- [ ] The comment states where the gate actually is, and does not name a gate this script
      enforces unless it enforces one.
- [ ] A grep for the same shape elsewhere: every place that cites `kit-task.sh` as a gate —
      `INSTALL.md`, `docs/`, `skills/`, `agents/`, `CLAUDE.md` — is swept in the same change
      rather than one instance fixed. When a reviewer names an instance, grep the shape.
- [ ] If a mechanical gate is added instead, it is a gate that can FAIL and a mutation proves it,
      and the reason a human-in-the-loop step is worth mechanising is written down. Adding a flag
      a caller can always pass is not a gate.
- [ ] The distinction is reflected in `SECURITY.md`, which already separates enforced-mechanically
      from convention-only, and currently does not list this.

## Notes

Filed 2026-08-15 out of the entry-mechanism approach reviews.

Preference, not a decision: `docs/LESSONS.md` §5 prefers deleting a component to hardening it,
and the honest cheap fix is to move the sentence into the convention column rather than build an
enforcement mechanism for a step whose whole value is that a human performed it. A gate that a
model can satisfy by passing `--yes` is the laundering, not the control — the same argument
already settled for `Via:` and for `kit-resolve.sh --fixed`.

Related shape: `T-20260814-a-fresh-adoption-reports-none-outstandin` and the `Via:` split in
`.claude/CLAUDE.md` — both are cases where prose addressed to a human sat where only the agent
would read it.
