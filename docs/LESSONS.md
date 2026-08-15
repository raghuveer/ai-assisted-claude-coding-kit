# Lessons

What this project has learned the hard way, with the evidence attached. Each entry cost real
rework; none is a maxim someone liked the sound of.

---

## 1. A green check that cannot fail is worse than no check

The recurring defect of 2026-08-09, in five different costumes, all shipped by the same author in
one day:

| Shape | What happened |
|---|---|
| A fixture arranged so the assertion passes anyway | The spend test put the ghost's transition LAST — the one arrangement where the claimed NULL happens regardless. The test asserted the comment, not the behaviour. |
| A pattern the tool never reads | `grep -qF '- fabricated row'` begins with `-`, so grep parses it as options and exits 2 without opening the file. `&& exit 1` never fired; the suite printed `grep: unknown option` and reported PASS. |
| A guard that matches its own explanation | A mutation guard grepped the whole file for `CHAR(96)`, which also appears in the comment *explaining* `CHAR(96)`. Successful mutation read as failure; the run was skipped. |
| A mutation targeting code that had moved | The guard asked "is the OLD text still present?", got "no", concluded the mutation applied, and ran an **unmutated** suite to a green 34/0. |
| A debug harness looser than the assertion it debugs | Written with wildcards and no anchor exactly where the real test was strict. It passed twice and explained nothing. |

**The test:** before trusting a check, ask what it prints if the thing under test is absent,
unapplied, or never reached. If that answer is also "pass", the check is decoration.

**In practice:** assert the *mutated* state is present rather than the original absent; count
occurrences before and after; pin exact values (`= 1.0`, never `!= 0`); and make a debug harness
match the real assertion character for character or it is testing something else.

---

## 2. Mutation testing proves sensitivity, not coverage

Twelve mutations came back red on one task. It felt like proof. It was not.

Mutation testing proves that **existing assertions are sensitive to changes in the code**, on
**the input the fixture already constructs**. Every defect the reviewers found afterwards lived
in a scenario the fixture never built: a second agent id, a second assistant turn, a capitalised
severity, a literal backslash, a NULL column.

No mutation of the source could have turned a passing assertion red for any of them, because no
assertion looked there. **Red mutations say the tests you have work. They say nothing about the
tests you don't.**

---

## 3. The defects were overwhelmingly the author's own claims

Across four review rounds the pattern never varied. Each of these was written confidently, none
was verified, and each survived until someone built the fixture the author hadn't:

- *"constrained to hex by everything that writes it"* — contradicted four lines later in the same
  comment block, and reachable through an ordinary commit.
- *"Both writes are CHECKED"* — checking **reports** the failure on stderr; it does not prevent it.
- *"present in **By scope** and the per-model figures"* — a NULL `scope` makes the whole row NULL,
  so 5.4M token-equivalents appeared in no figure at all.
- *"an agent that QUOTES the format in prose is not harvested"* — true only when the mention and
  the example share a raw line, which is the fixture's arrangement and not how anyone writes.
- *"kit-plan.sh needed no change and that was checked"* — the check was of the task population.
  The dependency EDGE was never looked at, and it had silently stopped blocking.

**A comment asserting behaviour is a claim, and a claim needs a test that fails without it.**
Prose in a code comment is the least verified thing in any repository and the most trusted.

---

## 4. When a defect shape is found, sweep for it immediately

`task_known()` interpolated an id into a `grep -E` pattern, so `T-re.l` matched `T-real` and the
gate passed a typo. It was filed the same morning, with an acceptance criterion that read *"check
the same shape elsewhere before closing"*.

That afternoon the same author wrote the same shape twice more, in new code: `agent_id`
interpolated into a `grep` pattern, and into a `find -name` glob. With `agent_id` of `*` the hook
harvested a **different agent's** transcript.

Three instances of one shape in one day, with the task documenting it open the whole time.
**Filing a defect class is not the same as sweeping for it, and the sweep is the cheap half.**

---

## 5. Prefer deleting a component to hardening it

The findings harvester scrapes reviewer output out of transcripts. It accumulated five defects in
about 120 lines: a JSON envelope leaking into the log, backslash corruption, retracted drafts
recorded as real, silent drops its own gap counter could not see, and the pattern injection above.

It exists for exactly one reason: **reviewers cannot run commands**, so nobody could hand the
findings over directly. Every one of those defects is a consequence of scraping rather than
receiving.

The fix is not a better scraper. It is for the reviewer to return findings as **structured data**
that the orchestrator records — the reviewer stays read-only, nothing new gets write access, and
the parsing subsystem ceases to exist along with its whole defect class.

**Ask for the data; do not scrape it. The cheapest component to secure is the one you deleted.**

---

## 6. Models for judgement; deterministic code for data

Both halves are load-bearing.

**Models earned their place.** Four adversarial reviewers found 24 real defects including two
criticals, each reproduced in a purpose-built fixture. They found what twelve mutations, a green
35-step suite and CI on three platforms all missed — because they built inputs nobody had thought
to build. That is judgement, and it is what this kit spends tokens on.

**Models would be actively wrong for the parsing.** Using one to extract findings from a
transcript would be nondeterministic where determinism is the product, unverifiable by a
conformance case, slower and costlier. Every failure of 2026-08-09 was data handling, and none
would have been improved by a model doing it.

---

## 7. Where the stack actually hurt, and where it did not

Counted honestly over 24 findings: roughly **half were stack-shaped and half were discipline**,
which is less comfortable than either "it's the tools" or "it's just care".

**Stack-shaped, and worth changing:**

- **JSON parsed and written with text tools.** The single worst decision in the set. It produced
  the envelope leak, the backslash corruption and the malformed append to a log that is
  append-only and committed. `python3` is *already* a hard dependency — `validate.py` runs in CI —
  so the constraint that justified hand-rolling was not real.
- **Untrusted text interpolated into patterns.** Not a regex problem; a shell-idiom problem. In a
  typed API, comparing strings is the default and building a pattern is deliberate.
- **POSIX tool footguns.** `grep` reading a leading `-` as options; `case` as the last command
  supplying an exit status of 0.
- **SQL NULL semantics.** `x NOT IN (set containing NULL)` is never true; `a||b` is NULL if either
  side is; SQLite does not enforce `NOT NULL` on a `TEXT PRIMARY KEY`. All three shipped.

**Not stack-shaped:** every false claim, every vacuous fixture, and the design gaps around
retracted drafts, empty reviews and attribution. No language prevents those.

**What this argues for** is not a rewrite. It is one JSON reader and one JSON writer at the two
boundaries that touch JSON, `STRICT` tables with `NOT NULL` where the schema already assumes it,
and a conformance lint for the pattern-injection shape — the kit already lints its own agent
tools, vocabulary and exec bits, and has now shipped this shape three times.

---

## 8. What the development loop costs, measured

One session, 2026-08-09: **$161.57, 4h of API time, 16.5h of wall time, 2,648 lines added.**
Opus $138.82, Sonnet $22.75. 67% of spend came from subagent-heavy work, 79% at >150k context,
97% from a session running 8+ hours.

**What it bought:** one task closed, two built and correctly rejected, six defects filed with
reproductions, an adoption rewrite, this document, and capability evidence from two external
repositories.

**Where it leaked, in order of size:**

**Rework from unverified claims.** Rounds 2, 3 and 4 of one task existed largely because
sentences in the previous round were false (§3). Each round costs several subagents plus a fix
pass. The expensive instrument — adversarial review — was spending its budget on prose a cheap
pass could have caught, instead of on what only it finds: a forged `commit_sha` reaching the
report, a spend row swallowing 5.4M token-equivalents. This is what
`T-20260809-a-claim-audit-before-a-task-closes-names` exists to stop.

**One context across many tasks.** Four distinct tasks and two dry runs shared a single session,
so every later request paid for all the earlier context. The task files and memory already carry
enough to resume cold — that is what they are for — so the split costs nothing but discipline.

**Polling.** Repeatedly checking background jobs, each check a full request at high context.
Fewer, longer waits are strictly better.

**Wall time is not money, but it is still a cost.** 16.5h wall against 4h API is mostly waiting on
local suites, which burn no tokens. It still shapes behaviour: at 8-10 minutes a run, mutation
proofs get batched instead of taken one at a time, and two mutation guards were written carelessly
on exactly that pressure — one skipped silently, one ran an unmutated suite to a green result.
Filed as `T-20260809-conformance-cannot-run-one-step-so-every`.

**What was NOT waste:** the reviewers. 24 real defects including two criticals, each reproduced in
a purpose-built fixture, found after a 35-step suite, twelve red mutations and three-platform CI
had all passed. Cutting that spend would have shipped the defects instead.

---

## 9. Push early — the gate you cannot run locally is the one that catches you

A new script landed in the index as `100644` while every sibling was `100755`, and three CI jobs
went red. The local suite had passed 35/0 on the same tree, and that was **true and incomplete**:
the control reads the git *index*, the file was untracked for every local run, and it became
visible to its own gate at the moment of commit — after the last local run.

A new file is invisible to that check exactly once, and that once is the commit introducing it.
The gate did its job at the first opportunity it had. The alternative was carrying a broken mode
through however many commits until someone thought to ask CI.

---

## 10. Decompose by technical property, not by organisational category

Two task splits in one day were wrong the same way, and both were caught by being asked "is this
the right approach?" rather than by review.

The first split a recorder task into **reviewer** work and **producer** work. That boundary comes
from the pipeline's org chart, not from the code: `verdict` is a closed three-value vocabulary
that fits an existing event line, and so is every producer fact — build pass/fail, an error
count, tests passed/failed/skipped. `narrative` is unbounded free text going into a committed,
line-oriented log. **The seam is bounded versus unbounded, and it cuts across reviewer/producer
rather than along it.** Splitting the wrong way bundled a cheap fix with an expensive one and
hid that recording the verdict alone was enough to tell an empty review from one that never ran.

The second nearly repeated it: within "bounded", reviewers have a runner that captures their
output and producers have none. That is an *emission-path* difference, not a data-shape one, and
it is the property that decides the work.

The test: if a boundary would still make sense with the agents renamed, it is probably real. If
it only makes sense because of what the parts are *called*, look for the property underneath.

A related failure in the same family: a dependency edge was proposed between two tasks that
merely shared a design decision. `blocked_by` cascades — one mistyped id once withheld 20 of 22
open tasks — so it states "cannot start until", never "decide this together". Shared constraints
are enforced by the constraint (one JSON writer), not by an edge.

## 11. Record the measured value beside the required one

A gate that reports only pass or fail cannot be audited, and a ladder with no measurement
promotes on opinion. The pattern that works is two numbers adjacent: what was required, and what
was observed. `threshold 0.85 / measured 0.72` says *experimental* by arithmetic — nobody has to
be persuaded, and nobody can quietly disagree.

The kit already does this in one place and not the others. Escape rate reports both populations
side by side precisely so provenance can change what a number means without changing whether an
escape is visible. The promotion ladder, by contrast, is documented with thresholds and
implemented with nothing, so promotion would be an act of belief.

Two corollaries that keep costing us when they are skipped:

- **An exclusion must be counted.** When a gate drops something — a refuted finding, a filtered
  population — the excluded count is reported next to the surviving one, or the smaller number
  is indistinguishable from a wrong one.
- **State applicability in both directions.** Anything shared says what it is unsuitable for, not
  only what it does. An asset that advertises only its strengths gets loaded where it does harm,
  and the person loading it has no way to know.

---

## 12. The harness that reports its own success is the one to distrust

§1 is about a check that cannot fail. This is its neighbour and it bit **five times in a single
session** on 2026-08-15: a *harness* — the scaffolding around a check — reporting success for work
it never performed. The check was fine every time. The thing driving it lied.

| Shape | What happened |
|---|---|
| A mutation that never applied | `sed`/`python` replacements silently matched nothing. The suite then ran against **unmutated** code and printed PASS, which reads as "the mutation survived" — the exact opposite of the truth. Three separate times, on three different mutations. |
| An edit script reporting the attempt, not the effect | It appended to its success list on *finding* the target line, not on *replacing* it. Reported `applied: [emit, header, join]` having changed one of the three. |
| A status read from the wrong process | `cmd \| tr '\n' ' '; rc=$?` captures `tr`'s status. Four refusal cases all reported `rc=0` while the script had correctly exited 1. |
| A step selected but not exercised | `--only "deterministic fixture"` ran the fixture's chain prefix and printed `0 passed, 0 failed`. The assertion lives in a *later* step of the same chain, so the filter selected the setup and none of the checking. |

**Why it recurs:** every one of these reports on the *intent* of an operation rather than its
*effect*. `sed` exits 0 when it matches nothing. A shell pipeline's `$?` belongs to its last stage.
Appending to a list inside an `if` records that the branch was taken, not that the work landed.
None of them are bugs in the tool; they are the tool answering a question that was never asked.

**The test:** after any step that is supposed to change something, ask *what would be different if
it had done nothing* — then check that, not the exit code. A mutation harness must verify the
mutation is present before it believes a survival. Print the count and read it.

**In practice:**

```sh
n=$(grep -c 'mutated_token' file); [ "$n" -ge 1 ] || { echo "MUTATION DID NOT APPLY"; exit 1; }
cmd > out.txt 2>&1; rc=$?          # status first, formatting afterwards
```

Treat **zero checks executed as a harness error, never as a result** — a run of `0 passed, 0
failed` is a run that measured nothing, and `--only` on a chained step can produce exactly that.

**And the one that proves the point:** the leading-dash family from §1 — after a program text, `--` is a
*filename*, not an option terminator — was written into this repository's comments and then
repeated by the same author, twice, within an hour. Once it broke `kit-entry.sh` so completely
that `entry-facts.tsv` came out as a header with zero rows, and once it broke every `awk` in a
validator. **Both times the exit status stayed clean and only reading the output caught it.**
Documenting a trap does not stop you falling into it; a check that looks at the result does.
