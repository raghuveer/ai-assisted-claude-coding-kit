---
id: T-20260819-a-finding-whose-subject-no-longer-exists
title: A finding whose subject no longer exists has no disposition so it blocks a gate forever
epic: feedback-loop
tier: T2
lang: bash
paths: tooling/kit-resolve.sh, tooling/kit-status.sh, tooling/kit-preflight.sh, .claude/CLAUDE.md
state: open
---

## Intent

The kit can record three things about a finding, and none of them fits the case that turns out to
be the most common one on a design review:

| command | claim |
|---|---|
| `kit-resolve.sh --fixed` | it was addressed |
| `kit-resolve.sh --unassessable` | it cannot be judged at all |
| `kit-vindicate.sh --false` | it was never a real defect |

**Nothing says "the thing this criticised no longer exists."**

Measured 2026-08-19 on `T-20260814-one-entry-mechanism-brownfield-is-the-ge`, which carries 64 open
findings — **more than half of every open finding on a closed task in this repository**. Of those,
**31 are reviews of `docs/design-input/2026-08-15-entry-mechanism.md`**, and design 2 opens by
rejecting design 1 outright: *"That design was rejected twice"*, and §A — *"Design 1's per-area
inventory. **Reject — now measured, not argued**"*, falsified against three real repositories.

Every one of the three existing dispositions is **wrong** for those 31:

- `--fixed` is false. Nothing was fixed; the design was abandoned.
- `--unassessable` is false. They are perfectly assessable — the record is intact and the
  reasoning is legible. That mark is for the nine findings that predate the `summary` column and
  have nothing left to judge.
- `--false` is the worst of the three. They **were** real. Being real is why the design died.

So they sit in the gate permanently, and under the operator's rule that all findings must be
addressed before a task closes, **`one-entry-mechanism` can never close no matter how much work is
done on it.** A gate that cannot be satisfied by any amount of correct work is the same failure the
`--unassessable` route was built to remove, arriving one category over.

## Acceptance criteria

- [ ] A finding can be recorded as **superseded** — its subject was withdrawn, rejected or replaced
      — distinctly from fixed, unassessable and false. The distinction is the point: a review that
      killed a design is evidence the review worked, and collapsing it into "fixed" erases that.
- [ ] The mark **names what superseded it** — the ADR, the revision, or the commit that withdrew
      the subject. `--reason` is required on `--unassessable` because a mark that clears a gate
      without saying why is laundering; this is the same requirement for the same reason.
- [ ] It **leaves the gate and stays in the record**, exactly as `--unassessable` does, and
      `kit-status.sh` reports the count separately rather than folding it into zero. A design that
      was rejected because a review found 31 problems is a fact worth keeping.
- [ ] **The route is not reachable for a finding whose subject still exists.** `--unassessable`
      already refuses a finding that carries a summary; this needs the equivalent guard, or it
      becomes the escape hatch for anything inconvenient — which would make the whole findings
      record worthless.
- [ ] `.claude/CLAUDE.md` gains it in the operator block alongside `--fixed` and `--unassessable`,
      and it is **operator-reserved for the same reason**: a session deciding its own findings are
      moot is the signature that carries no information.
- [ ] A check that can fail, covering both directions: a finding on a live subject must be refused,
      and a superseded one must leave `kit-preflight.sh --criticals` while still being counted by
      `kit-status.sh`.

## Notes

Found 2026-08-19 while walking the 64 findings on `one-entry-mechanism` at the operator's request,
after measuring that 325 open findings existed against 17 ever marked fixed and asking which of
them were real.

**The population is not homogeneous, and that was the actual finding.** Of the 64: 31 are reviews
of a rejected design, 15 review the design that replaced it, and 18 anchor to code — of which five
were verified fixed and marked, one **critical remains live** (`kit-entry.sh` still contains the
`[^']*` sed capture), and `--` guarding is still partial (`head` has it, `grep` and `awk` do not).

**Not a licence to clear the backlog.** This disposition applies only where the subject is
genuinely gone. The 206 findings on `progress` tasks are unaffected, and so are the nine remaining
criticals, which all carry summaries and are therefore ordinary fix work.

Related: `T-20260813-nine-criticals-predate-summary-and-canno` built `--unassessable` for the
adjacent case and is the model to follow — including its refusal guard, which is the criterion here
most likely to be skipped.
