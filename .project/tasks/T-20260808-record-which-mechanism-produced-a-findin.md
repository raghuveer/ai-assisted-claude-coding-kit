---
id: T-20260808-record-which-mechanism-produced-a-findin
title: Record which mechanism produced a finding so the accelerator and the second reviewer can be judged
epic: measurement
tier: T2
lang: bash
paths: tooling/schema.sql, tooling/kit-finding.sh, tooling/kit-status.sh
state: open
---

## Intent

The `finding` table records agent, model, tier, lang, class, pattern, domain and severity. It
does not record WHICH MECHANISM produced the finding. Two of this project's load-bearing
claims are therefore assertions rather than measurements.

**"Accelerators are worth their cost."** The whole amortisation bet — the README's central
open question — is that a finding earned on one project becomes reusable knowledge that finds
defects on the next. Nothing distinguishes a finding an accelerator prompted from one the
reviewer reasoned to unaided, so accelerator-attributable yield cannot be computed at all.

**"The T3 second reviewer earns its keep."** `docs/MEASUREMENTS.md` argues this from one
design-stage comparison: both reviewers returned REJECT, ~70% of findings shared, and the
other 30% was the value. That is n=1 and it was hand-scored. On 2026-08-08 five T3 reviews
ran on this repository and in three of them the blind second reader found a critical the first
missed — which is now anecdote for the same reason: nothing records that a finding came from
the second reader rather than the first.

## Acceptance criteria

- [ ] A finding records its source, from a closed vocabulary defined in ONE place, following
      exactly the shape `via` already set: `accelerator | reviewer | second-reviewer |
      tier-floor | unknown`, defaulting to unknown, with unknown reported as itself.
- [ ] The field is added to the CONTRACT in `kit_findings.py` and appears in
      `kit-finding.sh --contract`; the reviewer agents are updated to emit it, and a reviewer
      that omits it still validates, since it defaults to unknown.

      *Rewritten 2026-08-11.* This criterion used to require `kit-finding.sh --batch` to accept
      the new field "without breaking the existing field order, since the reviewer agents emit
      that format verbatim". **`--batch` and its positional format no longer exist** — reviewers
      return a JSON object and order carries no meaning, so the whole hazard this criterion
      guarded against is gone. Found by a round-4 reviewer as an unswept consequence of deleting
      it, which is the same §4 lesson one layer out: deleting a component means sweeping the
      backlog that still expects it.
- [ ] `kit-status.sh` reports yield by source: findings per source, and — the number that
      settles the second-reviewer question — how many findings came ONLY from the second
      reader on tasks where both ran.
- [ ] Cost per finding by source, using the billing-weighted spend the kit already records per
      agent. That is the comparison the accelerator bet needs and cannot currently make.
- [ ] The agent files are updated together with the recorder, and the conformance vocabulary
      assertion covers the new axis. The finding vocabulary drifted across four locations once.

## Notes

The idea is lifted from `ArchAI-Labs/medha`, which is otherwise irrelevant to this kit — a
Python semantic cache for text-to-query. Its one transferable design is that every cache hit
records which of its five strategies produced it, and it reports hit rate and latency per
strategy. That is the same discipline this kit applies to tiers, one level finer, and it is
what turns "the accelerators are working" into a number.

Note the second-order value flagged during that research: if `second-reviewer` provenance
rarely yields findings the first reviewer missed, that is direct evidence for LOWERING the T3
floor and saving real money. The measurement can argue against the design, which is the point.

Related: T-20260808-record-how-a-task-was-executed-so-kit-wo established the vocabulary
pattern, the human gate and the one-definition conformance assertion this should copy.
