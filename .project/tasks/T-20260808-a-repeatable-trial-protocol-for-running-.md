---
id: T-20260808-a-repeatable-trial-protocol-for-running-
title: A repeatable trial protocol for running the kit on an unfamiliar project
epic: validation
tier: T2
paths: docs/TRIAL-PROTOCOL.md, docs/MEASUREMENTS.md
state: completed
---

## Intent

The intent is to try the kit periodically on projects it has never seen, and to compare the
results. Comparison needs a fixed procedure decided BEFORE the first trial, not reconstructed
after the third.

What exists is `docs/MEASUREMENTS.md`: one n=1 record of one greenfield run. It carries a
section called "Methodology warnings for whoever repeats this", which is the seed of a
protocol and is not one — the warnings are attached to a specific run's story rather than
stated as a procedure someone can follow.

## Acceptance criteria

- [x] A protocol document that a person can execute without having read the run it came from.
      What to record, what to vary, what to hold constant, and what makes a trial void.
      → `docs/TRIAL-PROTOCOL.md`, §0 gate / §2 constants and record / §3 void.
- [x] The unit is fixed and stated: billing-weighted input-token-equivalents (input x1,
      cache-write x1.25, cache-read x0.1, output x5), from the per-agent transcripts. NOT the
      harness's per-agent figure, which is final context size and differed from actual output
      work by 5-215x on a measured run. `docs/MEASUREMENTS.md`'s own table is in the wrong unit
      for exactly this reason and says so.
      → §1, and **conformance-checked in both directions**: the weights are read out of
      `kit-status.sh` rather than retyped in the test, so the prose and the code cannot drift
      apart silently. Three mutations prove it — code drifts, prose drifts, warning deleted.
- [x] The known-void traps are promoted out of the 2026-08-01 narrative into the procedure:
      - a worktree path in a prompt does NOT isolate a subagent; both agents found and read the
        live repo, and that comparison was void
      - reindex AFTER committing, or the escape mechanism reads as broken
      - registering a finding contaminates any later blind run; use a worktree at a commit
        predating the registration
      - permission denials inside a subagent degrade into partial reads
- [x] It says what a trial must NOT do to the subject project. See the trial task's constraint:
      these are real codebases and the kit is not to put them in an unstable state.
      → §4, and it names which half is enforced: the `kit-guard.sh` hook matches
      `Write|Edit|NotebookEdit` — **verified, Bash is genuinely absent from the matcher** — so
      the copy is the control and non-destructiveness is a procedure, not a guarantee.
- [x] It says how work done during the trial is attributed, which is
      T-20260808-record-how-a-task-was-executed-so-kit-wo. A trial that cannot separate kit
      work from other work produces numbers nobody can interpret later.
      → §5, including that `unknown` is the honest default on brownfield, the lowercase
      `via:` frontmatter key for back-fill, and reporting over both populations.
- [x] n is stated on every figure it produces, and a figure from one project is never
      generalised to another without saying so. The existing measurement is n=1 on greenfield
      and is explicitly not a rate card; the protocol must make that the default posture
      rather than a caveat someone remembers to add.
      → §6. The document also declares its own **n=0**.

## Built 2026-08-12

`docs/TRIAL-PROTOCOL.md`. Two rules in it come from defects found in the kit's own review loop
rather than from the greenfield run, because they are the same failure the trial would produce:
an empty `{"findings":[]}` records as *"looked and found nothing"* when the reviewer may never
have received the request (§3), and an empty `via:kit` denominator prints zeroes in the shape of
a rate (§5). Both would have corrupted a trial's headline numbers.

**Not closed.** T2 needs an adversarial reviewer before it is done, and this document's whole
value is that it is right before the first trial rather than after it. Its own last line says it
is n=0 and expects to change on first execution.

## T2 review (2026-08-12) — REJECTED. 20 findings, 2 critical, 10 major.

`approach-reviewer` (opus), through `kit-review-record.sh`, accepted first attempt. Reviewed as
a **procedure** — can someone who never saw the greenfield run execute this and get a comparable
result — which is the right question and the one the document fails.

Both criticals reproduced by hand before recording.

### CRITICAL 1 — the safety measure has a hole (`§4`)

"Run against a copy or a **read-only clone**" is the rule protecting real client codebases. A
clone keeps `origin` pointing at the subject, and **`git push` is a Bash call** — the guard hook
matches `Write|Edit|NotebookEdit` only, which §4 itself points out. Nothing in the protocol
removes the remote. The one section whose job is "do not damage the subject" leaves the wire to
the subject connected.

### CRITICAL 2 — §1 and §2 are jointly unsatisfiable

§2 mandates recording **per-agent BTE**. §1 forbids retyping the weights by name. Verified:
`kit-status.sh` groups BTE by tier, scope, via and model — **never by agent**. So there is no
per-agent figure to read, and a trialist must either break §1 or fail to record what §2
requires. Two rules that cannot both be obeyed is worse than either rule missing.

### The majors, and the pattern in them

Most are **absent procedure rather than wrong procedure**, which is what a first execution would
have discovered expensively:

- no time-box, stop rule, mid-trial abort, what-if-the-subject's-tests-already-fail path, or
  dispute arbitration anywhere in §0–§7
- §4 bans hooks in the subject, but every §2 metric needs `kit-init.sh`, which installs
  `commit-msg`/`pre-push` and edits `.gitignore` — **the protocol forbids what it requires**
- §7 demands `docs/TRIALS/<date>-<subject>.md` "in the shape above" with no template and no such
  directory, so every trialist invents a different shape and comparability dies at the artefact
- the document fixes what is constant **within** a trial and never states what must match
  **across** trials for a comparison to be legitimate — which is the entire purpose
- **three of five VOID conditions state no detection a trialist can run**, so a trial can hit one
  and never notice. That is §1-of-LESSONS applied to my own document: a rule nobody can be shown
  to have broken is decoration.
- "Vary one thing per trial" is falsified by §7: filing and fixing kit defects changes the SHA,
  so by trial 2 both subject and kit have varied
- no pre-flight that spend capture is live — `kit-spend.sh` exits 0 silently, so a trial can run
  to completion with no counters at all
- frontmatter `via:` is silently overridden by any `Via:` trailer; §5 omits the precedence
- `kit-finding.sh --json` is named as the way to get findings **out**; it is the ingest door and
  the script has no read mode
- spend attribution is a heuristic that mis-binds with two tasks in flight, and nothing requires
  one task at a time

Minors include two of my own unsourced numbers — "a review with 5 tool uses did not read the
repository" (a threshold with no derivation, and nothing counts tool uses) and "they diverge by
4×" (no n, generalising one session) — **which break the protocol's own §6 rules three sections
later.**

### Revision 2 (2026-08-12) — both criticals and all ten majors addressed

**Critical 1, isolation.** The rule is now a command, not an adjective:
`git clone --no-hardlinks`, `git remote remove origin`, then `git remote -v` **must print
nothing or you stop**. `--no-hardlinks` because a hardlinked object store shares files with the
subject. Conformance asserts both commands are still in the document, and separately asserts the
guard's matcher is still `Write|Edit|NotebookEdit` — so if the hook ever grows Bash coverage, the
sentence that justifies the removed remote stops being silently stale.

**Critical 2, the unsatisfiable pair.** The protocol now states plainly that `kit-status.sh`
emits BTE by tier/scope/provenance/model and **not** per agent. The `spend` table does carry an
`agent` column, so §1 gives the query — and it reads the weights out of `kit-status.sh` with
`sed` rather than retyping them, which satisfies the no-duplication rule instead of colliding
with it. Conformance asserts the disclaimer is present and that `spend.agent` still exists.

**The majors.** §0 is now a real pre-flight with four groups: kit state, **instruments**,
subject, trial. It requires proving spend and findings capture are live before starting —
justified by a fact found while revising: **this repository has 0 spend rows after 12 days of
heavy use**, and `kit-status.sh` drops the cost section silently when the table is empty, so
nothing announces it. A trial would have finished with no cost data and no warning.

Also: time-box, stop rules and an abort path are stated; the subject's build/test baseline is
recorded *before* the kit touches anything; §2 gained the **across-trial** constants table that
revision 1 lacked entirely; "vary one thing per trial" is replaced with the honest rule that the
subject is the variable and the kit moves anyway, so a two-trial difference is a hypothesis;
§3's five VOID conditions each carry a **detection you can run**; `docs/TRIALS/TEMPLATE.md`
exists and conformance asserts it; §4 resolves the hooks contradiction by stating that the copy
is not the subject, so `kit-init.sh` runs there; §5 states the `Via:`-beats-`via:` precedence and
requires one task at a time because spend attribution mis-binds otherwise; §6 adds disputed-
finding handling; and a VOID trial now has a filing disposition.

**My two unsourced numbers are gone** — the five-tool-use threshold and the 4× wall-clock
divergence. §2 now says tool counts are not obtainable from the kit at all, which is the fact,
rather than asking for a column nothing can fill.

**Not addressed, deliberately:** per-agent BTE should be a `kit-status.sh` mode rather than a
query pasted into a protocol. That is a kit change, not a document change, and belongs in its own
task.

## Re-review of revision 2 (2026-08-12) — REJECTED. 24 findings: 2 critical, 17 major, 5 minor.

**More findings than revision 1, not fewer** (20 → 24). The structural contradictions are gone;
what replaced them is worse in kind, and the cause is one thing.

### The meta-finding, and it is the only one that matters

**Revision 2 added executable content and guarded it with prose matching.** The conformance step
contains **six `grep -q` checks against the document's text and executes zero of the commands the
document tells a trialist to run.** So every command, query and detection I added was verified
only to be *present*, never to *work* — and the review found that four of them do not.

That is `docs/LESSONS.md` §1 at document scope: a check that cannot fail for the defect it
guards. I fixed revision 1's "conditions with no detection" by writing detections **and then
checking they existed rather than that they ran**.

### CRITICAL 1 — the isolation fix does not cover the path §0 offers

§0 line 44 still says **"A COPY or a clone with its remote removed"**. §4's control — `git remote
remove origin` then `git remote -v` — is written for the clone path only. A `cp -r` of a git
repository keeps `.git/config` and its `origin` intact, so the copy path **reopens revision 1's
critical exactly**. The fix guarded one of the two doors its own pre-flight opens.

### CRITICAL 2 — the pre-flight stops a healthy trial

§0 says: run a throwaway agent, then `SELECT COUNT(*) FROM spend`, and **zero means stop**.
Verified: `kit-spend.sh` writes to `events.ndjson`, and rows reach the `spend` table only when
`kit-index.sh` runs (`kit-index.sh:772`). So with **working hooks** the count is 0 until a
reindex — and the pre-flight aborts a trial that is fine. A false stop in the gate added to
prevent a false start.

### Majors, grouped by what they share

**Commands that do not run** (all four verified by executing them):

- §3's empty-review detection selects a `reason` column **that does not exist** — `reason` lives
  inside `event.payload` JSON. Reproduced: `no such column: reason`.
- §1's two commands root in **different repositories** — `tooling/` is the kit, `.project/` is
  the copy. Run from the copy, `$W` is empty and the `SUM()` is a SQL error.
- §1's per-agent query has **no scope filter**, which `schema.sql:119` forbids, and
  `kit-spend.sh` leaves swept subagents unlabelled.
- `SUM(...)/100000` is **SQLite integer division**, so a cheap agent reports `0`.

**Detections that cannot discriminate:**

- reindex detection fires on **every** normal mid-trial state, because build output and a
  regenerated `STATUS.generated.md` keep `git status --short` non-empty
- permission-denial detection compares **tool counts, which §2 says the kit cannot obtain** —
  unrunnable by the document's own statement, two sections apart
- blind-run detection states **no pass criterion** and compares `finding.at` against an
  unspecified git date

**Self-contradiction reintroduced:**

- **§0 mandates registering a finding during pre-flight; §3 says a registered finding
  contaminates every later blind run.** The pre-flight creates the VOID it exists to prevent.
- §7 embeds a **second copy of the report template** which already diverges from
  `docs/TRIALS/TEMPLATE.md`, while §2 requires the template to match across trials
- VOID now lives in **two places**: §2's mid-trial constant changes and §5's two-tasks-in-flight
  both void a trial and appear in neither §3 nor any detection
- **Nothing states what the trial DOES** between pre-flight and reporting, so two trials can
  satisfy every §2 constant and still run unrelated workloads

**The empty-spend fix, reviewed too:** its notice prescribes `kit-spend.sh --transcript`, which
**writes a row into the very table being measured** and flips the report. And "almost always
means the hooks were not active" is wrong for a freshly initialised project, where empty spend
genuinely means no work yet. Its comment also claims "the sixteen OTHER sections" — an uncounted
number; the countable `-gt 0` gates are 11. §3, in a comment I wrote while fixing a §3 defect.

### What revision 3 must do differently

Not "write it more carefully". **Every command in the document must be executed by conformance
against a fixture, not grepped for.** If a query cannot be run in a test, it does not belong in
a procedure — and the same applies to the pre-flight, which is a sequence of commands and should
be a script the trialist runs rather than a checklist they interpret.

### Found by operating the loop, again

`kit-review-record.sh` records the findings and **discards the `verdict` and `narrative`**: the
reply lives in a `mktemp -d` workdir that the `EXIT` trap deletes. `kit_findings.py` accepts both
fields and says the verdict "is for the human who decides whether the work closes" — and the loop
throws it away before the human sees it. The verdict for this round is unrecoverable; 2 critical
and 10 major make it REJECT regardless, but that is inference, not the reviewer's word. Folded
into `T-20260811-harden-the-review-retry-loop-against-its`.

## Notes

Requested by the operator 2026-08-08: the kit is to be tried periodically on projects it has
never been run against, and those trials are expected to produce task inventories and work
carried forward. That makes the protocol a prerequisite rather than documentation of an
already-finished experiment.

Pairs with T-20260808-trial-the-kit-on-one-unfamiliar-brownfie, which is its first execution
and its first real test.
