# Retro, period one: 2026-08-17 to 2026-08-20

**A hand-run instance of the artefact `T-20260811-a-retro-artefact-that-closes-the-kaizen-` is
meant to generate.** Written by hand because the command does not exist, and written *before* it
does so the command has a target shape derived from a real period rather than an invented one.

Every figure carries its n. Where the honest answer is "not enough data", it says so instead of
printing a zero that reads as a measurement — the `0 / 0 via:kit` defect that task's last
criterion exists to prevent.

---

## 1. The period

One T3 change — plan persistence, ADR 0004 — plus its review chain, the clustering fix, and two
plugin deployment runs. **Five tasks closed: 3 × T3, 2 × T2.**

## 2. Did the agents earn their cost?

One T3 change, three reviewers, launched concurrently so rung 5's blindness was structural.

| agent | critical | major | minor | nit | tokens |
|---|---|---|---|---|---|
| `approach-reviewer` | **1** | 9 | 5 | 2 | 106,119 (+117,743 resume) |
| `security-reviewer` | — | 8 | 4 | 1 | 134,882 |
| `implementation-reviewer` | — | 4 | 1 | — | 140,718 |

**Guard condition — "any agent producing zero findings across a full retro period is a candidate
for removal": not triggered.** All three produced findings. n=1 period.

**The lists barely overlapped, which is the finding.** `security-reviewer` alone found a `goal_id`
that became a filesystem path an agent loads verbatim, a `1e999` score that killed the whole index
build, and an ignored `awk` exit status. `approach-reviewer` alone found that the ADR's
load-bearing claim — *packs are a rebuildable cache of the plan* — was false. Three reviewers
independently found the slug-versus-`goal_id` mismatch; two found the unchecked `plan_stale` writes.

That is `verify-ladder`'s claim about rung 5 — *"run it expecting a different half of the problem"*
— measured rather than asserted, for the first time.

**Not enough data to act on the spread.** `implementation-reviewer` raised 5 findings against
`approach-reviewer`'s 17 on the same change. On a change that was mostly *new mechanism* rather
than new code, design and security dominating is plausible. **At n=1 this is a datum to carry
forward, not a signal to tune a prompt on.**

## 3. Where did rework come from?

**Not from the reviewers. From what happened after them.**

The approach reviewer wrote *"task-context step 4 has no miss path"*. Two mechanisms were built in
response — `--packs` to recover a clone's packs, and a `kit-status.sh` notice to make the state
discoverable — the finding was **marked fixed with a note**, and the task was closed.

A live plugin session on 2026-08-20 then walked into exactly that miss path. `skills/task-context`
step 4 still had no branch for a row whose pack is absent, and the only repair it names — bare
`kit-plan.sh` — **discards the committed plan**. The session recovered only by reading
`kit-plan.sh`'s source comments.

**The finding was marked fixed against CODE CHANGED rather than BEHAVIOUR RESTORED.** The site was
fixed; the consumer was never touched. That is the single most expensive error of the period and
it is not a reviewer failure — the reviewer named it precisely, in those words.

## 4. Is the tier distribution calibrated?

**Cannot be answered, and this is the honest form of the answer.** Escape rate needs escapes:
`SELECT COUNT(*) FROM event WHERE kind='escaped'` returns **0**, and has since the kit was built.
Nothing has ever been recorded as escaping its tier.

So *"was T3 the right tier for the plan change"* has no measurement behind it. What can be said:
the T3 chain found 1 critical and 21 majors on that change, and a T2 chain would have run neither
rung 5 nor a second blind reader — the two that produced the critical and the input-validation
class respectively. **Suggestive, not calibration.**

## 5. Cost signals

**The kit's own repository has zero `scope=subagent` spend rows.** Hooks fire only under
`--plugin-dir`, and kit development does not run that way — so every reviewer figure in §2 came
from the harness, not from the kit's own instrument.

The instrument itself is proven: a plugin run against a throwaway subject took spend events **0 → 2**
with `scope=subagent`, `agent=general-purpose`. **The kit can measure this and does not, on itself.**

## 6. The concrete change this retro produces

AC1: *a retro that changes nothing is a report, not a loop.*

**Change `agents/implementation-reviewer.md`: when a change claims to close a prior finding, the
reviewer must check the CONSUMER of the fixed mechanism, not only the site.**

Justified by §3, and generalisable beyond it. The existing universal failure modes already include
*(h) a fix ported from a sibling control must bring that control's REASONING* — this is its
sibling: **a fix that satisfies a finding's wording at the site while leaving the caller unchanged
still reads as closed.** The period produced a clean instance: `--packs` existed, `kit-status.sh`
reported the state, and the skill that dereferences the pack was untouched.

Proposed wording, for the "Universal failure modes" list:

> **(i) A fix that closes a finding at its site may leave its CONSUMER unchanged.** When a diff
> claims to address a prior finding, find who *reads* the thing that was fixed and check that path
> too. A mechanism can be repaired, made observable, and still be unreachable from the code that
> needed it — which reads as closed in the record and is open in behaviour.

**Not proposed:** any change to the risk-tiering table. §4 shows there is no calibration evidence,
and changing floors on a hunch is what that table's own comment forbids.

## 7. What this retro cannot close, and why it matters to the command

Three of this period's failures were **mine, not the pipeline's**, and no artefact the kit produces
would have caught them: reporting an in-flight suite as a result, editing a running script,
`git checkout` over uncommitted work, and scripted patches whose anchors silently did not match.

They are recorded here because a retro that only measures the pipeline will report a healthy period
in which most of the lost time was operator error. **If the retro command cannot see this class, it
should say so rather than imply coverage** — the same discipline `security-reviewer`'s boundary
section already applies to SCA, SAST and DAST.

## 8. Inputs the command will need, from having done it by hand

- findings by agent and severity over a period — **available**, `finding.at`
- tasks closed by tier over a period — **available**, `task.closed_at`
- escapes by tier — **available and empty**; must print "no escapes recorded", never `0 / 0`
- per-agent spend — **available only under `--plugin-dir`**; degrade to kit-side data and say so
- *disposition latency* — findings recorded versus dispositioned, and how long between —
  **not currently derivable**, and it is the number that would have surfaced this period's real
  problem: 351 findings recorded against 17 ever dispositioned before this period.
