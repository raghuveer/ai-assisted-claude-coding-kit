---
id: T-20260820-marking-findings-is-one-at-a-time-so-the
title: Marking findings is one at a time so the record is write only in practice
epic: feedback-loop
tier: T2
lang: bash
paths: tooling/kit-resolve.sh, tooling/kit-status.sh, skills/verify-ladder/SKILL.md
state: open
---

## Intent

Measured 2026-08-20: **351 findings recorded, 22 marked fixed, 9 marked unassessable.**

All 31 of those marks were applied in a single session, under explicit instruction, after being
asked for. Before that the count was 17 — and 8 of those predate the `summary` column. **The
findings table has been effectively write-only since the loop was built.**

**The gate is not the problem and must not be weakened.** `kit-resolve.sh --fixed` and
`--unassessable` are operator-reserved for a reason `.claude/CLAUDE.md` states plainly: a session
certifying its own output is the one signature that carries no information. The kit defends this
properly — verified 2026-08-20, `kit-event.sh` refuses to write `finding-fixed` at all, because
the indexer acts on it.

**The problem is that the design demands a human decision and gives that human no affordance for
making twenty of them.** Marking twenty findings means twenty invocations, each needing an id the
operator must first query for, each id needing `tr -d '\015'` on this platform because `sqlite3`
emits CRLF. The cost of recording a decision exceeds the cost of making it, so the decision does
not get recorded — and the record drifts from reality until nobody trusts it.

**The consequence is now load-bearing.** With the operator's rule that all findings must be
addressed before a task closes, three otherwise-complete tasks cannot close, and two of them block
`T-20260808-trial-the-kit-on-one-unfamiliar-brownfie`. The backlog is not blocked by engineering;
it is blocked by bookkeeping the tool makes expensive.

## Acceptance criteria

- [ ] A human who has just done the work can dispose of **many findings in one reviewed action** —
      by task, by class, by file, or from a list they edited — without looking up ids by hand.
- [ ] **The human decision stays per-finding, even when the action is bulk.** The operator must see
      what they are about to assert before asserting it; a command that marks forty findings
      sight-unseen is the self-certification this gate exists to prevent, wearing a batch flag.
      Show, then confirm, then write.
- [ ] The reason or note travels **per finding**, not once for the batch. `--reason` is required on
      `--unassessable` precisely because a mark that clears a gate without saying why is
      laundering, and a single reason stamped across forty rows is that same laundering at scale.
- [ ] It is **still an event stream**. `kit-resolve.sh` writes events and the index derives from
      them; a bulk path that wrote the database directly would be the second source of truth ADR
      0004 spent a whole decision removing.
- [ ] Partial failure is **all-or-nothing, or itemised**. `kit-finding.sh` already rejects a whole
      batch on one bad value, on the stated grounds that a half-stored review disagrees with the
      review it came from. The same argument applies here and the same choice should be made
      deliberately rather than inherited by accident.
- [ ] `kit-status.sh` reports the **marking rate**, not only the counts — findings recorded against
      findings dispositioned. The gap this task exists to close was invisible until someone
      divided one number by the other, and it will become invisible again.
- [ ] A check that can fail, covering the quiet direction: a bulk mark must not touch a finding the
      operator did not see, and an id that does not resolve must refuse rather than silently skip.

## Notes

Filed 2026-08-20 after an audit of where task and finding status is stored, which found four
locations — `events.ndjson` authoritative, task frontmatter as fallback, `index.db` derived, and
acceptance-criteria checkboxes **read by nothing**. The checkbox half is a separate defect in its
own right: a human ticks `- [x]`, believes progress is recorded, and no mechanism agrees.

**This is distinct from the three tasks already circling the findings loop**, and none of them
covers it. `T-20260801-nothing-invokes-kit-finding-so-the-findi` is about findings never being
*recorded*. `T-20260812-a-finding-cannot-be-marked-fixed-so-any-` built the `--fixed` mechanism
that now exists. `T-20260819-a-finding-whose-subject-no-longer-exists` is about a missing
*disposition*. This one is about the **cost of exercising the dispositions that exist**.

**Do not solve it by inferring.** A tempting shortcut is to mark a finding fixed when its file
changed after the finding's date. That is the "looks done" inference the whole gate refuses, and it
would be wrong in both directions: this session found findings whose file had changed many times
and which were still live, and findings whose subject was a design that had been abandoned
entirely.
