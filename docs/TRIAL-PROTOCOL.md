# Trial protocol

How to run the kit against a project it has never seen, so that two trials can be compared.

**This is a procedure, not a report.** You should be able to execute it without having read
`docs/MEASUREMENTS.md`. That document is the first trial's *results*, and it is cited here only
where a rule exists because something went wrong there.

The procedure is fixed **before** a trial, not reconstructed after it. A comparison assembled
afterwards from whatever each run happened to record is not a comparison.

---

## 0. Before you start: is this trial allowed?

Stop unless all four hold.

- [ ] **The kit is in a state you would defend.** Working tree clean, full conformance green,
      CI green on every platform, and no task at `progress` carrying an unfixed critical. A
      trial run from a broken kit measures the breakage.
- [ ] **The subject is a COPY or a read-only clone.** Never the working repository. See §4 —
      this is the rule with the least room for judgement.
- [ ] **You know what question this trial answers.** "Try the kit on X" is not a question.
      "Does the co-change graph produce a usable ordering on a repo with 4 years of history"
      is. Write it down before the first command; the temptation to discover the question in
      the results is exactly how n=1 becomes a rate card.
- [ ] **The subject's owner has agreed**, if that is not you.

---

## 1. The unit

**Billing-weighted input-token-equivalents (BTE).** One number, four counters:

    BTE = input×1 + cache-write×1.25 + cache-read×0.1 + output×5

Read the four counters from the **per-agent transcripts** — `kit-spend.sh` records them raw,
per agent, and `kit-status.sh` computes the weighting from one definition. Never retype the
weights; if you find yourself typing `1.25` into a spreadsheet, you have made a second
definition that will drift.

**Do NOT use the harness's per-agent completion summary.**
That figure is each agent's **final context size**, not its cost.
Reconciled across a 105-subagent run it matched summed last-context to 0.012% while differing
from actual output work by **5–215×**. It is a fair measure of context carried and a worthless
measure of money. The first trial's headline table is in that wrong unit and says so; do not
reproduce the mistake by copying its shape.

**Record raw counters alongside the weighted total.** Weights are a pricing assumption and
pricing changes; raw counters can be re-weighted later, a weighted total cannot be undone.

---

## 2. What to hold constant, what to vary, what to record

**Hold constant** — changing any of these mid-trial voids the comparison:

- the kit version (record the commit SHA, not the tag)
- the tier of each task, and who assigned it
- the agent set, and which capability each agent runs at
- the profile: `tier.rule` floors, `commands.*`, `ingest.*`, `accelerator.*`
- whether accelerators are loaded at all

**Vary one thing per trial.** A trial that changes the subject *and* the agent set answers
nothing about either.

**Record, every time, without exception:**

| | |
|---|---|
| kit commit SHA | the exact tree that ran |
| subject | language mix, approximate size, commit count, age of history |
| greenfield or brownfield | and if brownfield, whether history was truncated |
| per-agent BTE | plus the four raw counters |
| tool-use count per agent | a review with 5 tool uses did not read the repository |
| verdict per reviewer | and whether the second was genuinely blind (§3) |
| findings per agent | with class and severity, via `kit-finding.sh --json` |
| vocabulary compliance | findings the recorder accepted ÷ findings emitted |
| escape rate by tier | over both provenance populations |
| wall-clock | separately from API time; they diverge by 4× and mislead differently |
| **n** | on every figure, in the figure, not in a footnote |

---

## 3. What makes a trial VOID

Each of these produced a wrong answer on a real run. A trial that hits one is not a weak
result — it is **no result**, and reporting it as a weak one is worse than not running it.

**A worktree path in a prompt does not isolate a subagent.** Both agents in the
implementation-reviewer comparison found and read the live repository — one said so explicitly
and reviewed that instead. **Void.** Isolation is a property of what the agent can reach, not
of what the prompt says. Check the worktree contains no trace of what you are hiding, and
check afterwards which paths the agent actually read.

**Registering a finding contaminates every later blind run.** Once a finding is in the table,
a "blind" reviewer can find it there. Run blind comparisons from a worktree at a commit
**predating the registration**.

**Reindex only after committing.** Running `kit-index.sh` before `git commit` in the same chain
showed `T2 0/8` and nearly produced a report that the escape mechanism was broken. The
mechanism was fine; the reader was early.

**A permission denial inside a subagent degrades into a partial read.** One reviewer was denied
Read on a task file, recovered via Grep, and disclosed it — the disclosure is what made the run
salvageable. Assume an undisclosed denial is a partial read, and check the tool log rather than
the reply.

**A reviewer that returns nothing has not necessarily reviewed nothing.** An empty
`{"findings":[]}` records as `reason=empty`, which means *"looked and found nothing"*. If the
reviewer never received the request — a retry that dropped it, a prompt file that did not
exist — that row is a lie. Check `finding-gap` reasons before treating any zero as evidence.

---

## 4. What a trial must NOT do to the subject

The subject projects are real work. The operator's condition, and it decides the method rather
than qualifying it: **do not destabilise them.**

- **Run against a copy or a read-only clone.** Nothing writes into the subject's own history
  until a human has read the inventory and said so.
- **First pass is read-only in intent**: read the project, produce a task inventory and a
  report. No commits, no branches, no hooks installed in the subject.
- **Be honest about what enforces that.** `kit-guard.sh` blocks Write outside the project root
  but **not Bash writes**. So non-destructive is a procedure *you* enforce, not a property the
  kit guarantees. Until that gap closes, the copy is the control — not the guard.
- **Anything the trial produces for the subject is a proposal**, delivered as files for review,
  never applied.

---

## 5. Attribution

A trial that cannot separate kit work from other work produces numbers nobody can interpret
six months later.

- Every task the trial touches carries a provenance value: `kit`, `agent`, `manual`, or
  `unknown`.
- **`unknown` is the honest default** for pre-existing work, and it is load-bearing on a
  brownfield subject where most of the backlog predates adoption. It is not a failure to record
  it; it is a failure to guess instead.
- Back-fill uses the lowercase **`via:`** frontmatter key. `Via:` is the git trailer, and a
  commit already written cannot gain one.
- Provenance is set by the operator, never by the agent that did the work.
- Report escape rate over **both** populations side by side — `via:kit` and `all`. If the
  `via:kit` column has no denominator, say so; zeroes in the shape of a rate read as a clean
  result and are not one.

---

## 6. Reporting

**State n on every figure.** Not in a preamble, not in a footnote — next to the number. A
figure whose n is elsewhere gets quoted without it.

**Never generalise across subjects without saying so.** The default posture is that a figure
describes the project it came from. One greenfield TypeScript run is not a rate card for a
polyglot Rust monorepo, and the existing measurement says so about itself.

**Report what was NOT exercised.** The first trial's most useful section is the one listing what
it never touched. An untested component reported as absent is information; the same component
reported as nothing at all reads as tested-and-fine.

**Separate three kinds of finding**, because they have different lifetimes:

1. defects **in the kit**, which become tasks here
2. defects **in the subject**, which belong to the subject's owner
3. **methodology** failures, which come back into this document

**A trial that found nothing is a result**, and must be recorded as one — including which parts
of the kit ran and produced no output. Silence is how an empty finding table came to read as
"nothing escaped".

---

## 7. After the trial

- [ ] Every kit defect filed as a task, **before** any of them is fixed. Filing after fixing is
      how the escape record stops being real.
- [ ] Methodology failures added to §3 of this document, with the evidence.
- [ ] The results committed as `docs/TRIALS/<date>-<subject>.md`, in the shape above, so the
      next trial is comparable rather than merely similar.
- [ ] What the trial could not test, listed explicitly.

---

## Provenance of this document

Written 2026-08-12, before the first brownfield trial, from the greenfield run of 2026-08-01
(`docs/MEASUREMENTS.md`). §3 is that run's "Methodology warnings" promoted from a narrative into
a procedure; §1's warning about the wrong unit is the reason its headline table cannot be quoted
as cost. The empty-review rule in §3 and the empty-denominator rule in §5 come from defects
found in the kit's own review loop on 2026-08-11 and 2026-08-12, not from a trial.

**This protocol is n=0.** It has never been executed. Its first execution is
`T-20260808-trial-the-kit-on-one-unfamiliar-brownfie`, which is also its first real test, and
the expected outcome is that this document changes.
