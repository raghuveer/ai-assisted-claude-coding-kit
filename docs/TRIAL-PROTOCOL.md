# Trial protocol

How to run the kit against a project it has never seen, so that two trials can be compared.

**This is a procedure, not a report.** You should be able to execute it without having read
`docs/MEASUREMENTS.md`. That document is the first trial's *results*, and it is cited here only
where a rule exists because something went wrong there.

The procedure is fixed **before** a trial, not reconstructed after it. A comparison assembled
afterwards from whatever each run happened to record is not a comparison.

**Revision 2, 2026-08-12.** Revision 1 was reviewed before first use and rejected with two
criticals — its isolation rule left `git push` pointed at the subject, and it mandated a figure
the kit does not emit while forbidding the only way to get it. Both are fixed below. The review
is the reason this document is usable, and the reason to run one again after the first trial.

---

## 0. Pre-flight

Stop unless every box is ticked. Record the answers; they are part of the result.

**The kit**

- [ ] Working tree clean, full conformance green, CI green on every platform.
- [ ] No unfixed critical anywhere in the backlog. **Computable — run it, do not judge it:**

      sqlite3 .project/index.db "SELECT COUNT(*) FROM finding
                                  WHERE severity='critical' AND fixed_at IS NULL
                                    AND COALESCE(vindicated,1) <> 0;"

      **Not filtered by task state.** Revision 3 of this box read `AND t.state='progress'`,
      which meant a critical on a *done* task did not count — so closing the task cleared the
      pre-flight exactly as well as fixing the defect, and two of this repository's own
      outstanding criticals were invisible to it. A gate you can satisfy by changing a status
      field is not a gate. Refuted findings (`vindicated=0`) ARE excluded, because a reviewer
      being wrong is not outstanding work; `kit-status.sh` prints that exclusion as its own
      count so it cannot be mistaken for a lower number.

      Zero, or stop. `kit-status.sh` prints the same thing per task under **Outstanding
      criticals**, and `kit-resolve.sh --list --severity critical --unfixed` names them.
      An unmarked finding counts as OUTSTANDING: silence is not a fix.

      > Revision 2 wrote this box with no way to evaluate it. The `finding` table had no column
      > for whether a finding was addressed — `vindicated` says whether it was *real*, a
      > different question — so the first execution of this protocol hit the very first box,
      > got 16 including findings fixed hours earlier, and overrode it. That is the honest
      > outcome and it is also proof a gate nobody can evaluate is worse than none: it launders
      > "we ignored it" into "we checked". Three review rounds on this document did not find
      > that. Running the first checkbox did.
- [ ] `git rev-parse HEAD` recorded. The SHA is the kit version, not the tag.

**The instruments** — an unmeasured trial is worse than none, because it looks like a result.

- [ ] **Spend capture is live.** Run one throwaway agent, then
      `sqlite3 .project/index.db "SELECT COUNT(*) FROM spend;"`. A zero here means the hooks are
      not firing and **the entire cost half of the trial will be empty**. This is not
      hypothetical: the kit's own repository recorded **0 spend rows across 12 days** of heavy
      use, and `kit-status.sh` skips the cost section silently when the table is empty, so
      nothing announces it.
- [ ] **Findings capture is live.** Run one reviewer through `kit-review-record.sh` and confirm
      a row lands. A review that records nothing is indistinguishable from a review that found
      nothing (§3).
- [ ] `kit-index.sh` and `kit-status.sh` both run clean on the copy.

**The subject**

- [ ] **A COPY or a clone with its remote removed** — §4, the rule with the least room for
      judgement.
- [ ] **Baseline recorded before the kit touches anything**: does the subject build, do its
      tests pass, how long do they take. A subject whose tests already fail is a valid trial
      subject, but only if you knew that first — otherwise the kit gets blamed for it.
- [ ] The subject's owner has agreed, if that is not you.

**The trial**

- [ ] **The question is written down.** "Try the kit on X" is not a question. "Does the
      co-change graph produce a usable ordering on a repo with four years of history" is.
- [ ] **Time-box stated**, in hours, before starting.
- [ ] **Stop rules stated.** Stop and record what you have when: the time-box expires; the same
      kit defect blocks progress three times; or any VOID condition (§3) is hit.
- [ ] **Abort path stated.** If the kit crashes or corrupts state mid-trial, the trial is
      recorded as aborted at that point with the cause — it is never silently restarted, because
      a restarted trial has a contaminated index and is no longer comparable.

---

## 1. The unit

**Billing-weighted input-token-equivalents (BTE).** One number, four counters:

    input×1 + cache-write×1.25 + cache-read×0.1 + output×5

**Never retype those weights.** They have one home — `BTE=` in `tooling/kit-status.sh` — and a
conformance step asserts this document still agrees with it. Read them from that home:

```sh
W=$(sed -n 's/^BTE="(\(.*\))"/\1/p' tooling/kit-status.sh)
```

**What the kit emits, and what it does not.** `kit-status.sh` reports BTE grouped by **tier,
scope, provenance and model**. It does **not** emit a per-agent figure. Revision 1 mandated
per-agent BTE anyway, which made two of its own rules jointly unsatisfiable. The `spend` table
does carry an `agent` column, so the number is one query away — and this form takes the weights
from their one home rather than duplicating them:

```sh
sqlite3 -column .project/index.db "
  SELECT COALESCE(NULLIF(s.agent,''),'(main loop)') AS agent,
         COUNT(*) AS transcripts, SUM($W)/100000 AS kBTE
    FROM spend s GROUP BY 1 ORDER BY 3 DESC;"
```

**Where the counters come from.** `kit-spend.sh` writes them from the `SubagentStop` and `Stop`
hooks — nobody types it, which is why §0 checks the hooks are live rather than trusting them.
Its `--transcript` flag is the manual door if you are reconstructing a run after the fact.

**Do NOT use the harness's per-agent completion summary.**
That figure is each agent's **final context size**, not its cost.
Reconciled across a 105-subagent run it matched summed last-context to 0.012% while differing
from actual output work by **5–215×**. It is a fair measure of context carried and a worthless
measure of money. The first trial's headline table is in that wrong unit and says so; do not
reproduce the mistake by copying its shape.

**Record raw counters alongside the weighted total.** Weights are a pricing assumption and
pricing changes; raw counters can be re-weighted later, a weighted total cannot be undone.

---

## 2. Constant, varied, recorded

### Constant WITHIN a trial

Changing any of these mid-trial voids it: the kit SHA, the agent set and each agent's
capability, the profile (`tier.rule`, `commands.*`, `ingest.*`, `accelerator.*`), and whether
accelerators are loaded.

`commands.*` and `tier.rule` must be **authored per subject** — a Rust monorepo has different
test commands from a TypeScript one. Author them during pre-flight, record them verbatim in the
report, and do not touch them again once the trial starts.

### Constant ACROSS trials — the part that makes comparison legitimate

This is the section revision 1 was missing entirely, and without it the document fixed a
procedure that produced incomparable results.

| Must match across compared trials | Why |
|---|---|
| the BTE definition | a different unit is a different measurement |
| the agent set and capabilities | the cost question is about these agents |
| the tier vocabulary and floors' *shape* | floors differ per subject; the ladder must not |
| what counts as an escape | the escape rate is otherwise not one number |
| the report template (§7) | a figure not in both reports cannot be compared |

**The kit SHA will differ between trials, and that is unavoidable** — §7 requires filing and
fixing the defects each trial finds. So "vary one thing per trial" is false as stated, and
revision 1 stated it. The honest rule: **the subject is the variable; the kit moves anyway.**
Record both SHAs and diff them, and when a figure moves, say plainly that either the subject or
the kit could account for it. A two-trial difference is a hypothesis, not a finding.

### Record every time

| | |
|---|---|
| kit commit SHA | the exact tree that ran, both trials when comparing |
| subject | language mix, size, commit count, age of history |
| greenfield or brownfield | and whether history was truncated |
| BTE by tier / scope / provenance / model | what `kit-status.sh` emits |
| BTE by agent | the query in §1 |
| raw counters | so the weighting can be redone |
| verdict per reviewer | and whether a second was genuinely blind (§3) |
| findings per agent | class, severity, summary, via `kit-review-record.sh` |
| findings **rejected** by the recorder | the `finding-gap` rows, with reasons |
| escape rate by tier | over both provenance populations |
| wall-clock and API time | separately |
| **n** | on every figure, in the figure |

**Tool-use counts are not currently obtainable.** Revision 1 asked for them and asserted a
five-use threshold, and no tool in the kit counts tool uses. If your harness reports them,
record them and say which harness; otherwise record that they were unavailable rather than
leaving a column that looks unmeasured.

---

## 3. What makes a trial VOID — and how to detect each

Each of these produced a wrong answer on a real run. A trial that hits one is not a weak
result — it is **no result**. Revision 1 stated the conditions without saying how to notice
them, which made three of five undetectable in practice.

| Condition | Detection you can actually run |
|---|---|
| **A worktree path in a prompt does not isolate a subagent.** Both agents in one comparison found and read the live repository; one said so and reviewed that instead. | Grep the agent's own reply and tool log for paths outside the worktree root. If the harness does not expose a tool log, a blind comparison cannot be validated — say so and do not claim one. |
| **Registering a finding contaminates every later blind run.** | `sqlite3 … "SELECT COUNT(*) FROM finding WHERE at < '<worktree commit date>'"` — the worktree must predate every row you are hiding. |
| **Reindexing before committing** showed `T2 0/8` and nearly produced a report that the escape mechanism was broken. | Run `git status --short` before `kit-index.sh`; a non-empty tree means the index you are about to read is early. |
| **A permission denial inside a subagent degrades into a partial read.** | Check the tool log for denials. An agent that discloses one is salvageable; assume an undisclosed denial happened if its tool count is far below its peers on the same task. |
| **A reviewer that returns nothing may not have reviewed nothing.** An empty `{"findings":[]}` records as `reason=empty` — *"looked and found nothing"*. | `sqlite3 … "SELECT reason, COUNT(*) FROM … kind='finding-gap' GROUP BY 1"`. Any `rejected` row is a review whose findings were lost. Confirm the reviewer received a prompt before believing any zero. |

**A VOID trial is still recorded** — as `docs/TRIALS/<date>-<subject>-VOID.md`, naming the
condition hit and what had been established before it. Discarding it silently is the same
failure as an unrecorded empty review: the next person repeats it.

---

## 4. Isolation — what a trial must not do to the subject

The subject projects are real work. The operator's condition, and it decides the method rather
than qualifying it: **do not destabilise them.**

**The copy must have no path back.** Revision 1 said "a copy or a read-only clone" and was
rejected on it: `git clone` leaves `origin` pointing at the subject, and `git push` is a **Bash**
invocation, which the guard hook does not match (below). Do this instead:

```sh
git clone --no-hardlinks <subject> <copy>
cd <copy>
git remote remove origin
git remote -v          # MUST print nothing. If it prints anything, stop.
```

`--no-hardlinks` because a hardlinked object store shares files with the subject. Verify the
remote is gone before any agent runs; that command is the control, not the intention.

**What is enforced and what is not.** `hooks/hooks.json` matches `Write|Edit|NotebookEdit`, so
the guard blocks those outside the project root. **It does not see Bash at all** — no `git push`,
no `rm`, no redirect. So non-destructiveness is a procedure *you* enforce; the removed remote is
what makes the procedure hold when the guard cannot.

**Hooks go in the copy, never the subject.** Revision 1 banned hooks in the subject while
requiring every metric that `kit-init.sh` produces, and `kit-init.sh` installs `commit-msg` and
`pre-push` and edits `.gitignore` — so the document forbade what it required. The resolution is
that **the copy is not the subject**: run `kit-init.sh` there and let it install whatever it
installs. Nothing is ever installed into the subject.

**Everything the trial produces for the subject is a proposal** — files for review, never
applied, never pushed.

---

## 5. Attribution

A trial that cannot separate kit work from other work produces numbers nobody can interpret
later.

- Every task the trial touches carries `kit`, `agent`, `manual`, or `unknown`.
- **`unknown` is the honest default** for pre-existing work and is load-bearing on brownfield,
  where most of the backlog predates adoption. Recording it is not a failure; guessing is.
- **Back-fill uses the lowercase `via:` frontmatter key.** `Via:` is the git trailer and a
  commit already written cannot gain one.
- **Precedence: a `Via:` trailer beats the frontmatter `via:`.** The derivation takes the last
  `via` event by sequence and falls back to frontmatter only when there is none — so a
  back-filled value is silently overridden by any later trailer on that task. If you back-fill
  and then commit against the same task, state which value you intended.
- Provenance is set by the operator, never by the agent that did the work.
- **Run one task at a time.** Spend attribution binds a transcript to the task whose transition
  follows it; with two tasks in flight it can bind to the wrong one, and the resulting cost
  figures are wrong in a way nothing detects afterwards.
- Report escape rate over **both** populations. If `via:kit` has no denominator, the report says
  so — zeroes shaped like a rate are not a result.

---

## 6. Reporting

**State n on every figure**, next to the number, not in a preamble. A figure whose n is
elsewhere gets quoted without it.

**Never generalise across subjects without saying so.** One greenfield TypeScript run is not a
rate card for a polyglot Rust monorepo.

**Every number in the report needs a source.** Revision 1 asserted a five-tool-use threshold and
a "4× divergence" between wall-clock and API time, neither with a derivation or an n — breaking
this document's own rule three sections later. If a number came from one session, say so and
give the n; if it came from nowhere, delete it.

**Report what was NOT exercised.** The first trial's most useful section lists what it never
touched. An untested component named as untested is information; one omitted reads as fine.

**Separate three kinds of finding**, because they have different lifetimes:

1. defects **in the kit** → tasks here
2. defects **in the subject** → the subject owner's, delivered as a proposal
3. **methodology** failures → §3 of this document

**Disputed findings.** Where the subject's owner disagrees that a finding is real, record it as
disputed with both positions and do not resolve it in the trial report. The trial measures
whether the kit *produced* the finding; whether it is correct is the owner's call.

**A trial that found nothing is a result**, and is recorded as one, including which parts of the
kit ran and produced no output.

---

## 7. After the trial

- [ ] Every kit defect filed as a task **before** any of them is fixed.
- [ ] Methodology failures added to §3 **with their detection**, not just their story.
- [ ] Results committed as `docs/TRIALS/<date>-<subject>.md` using the template below —
      `docs/TRIALS/TEMPLATE.md`. A shape each trialist invents is a shape nothing can compare.
- [ ] What the trial could not test, listed explicitly.
- [ ] The copy deleted, or kept and named as contaminated.

### Report template

```markdown
# Trial: <subject> — <date>

Question:              <the one written at pre-flight>
Kit SHA:               <sha>        Time-box: <hours>    Actual: <hours>
Subject:               <languages, size, commits, age>   Greenfield/brownfield: <which>
Outcome:               COMPLETE | ABORTED (<cause>) | VOID (<condition>)
Baseline before kit:   build <pass/fail>, tests <pass/fail>, <duration>

## Cost            (n on every figure)
BTE by tier / scope / provenance / model — from kit-status.sh
BTE by agent — from the §1 query
Raw counters
Wall-clock vs API time

## Findings
By agent: class, severity, summary
Rejected by the recorder (finding-gap rows, with reasons)
Escape rate by tier, both provenance populations

## Which brownfield degradations bit
Over-tiering from an empty edge table · co-change usable or withheld · planner ordering on a
backlog it did not author

## Three kinds of finding
Kit defects (filed as tasks) · subject defects (proposal) · methodology (into §3)

## Not exercised
## Disputed
```

---

## Provenance of this document

Written 2026-08-12 before the first brownfield trial, from the greenfield run of 2026-08-01
(`docs/MEASUREMENTS.md`). §3 is that run's "Methodology warnings" promoted from narrative into
procedure, plus detections. The empty-review rule in §3 and the empty-denominator rule in §5
come from defects found in the kit's own review loop, not from a trial.

Revision 2 incorporates a T2 review that found 20 defects **before first use**, including the
two criticals named at the top. That review cost one agent run and would otherwise have been
paid for by a trial on a client codebase.

**This protocol is n=0.** It has never been executed. Its first execution is
`T-20260808-trial-the-kit-on-one-unfamiliar-brownfie`, which is also its first real test, and
the expected outcome is that this document changes again.
