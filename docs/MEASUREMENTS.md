# Measurements — greenfield run, 2026-08-01

First run of the kit with the model in the loop. Recorded because the five defect tasks it
produced are in the backlog but the evidence behind them was not, and the numbers below are
the only thing that makes those tasks arguable rather than assertions.

## Read this first

**Every number is n=1** except the tier test, which is n=2 per task.

**The whole sample is the kit's worst case.** Greenfield, no history, no accelerators — so
the co-change graph and the planner never had anything to work with. The defects are real
regardless; the cost figures must not be generalised to a brownfield repository without
rerunning there.

Subject: a TypeScript RAG platform. Approved 46KB ADR, 23 review findings imported as a
backlog, **zero lines of code at start**.

## What was run

| | tokens | tools | wall |
|---|---|---|---|
| **T2 scaffold, full pipeline** | | | |
| coder | 115,567 | 75 | 28.1 min |
| implementation-reviewer | 104,769 | 45 | 7.7 min |
| | | | verdict REVISE — 2 real findings + 1 tooling artifact; output 293 source lines, working build/test/lint/typecheck |
| **T3 design stage only (split ICacheAdapter)** | | | |
| researcher | 51,408 | 30 | 4.5 min |
| approach-reviewer | 70,966 | 19 | 6.5 min |
| | | | verdict REJECT — halted before coder |
| **Tier stability** | | | |
| 6 general-purpose agents, 2 per task, cold, sonnet | 239,947 | 38 | ~4 min (parallel) |

## A. Cost correlated negatively with value in this sample

`coder` spent 115k on 293 lines a developer writes in an hour. `researcher` was the
cheapest agent at 51k and produced the most leveraged artifact.

`approach-reviewer` spent 71k and rejected a design that (a) deleted a mandated
invalidation behaviour with no replacement, (b) rejected its own best alternative with an
argument it contradicted two paragraphs later, and (c) surfaced two High security findings
absent from the register.

## B. The T3-specific rungs paid for themselves

Had that task run the T2 shape — straight to coder — roughly 116k would have gone into
implementing a design that ships a cross-role data leak.

This is the first evidence that tier routing does what it claims. It is one instance.

## C. The findings table held zero rows across a project that had run two reviews

19 rows appeared the moment the emitted blocks were piped in by hand. See defect 2.

## D. The tier classifier is stable; the recorded tiers were not

| task | recorded | run A | run B |
|---|---|---|---|
| cache epoch (F13) | T2 | **T3** | **T3** |
| liveness split (F22) | T1 | **T2** | **T2** |
| nonce store (F16) | T3 | T3 | T3 |

3/3 pairwise agreement between independent classifiers. **2 of 3 recorded tiers were too
low** — both because the backlog was tiered from finding *severity* and never checked
against the project's own `tier.rule` floors.

The classifiers could see the recorded tier and overrode it anyway, so anchoring biased
*against* this result and it held regardless. That is what makes it worth acting on.

## The five defects

Filed as tasks at `b238e2e`.

1. **Reviewer agents cannot run the tools their instructions require.** All three reviewers
   are `tools: Read, Grep, Glob` and all three are told to run `kit-finding.sh --vocab`
   rather than guessing. `approach-reviewer` guessed right, 18/18 valid.
   `implementation-reviewer` guessed wrong — `fail-open-guard`, `missing-integration-test`,
   `unverified-claim`, `scope-discipline-clean`; 3 of 4 would have been rejected as unknown
   classes.

   Its top required change was "independently confirm the four ladder commands exit 0",
   which is unresolvable by construction. Having no git either, it could not diff an
   uncommitted change, and read the operator's `.claude/settings.local.json` to
   reverse-engineer what the coder had run.

   **The tell:** `approach-reviewer` used 19 tools, `implementation-reviewer` 45. Design
   review is a reading task and the toolset fits. Implementation review is an execution
   task and it does not. Identical grants; they should not be.

2. **Nothing invokes `kit-finding.sh` — the loop is open circuit.** Agent files say findings
   "are piped straight into `kit-finding.sh --batch`". Nothing does the piping: no hook, no
   skill step. An escape rate reading `T3 0/13` means *nothing was recorded*, not *nothing
   escaped*, and the two are indistinguishable from the output.

3. **No finding class for test-coverage or verification defects.** A missing regression test
   has no home, so reviewers invent class names. Caution from the script's own header: this
   list already drifted across four locations once. Any fix must **reduce** the number of
   places it lives, not add one.

4. **Nothing validates a recorded tier against its own `tier.rule` floors.** Under-tiering
   is silent and it is the dangerous direction. Both floors and task tiers are already in
   the index — this is a query, not a new mechanism.

5. **`kit-plan.sh` has no notion of prerequisite work on greenfield.** 22 tasks collapsed to
   2 layers (20 + 2). The scaffold task — which every other task needs in order to be
   verifiable at all — ranked 11th, behind ten T3s. Only 2 declared `blocked_by` edges, and
   the co-change graph was empty because there is no history. Score is effectively a proxy
   for tier, so the plan says "do the riskiest work first" exactly when the ladder reports
   its rungs unavailable. **Greenfield is this planner's worst case and that is not in the
   known limits.**

### Sixth, smaller

`kit-guard.sh` blocks the Write tool outside the project root but not Bash writes.
`kit-task.sh` created files in another repository from a session rooted elsewhere without
tripping it, while the Write tool was refused. The README already calls the guard "a net,
not a security boundary" — the inconsistency between tool paths is still worth knowing.

## Still untested, ranked by what would change a design decision

1. **Reviewer redundancy at T3.** Run `security-reviewer` blind on the same design
   `approach-reviewer` rejected. If findings converge, the "independent second reviewer" is
   waste and T3 needs redefining — that is 11 of 24 open tasks. **Highest-value test
   remaining, ~70k.**
2. **Model tier sensitivity on reviewers.** Reviewers are roughly half of all spend.
3. **`tester` — never run.** It has Bash. Real tests, or coverage theatre?
4. **A real REVISE/REJECT second round.** Both were short-circuited by hand, so nobody knows
   whether REJECT converges or oscillates.
5. **Context economics.** 13 cluster packs were generated and read by nothing. "Session
   length is the cost lever" remains unvalidated.
6. **Brownfield.** The co-change graph is the kit's differentiator and it was inert here.

## What cannot be tested in a session

**Escape rate itself** — the central hypothesis that tier correlates with defects escaping.
That needs a bug found *after* a task closed.

What can be validated today is that the measuring apparatus works. One of the two apparatus
tests — the findings loop — was already broken.
