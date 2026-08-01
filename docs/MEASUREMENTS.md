# Measurements — greenfield run, 2026-08-01

First run of the kit with the model in the loop. Recorded because the defect tasks it
produced are in the backlog but the evidence behind them was not, and without the numbers
those tasks are assertions.

## Read this first

**n=1 per cell**, except tier stability which is n=2.

**The whole sample is the kit's worst case.** Greenfield, no history, no accelerators — so
the co-change graph and the planner never had anything to work with. The defects are real
regardless; the cost figures must not be generalised to a brownfield repository without
rerunning there.

Subject: a TypeScript RAG platform. Approved 46KB ADR, 23 review findings imported as a
backlog, **zero lines of code at start**.

## A. What was measured

| agent | model | tokens | tools | verdict | findings | vocab valid |
|---|---|---|---|---|---|---|
| coder (scaffold, T2) | sonnet | 115,567 | 75 | — | — | — |
| implementation-reviewer | sonnet | 104,769 | 45 | REVISE | 4 | 1/4 |
| researcher (F6, T3) | opus | 51,408 | 30 | — | — | — |
| approach-reviewer | opus | 70,966 | 19 | REJECT | 18 | 18/18 |
| security-reviewer, **blind** | opus | 73,686 | 19 | REJECT | 17 | 17/17 |
| approach-reviewer | sonnet | 59,373 | 20 | REVISE | 9 | 0/9 |
| approach-reviewer | haiku | 42,159 | 5 | REJECT | 8 | 0/8 |
| implementation-reviewer | opus | 89,716 | 50 | REVISE | 11 | 11/11 |
| implementation-reviewer | haiku | 62,408 | 58 | REJECT | 1 | 0/1 |
| tier-classify ×6 | sonnet | 239,947 | 38 | — | — | — |

## B. Defects in the kit

### 1. Reviewers cannot run the tools their instructions require — *partly fixed*

All three reviewers are `tools: Read, Grep, Glob` and all three were told to run
`kit-finding.sh --vocab`. Unexecutable in every one.

`implementation-reviewer` also has no git, so on an uncommitted change it cannot diff. It
reviewed the whole tree and read the operator's `.claude/settings.local.json` to
reverse-engineer what the coder had run. Its top required change was "independently confirm
the commands run" — unresolvable by construction, and it recurs on every run where it
matters.

**Fixed at `309aa63`:** the vocabulary is inlined and `tests/conformance.sh` asserts no
Bash-less agent is told to run a script.

**Not fixed:** the toolset. Implementation review is an execution task carrying a reading
toolset. 45 tool uses against `approach-reviewer`'s 19 is the tell — design review is a
reading task and the grant fits; implementation review is not and it does not.

### 2. Nothing invokes `kit-finding.sh` — the loop is open circuit

The findings table held **zero rows** across a project that had run two reviews. Agent files
say findings "are piped straight into `kit-finding.sh --batch`"; nothing does the piping. 36
rows appeared once piped by hand. An escape rate reading `T3 0/13` meant *nothing recorded*,
not *nothing escaped*, and the output cannot distinguish them.

### 3. Vocabulary compliance tracks MODEL TIER, not agent identity

Same agent, same prompt, only the model varied:

| | valid |
|---|---|
| opus | 18/18, 17/17, 11/11 |
| sonnet | **0/9** — `design-gap`, `unverified-claim`, `scope-creep`, `missing-alternative` |
| haiku | **0/8** — `assumption`, `design`; and it appended prose after the fourth pipe field, breaking the batch format outright |

The opus agents could not run `--vocab` either. They **located and read `kit-finding.sh`
from source**. The tiers below invented plausible class names instead.

`MODELS.md` pins `coder`, `implementation-reviewer`, `tester` and `adr-scribe` to sonnet —
"the working tier, most of the volume". So the agents producing most of the review volume
could not produce an ingestible finding.

**The consequence is what makes this severe:** fix the plumbing alone and the table fills
with opus-tier findings *only*, and looks like it is working. Accelerators would then be
derived from design review exclusively, with implementation review silently absent.

**Open question, and the sharpest one remaining.** This test ran against the *pre-inlining*
agents — the evidence is that opus worked around the gap by reading the script, which it
would not need to do if the list were in its instructions. Since `309aa63` the vocabulary is
in the agent text. **Whether that fixes sonnet and haiku is untested**, and the two outcomes
have opposite implications:

- if inlining fixes it, this was a reachability problem and is closed
- if it does not, lower tiers do not attend to a list in front of them, and the fix has to
  be validation-and-correction at the recording step rather than instruction

Retesting this is cheap and it gates whether defect 2 can be closed honestly.

Also: no class exists for test-coverage or verification defects, so reviewers invent one.
Any fix must **reduce** the number of places the vocabulary lives — it already drifted
across four locations once.

### 4. Nothing validates a recorded tier against its own `tier.rule` floors

Three tasks, two independent classifiers each, cold:

| task | recorded | run A | run B |
|---|---|---|---|
| cache invalidation epoch | T2 | **T3** | **T3** |
| liveness/readiness split | T1 | **T2** | **T2** |
| nonce store | T3 | T3 | T3 |

Classifier **stable** — 3/3 pairwise. Recorded tiers **not** — 2 of 3 too low, because the
backlog was tiered from finding *severity* and never checked against floors.

The classifiers could see the recorded tier and overrode it anyway, so anchoring biased
against this result and it held. Both floors and task tiers are already in the index: this
is a query, not a new mechanism.

### 5. `kit-plan.sh` has no notion of prerequisite work on greenfield

22 tasks collapsed to 2 layers (20 + 2). The scaffold task — which everything else needs in
order to be verifiable at all — ranked **eleventh**, behind ten T3s. Two declared
`blocked_by` edges total, and the co-change graph was empty because there is no history.

Score is effectively a proxy for tier, so the plan says "do the riskiest work first" exactly
when `verify-ladder` reports its rungs unavailable. **Greenfield is this planner's worst
case and that is not in the known limits.**

### 6. Trailer-discipline warning counted commits the hook exempts — *fixed at `e7dd860`*

`git.trivial_pattern` was read only by `kit-trailers.sh`. `kit-index.sh` counted every commit
as untagged and `kit-status.sh` divided by every commit. Real case: 8 commits, 5 `chore`/`docs`
the hook deliberately waved through, 3 non-trivial all correctly tagged — reported as "4 of 8
carry no `Task-Id`".

A warning that never turns off is one people stop reading, and this one guards the signal
escape-rate-by-tier depends on.

Fix: `kit-index.sh` reads the same key and tracks `commits_exempt`; `kit-status.sh` divides
by total-minus-exempt and names the excluded count. Exempt commits still have their trailers
indexed — only the counters differ. A stale index reads 0 and degrades to the old
denominator rather than a wrong one. Deliberately **not** widened to `Revert`/`fixup!`/
`squash!`, which `kit-trailers.sh` also exempts and this counter still counts.

### Smaller

`kit-guard.sh` blocks the Write tool outside the project root but not Bash writes.
`kit-task.sh` created files cross-root without tripping it.

## C. Both cost questions answered — against the cheap option

### Is T3's second reviewer redundant? **No.**

`approach-reviewer` and `security-reviewer` — the second blind, in a worktree at a commit
predating the first's findings — both returned REJECT and shared roughly 70% of findings.

The other 30% is the whole value:

- **only security:** `hash()` unpinned, and `hash(question+filters)` has an ambiguous
  pre-image, so a same-tenant attacker can construct a colliding question and poison or read
  a victim's cached answer; `tenantId` unbranded in the domain ports; invalidation inherits
  degrade-to-no-op, so a failed invalidation ACKs the ingest
- **only approach:** the port set has no invalidation method at all; the alternative-D
  comparison was never fairly run; no per-layer hit-rate metric; epoch keyspace growth;
  `render()` golden-file test; cold-cache stampede

**It is a completeness control, not a correctness control.** Same verdict either way. The
phrase "independent second reviewer" reads as redundancy insurance, which is exactly what
makes it look cuttable. `verify-ladder` now says what it actually buys.

### Is the opus pin earned? **Yes.**

- **haiku missed the critical security finding entirely** — 5 tool uses against 19–20. It
  reviewed the prompt, not the repository, despite being told not to trust the design's own
  characterisation.
- **sonnet found the leak and still returned REVISE.** A calibration failure rather than a
  knowledge failure, and the more dangerous kind: REVISE means fix-and-continue, REJECT means
  redesign. The agent file says "bias toward rejection".
- **Only opus caught the self-refuting rejection** — the design killed alternative B over a
  read-modify-write race, then handed `MemoryAdapter` that same race via composed defaults.

A 16% saving costs a softened verdict plus every recordable finding. 41% costs the security
finding.

## D. Methodology warnings for whoever repeats this

- **A worktree path in the prompt does not isolate a subagent.** On the
  implementation-reviewer tier test both agents found and read the live repo; opus said so
  explicitly and reviewed it instead. **That comparison is void.** The design-rung blind
  tests held only because the worktree was checked to contain no trace of the earlier
  findings.
- **Reindex after committing.** Running `kit-index.sh` before `git commit` in the same chain
  showed `T2 0/8` and nearly produced a report that the escape mechanism was broken.
- **Registering a finding contaminates any later blind run.** Use a worktree at a commit
  predating the registration.
- **Permission denials inside subagents degrade into partial reads.** `security-reviewer` was
  denied Read on a task file, recovered via Grep, and disclosed it.

## E. What the kit caught that was worth the money

- `coder`'s 11-item unstated-decisions list caught that `typescript-eslint` peer-caps
  TypeScript at `<6.1.0`, so pinning TS 7 would have silently broken typed linting.
- `coder` **refused to invent a fake `ladder.rung5` command**, citing the kit's own
  precedent, rather than write theatre.
- **Two High security findings absent from a 28-item review register**, both confirmed
  against the ADR before being recorded:
  - **F29** — the semantic cache is not scoped by classification set. F3 re-keyed the exact
    cache and left `rag:semcache:{tenantId}` with no role filter, so an admin's answer drawn
    from restricted chunks is served to a `credit_analyst` who paraphrases. More exploitable
    than F18: that needs a UUID guess, this needs a synonym.
  - **F30** — `sessionId` is body-supplied and used unvalidated as a key segment, with no
    ownership check specified anywhere.
- **`implementation-reviewer` on opus found two escapes in work that had already passed the
  sonnet review and been committed:**
  - `ladder.rung3` named a command that exits 0 over an empty directory and always would —
    `passWithNoTests` was set in `vitest.config.ts`, not only in the npm script, so removing
    the visible flag would not have closed it. The profile then reported rung 3 **available**
    and every task was reviewed one rung shallow.
  - `KEY_LINE` could not match a YAML list item, so the first key of every `connectors[]`
    entry was skipped — and ADR §13 defines connectors as a sequence of mappings, making the
    one credential-bearing structure the one shape the fail-closed branch could not see.

  Both were filed before fixing, so the escape recorded. **T2 escape rate is now 1/7 — the
  first real datum this measurement has produced.**
- Fixing those surfaced two more that appeared only once the rule ran on a real file — the
  argument for fail-closed-on-zero-input, demonstrated in minutes: `max_tokens` flagged as a
  secret by substring match on "token", and the `*_ref` message **echoed the credential it
  found** into build output and, per the ADR's Graylog stack, into a log aggregator.

## F. Still untested

`tester` (never run) · a real REVISE/REJECT second round (both short-circuited by hand) ·
context economics (13 cluster packs generated, read by nothing) · brownfield, where the
co-change graph is not inert · accelerators (commented out) · **whether inlining the
vocabulary fixes sonnet and haiku compliance** (see defect 3).

**Cannot be tested in a session:** escape rate as a *hypothesis* — whether tier correlates
with defects escaping. That needs escapes accumulated over time. What can be validated now is
that the apparatus works, and **two of its three parts were broken when first touched**.
