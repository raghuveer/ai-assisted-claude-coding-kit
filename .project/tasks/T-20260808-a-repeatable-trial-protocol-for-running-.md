---
id: T-20260808-a-repeatable-trial-protocol-for-running-
title: A repeatable trial protocol for running the kit on an unfamiliar project
epic: validation
tier: T2
paths: docs/TRIAL-PROTOCOL.md, docs/MEASUREMENTS.md
state: open
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
