---
id: T-20260812-a-finding-cannot-be-marked-fixed-so-any-
title: A finding cannot be marked fixed so any gate on open criticals is uncomputable
epic: measurement
tier: T2
lang: sql
paths: tooling/schema.sql, tooling/kit-vindicate.sh, tooling/kit-status.sh
state: open
---

## Intent

The `finding` table records what a review found. It has **no column expressing whether the
finding was addressed**. Columns are `id task_id agent model tier lang class domain pattern
severity at vindicated summary file_path line_no`, and `vindicated` answers a different
question — *was this real or a false positive* — set by `kit-vindicate.sh --real|--false`.

So **"is there an open critical on this task" cannot be computed**, and anything gating on it
either blocks forever or gets ignored.

Found by executing `docs/TRIAL-PROTOCOL.md` on 2026-08-12. Its §0 pre-flight requires "no task
at `progress` carrying an unfixed critical". Run against this repository:

    SELECT COUNT(*) FROM finding f JOIN task t ON t.id=f.task_id
     WHERE f.severity='critical' AND t.state='progress';   -- 16

Sixteen — including findings fixed hours earlier the same day, such as *"file pattern lang and
domain are interpolated into the event"*, whose fix landed in `d907522`. The gate was overridden
to let the trial proceed, which is the honest outcome and also proof the gate is decorative.

**Three review rounds on that protocol did not find this. Running the first checkbox did.**

## Why it matters beyond the protocol

- The escape-rate story assumes findings accumulate as evidence. A table that cannot distinguish
  *outstanding* from *addressed* can count findings but cannot report **risk**.
- Any future gate — CI, a close check, the claim audit — hits the same wall.
- It interacts with `vindicated`: a finding can be real **and** fixed, real and open, false and
  irrelevant. One column cannot carry two orthogonal facts and currently is not asked to, so the
  second fact is simply absent.

## The change

Add the missing axis. The shape is a decision, not a detail, and belongs to whoever takes this:

- **A column** (`fixed_at`, or a `state` with a closed vocabulary) set by a command in the same
  family as `kit-vindicate.sh`; or
- **an event**, `finding-fixed`, keyed to the finding, which fits the kit's derive-from-events
  grain better and survives a rebuild.

The second is more in keeping with the rest of the design — `finding` rows are already derived
from `finding` events — but it needs a stable finding identity to key on, and today `id` is
`at:n`, a positional counter that **changes when events are re-read**. That is the real work
here, and it is why this is not a one-line fix.

## Acceptance criteria

- [ ] A finding can be marked addressed, by a command, without editing derived state.
- [ ] "Open criticals on task X" is a query that returns 0 on this repository today, because
      every recorded critical has in fact been fixed. If it does not return 0, either the data
      or the claim is wrong and the discrepancy is the finding.
- [ ] The mark survives `kit-index.sh` rebuilding from scratch — asserted, since findings are
      derived and a mark stored only in the database would vanish.
- [ ] Marking a finding addressed is distinct from vindicating it. A fixture proves all four
      combinations are representable.
- [ ] `docs/TRIAL-PROTOCOL.md` §0's gate becomes computable, or is deleted. **A gate nobody can
      evaluate is worse than no gate**, because it launders "we ignored it" into "we checked".

## Notes

Filed 2026-08-12 from the first execution of the trial protocol
(`docs/TRIALS/2026-08-12-fd-throwaway.md`, finding T-1). Blocks closing that protocol task
honestly: its §0 cannot be satisfied as written.
