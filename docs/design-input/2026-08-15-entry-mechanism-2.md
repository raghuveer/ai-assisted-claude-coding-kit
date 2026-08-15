## Problem statement

The kit has no way to turn an existing codebase into a first task list. Design 1 proposed a per-directory inventory ("areas"), marker-file stack detection, per-directory churn, and a *rationale map* that classified doc-shaped files by name and path. That design was rejected twice, and a prototype implementing exactly its five inputs has since been run against three real repositories. The measurements are in `inventory-*.md` and they falsify the central invention rather than qualify it:

- On **this repository**, `tooling/` — 21 files, 1,554 comment lines, 34.1% density, the densest rationale in the project — reports **zero rationale sources**. The map would ask the questions it was built to prevent.
- On **prometheus**, 13 of 23 areas report zero rationale, including `config` (224 files), `cmd` (87), `util` (83). Doc-shaped files are 4.1% of the tree and `docs/` holds 32 of the 68.
- **Directory attribution destroys history**: `(root)` absorbs 72% of prometheus's commits and 94% of actix-web's.
- **Marker files discriminate nothing**: all 13 actix-web areas are `Cargo.toml`; prometheus `web/` carries `go.mod` *and* `package.json`.

So this document starts from the problem, not from a patch. Its two expensive decisions are **what the deterministic half emits** and **which actor writes each artefact** — the second is where design 1 died outright (`agents/researcher.md:5` grants no `Write`).

## Assumptions and constraints

- `bash` + `git` + `awk` + `sqlite3`. `python3` stays at its one boundary (`tooling/kit_findings.py`). Nothing is written to SQLite. CI is ubuntu-latest (mawk) + macos-latest (BSD), so every `awk`/`sed`/`date`/`wc` claim below is a portability claim and is treated as one.
- The five settled decisions in the brief are taken as given: no aggregation unit; `paths.adr` and `paths.design_input` added together; questions committed and candidates disposable; **no `--confirm` flag and no claimed hold**; design against today's tooling.
- **This design OWNS the profile change**, rather than assuming someone else makes it. `paths.adr`
  and `paths.design_input` are added to **both** `.claude/project-profile.md` and
  `templates/project-profile.md` — the template too, or every future adoption starts without the
  keys and two writer rows in §B2 depend on keys nobody creates. Taking a decision as given is not
  the same as someone having implemented it, and the first revision listed neither in scope nor in
  "Not solving".
- **Failure model.** The subject may have: one commit (vendor import — the ordinary modernization case), no index, an empty or withheld co-change graph, binary and generated files, 20k files, and rationale that is not in the repository at all. Each of these must read as *did not look*, never as zero.
- **Not solving.** The component model. The `INSTALL.md` §C adoption rewrite (but see Open questions — nothing currently causes this to be run). Fixing the three defects filed today. Any hold mechanism.

## Existing code considered

| Path | State | Bearing |
|---|---|---|
| `tooling/kit-index.sh` §2b + `cochange` table (`schema.sql:60-66`) | **Complete-but-narrow** | `src`/`dst`/`weight`, `f:<path>` keys — already file-anchored. Read it; never recompute. Measured here: 375 pairs over **72 of 170** files, degree 10.4/50. On `fd`: 722 pairs, 97 files, 14.9. Positive evidence on two subjects. |
| `tooling/kit-index.sh` §2b early exits | **Defective** | Four non-success states leave no trace (`T-20260815-co-change-withheld-disabled-and-empty-ar`). An empty table is ambiguous **today** and this design must not wait on the fix. |
| `tooling/kit-task.sh` | **Complete, and not a gate** | Lines 30-50 write unconditionally from flags; the only refusal is the id collision at `:39`. `T-20260815-kit-task-sh-documents-a-confirm-gate-it-`. No argument here rests on it. |
| `tooling/kit-accel.sh propose` (`:81-163`) | **Complete** | The artefact model: `GENERATED`, checkboxes, applied by nobody, thresholds stated, and a `Below threshold (not proposed)` section — an exclusion *counted*. Copy this shape. |
| `tooling/kit-finding.sh` + `kit_findings.py` | **Complete** | The precedent for "a read-only model returns data, a script records it" (`LESSONS` §5). Relevant as a shape and **not reusable here**: its contract is findings, and a second parser would be a second boundary. |
| `agents/researcher.md:5` / `adr-scribe.md:5` / `documenter.md:5` | **Complete** | researcher: `Read, Grep, Glob, WebFetch, WebSearch` — **no Write**. adr-scribe and documenter have `Write`. Checked this session. |
| `tests/conformance.sh:213-229` (step 4) | **Complete-but-narrow** | "no agent is told to run a tool it does not have" tests only ``Run `kit-*.sh` `` against a missing `Bash`. It does not test `Write`, which is why `researcher.md:31` ("write to the project's design-input directory") has survived. New finding, see below. |
| `.claude/project-profile.md:8-10`, `.gitignore` | **Absent / Complete** | No `paths.adr`, no `paths.design_input`. `.gitignore` covers `index.db*`, `packs/`, `STATUS.generated.md` — so anything new under `.project/` is committed by default and must be added explicitly. |
| `docs/DESIGN-NOTES.md` §0 | — | An agent is a permanent standing charge (~105 tok each); a reference file is not. This forbids a new agent for a once-per-project act. |

## Alternatives considered

**A. Design 1's per-area inventory.** **Reject — now measured, not argued.** Three subjects, both failure directions, above.

**B. One file-anchored fact tool + a resident model for judgement (recommended).** Detailed below.

**C. No script — a skill instructing the model to run `git` itself.** Zero code, maximum flexibility, ~88 tok resident. Rejected in design 1 for unbounded context and non-reproducibility; **it is a much closer call now**, because the deterministic half is thinner than design 1 assumed. It still loses on the one job the tool does best: counting comment lines and locating comment blocks across 1,665 files is arithmetic, not judgement (`LESSONS` §6), and a model doing it produces a number nobody can regression-test or compare between trials. *Reversibility: highest.*

**Withdrawn as the fallback.** The first revision named this the fallback if the localiser failed,
in one paragraph. That will not hold weight: adopting it deletes the only structural control in
§B2 (a tool that cannot write a task file) and the whole of §B3 (there is no script to write a
fixture against), and it adds a permanently resident skill for a once-per-project act, which
`DESIGN-NOTES` §0 disfavours. A fallback that costs more than the thing it replaces and is
specified in one paragraph is not a fallback; it is an escape hatch nobody has costed.

**The real fallback, and it is smaller than the design.** If the re-registered condition below
fails validly, `kit-entry.sh` **drops comment localisation and keeps the census** — paths,
extensions, line counts, comment *counts* per file, marker-file paths, per-file history, co-change
coverage. All of that is already measured to work and none of it depends on the invention. The
model then receives the TSV and a bounded file list and does the locating itself, in one place,
where it is judgement rather than arithmetic. The tool stays, the fixture stays, the structural
control stays, and the design loses exactly the one thing that failed. Option C remains on the
table only if the *census itself* proves useless on the first external subject, which nothing
currently suggests.

**D. `ingest.extra` adapter emitting candidate rows.** **Reject**, and worse than design 1 knew: an adapter genuinely *can* `INSERT INTO task` (`T-20260815-an-ingest-adapter-can-insert-a-task-row-`), so this route puts unconfirmed candidates in the backlog count and the escape-rate denominator with nothing refusing them. *Reversibility: poor — ids in trailers are permanent.*

**E. Extend `kit-index.sh`.** **Reject**, unchanged: `--if-stale` runs per session; a whole-tree walk is once per adoption.

**F. `--confirm` batch writer.** Excluded by decision 4. A gate satisfied by passing a flag is laundering.

## Recommendation — option B

### B1. What the deterministic half emits

`kit-entry.sh` (name in Open questions). **One row per tracked file, no grouping.** Two outputs under `paths.state`, both derived — and **three** `.gitignore` lines are added, not two: `entry-facts.tsv`, `entry-report.md`, and `entry-candidates.md` from §B2, which is equally disposable and equally derived. Missing the third is how a machine-specific artefact reaches a colleague's clone:

- `entry-facts.tsv` — complete, one line per file: `path · ext · lines · comment_lines · comment_blocks · commits · first · last · authors · doc_shaped · cochange_degree`. Uncapped, cheap, greppable. **Header line names the columns; tab-separated; `LC_ALL=C` sort by `path`.**
- `entry-report.md` — **bounded**, model-facing and human-readable. Every section is a top-K with `showing K of N` and the dropped count printed beside it (`LESSONS` §11, and the `Below threshold` precedent in `kit-accel.sh`).

**There is no per-file section in the report.** The first revision had one, capped at 400 files,
with no ranking key named — and an unnamed sort over 400 of 20,000 files is the tool choosing the
answer through a tiebreak, which is decision 1 violated by the back door. The per-file data lives
in `entry-facts.tsv`, which the model reads with `Grep` on its own terms. The report carries only
sections whose ranking key is stated in the section heading itself:

| section | ranking key, stated | cap |
|---|---|---|
| Totals and degeneracy states | none — fixed set, all printed | n/a |
| Comment runs | run length, descending; `path` then `start` as tiebreak, `LC_ALL=C` | 40 |
| Marker-file paths | `path`, ascending | all |
| Co-change neighbours | `weight` descending, `dst` tiebreak | 5 per file, files by degree |
| Extension histogram | count descending, extension tiebreak | all |

**Report line grammar, for every field any fixture asserts on.** One record per line, no wrapping:

    tracked_files <N>
    commits <N>
    history <ok|degenerate: single-commit history|unavailable: not a git repository>
    cochange <ok N pairs, M of T files|empty: indistinguishable from withheld / disabled / no history / no index>
    run <path>:<start>-<end> <length>
    marker <path>
    skipped <binary|oversize|unreadable> <N>

A fixture asserting on anything not in this list is asserting on prose, which is how the first
revision's fixture came to grep a TSV column name out of a markdown file.

Five emissions, and what measurement did to each:

1. **Per-file history** (`commits`, `first`, `last`, `authors`) — **kept**. The collapse measured on prometheus and actix-web is an artefact of *aggregating to a directory*; `(root)` absorbing 13,258 commits is a true fact about `CHANGELOG.md` and `go.mod`, and it is only meaningless once it is called "the root area". Decision 1 is therefore not merely a constraint — it is what rescues this input.
2. **Comment localisation** — **the replacement for the rationale map, and the only new invention here.** Emit every **run of ≥10 consecutive comment lines as `path:start-end length`**, top 40 by length. Locating and counting is deterministic; reading those ranges for meaning is the model's job, and it reads *kilobytes of named line ranges* instead of a tree. The tool never says "no rationale here" — only "0 comment lines here", which is a count.

   **Comment tokens are NOT selected by file extension.** The first revision chose one token set
   per extension (`#` for `.sh`), and that hid `kit-index.sh:935-961` — 27 lines, the phantom-task
   rationale, the 5th-longest run in this repository — because it is SQL comments inside a bash
   heredoc. Embedded languages are ordinary, not exotic: SQL in shell and Go, awk in shell, JS in
   HTML, shell in YAML. A file is scanned for the **union** of `#`, `//`, `--` and `/* … */`, and a
   run may not mix tokens — a `#` run and a `--` run are different runs even when adjacent.

   **This is a fix, not a tune — and it has now been measured, and it buys almost nothing.** A tune
   moves a threshold until a known target appears; this changes *which lines are comments at all*
   and is derived from a named false negative. But scored against the blind ground truth below, the
   union matcher and the per-extension matcher give **identical recall — 6/10 into the top-40, 7/10
   overall** — and the union scan adds only 4 runs (68 → 72) on this repository. It is retained
   because `kit-index.sh:935-961` is a real 27-line rationale block that the per-extension rule
   genuinely hides, and because embedded languages will be commoner on a polyglot subject than on
   this one. **It is not retained on evidence that it improves the result, because it does not.**
   Saying otherwise would be the false-rationale class this kit refuses.

   **File selection is not by extension either**, for the same reason one level up: `tooling/`
   contains `commit-msg` and `pre-push`, real shell scripts with no extension, and one of them was
   independently nominated as load-bearing rationale. Selection is by extension **or** a `#!` first
   line.
3. **Doc-shaped files** — **kept as a per-file fact, demoted from an inference.** `README`/`ADR`/`*.md` under a docs path is a fact about that file. "This area has no rationale" is the falsified claim and is never emitted.
4. **Stack** — **demoted.** A repo-level extension histogram, plus the literal paths of every marker file (`web/ui/package.json`, not "web is JS"). Zero discriminating power per area is what was measured; per-path it is still true.
5. **Co-change** — **read, never recomputed**, top-5 neighbours per file, with coverage stated as a fraction (`72 of 170 files, 42%`). If the table is empty the report prints `co-change: empty — indistinguishable from withheld / disabled / no history / no index (T-20260815-...)`, i.e. **did not look**, citing the filed defect. Nothing here waits on that fix.

**Deleted outright:** area aggregation, per-area stack, per-area churn, the rationale map. Say it plainly: **the deterministic half is thinner than design 1 assumed** — roughly 200 lines of `awk` doing counting and localisation, not classification.

**Determinism.** Every list is sorted with an explicit total order and a `path` tiebreak under `LC_ALL=C`; no `for (k in arr)` (mawk and BSD awk differ, and `kit-index.sh:687` gets away with it only because SQL is order-free). All dates come from `git log --date=short`, never `date(1)`. Line counts from `awk END{print NR}`, never `wc -l` (BSD pads). Binary files and files over a size cap are skipped **and counted**.

**Degeneracy, stated per input.** Each input prints `ok | empty | degenerate: <why> | unavailable: <why>`.
- *Second run*: both artefacts are derived and overwritten; the committed questions file is dated and never touched by the tool. The model is given the existing task ids and must mark each candidate `new` or `already filed as T-…`, with the suppressed count reported.
- *Empty tree*: `tracked_files 0`, every section `0 of 0`. Greenfield, with no special path. `awk` is never invoked with zero file operands.
- *Single-commit import*: `commits == 1` marks all four history inputs `degenerate: single-commit history` rather than emitting one date and one author that read as measurements. What survives is exactly the static half — paths, extensions, comment blocks, marker files — which is the half that also survived the aggregation collapse. This is the fourth failure condition both reviews demanded.

### B2. Which actor writes each artefact

| Artefact | Writer | Tools, checked |
|---|---|---|
| `entry-facts.tsv`, `entry-report.md` (derived, gitignored) | `kit-entry.sh` | bash — writes these two paths and nothing else, ever |
| the proposal *text* | **`researcher`, AMENDED — see below** | `Read, Grep, Glob, WebFetch, WebSearch` (`researcher.md:5`) — it **returns**, it does not write |
| `<paths.state>/entry-candidates.md` (disposable, gitignored) | the **orchestrator**, via `Write` | writes the returned text verbatim |
| `<paths.design_input>/YYYY-MM-DD-entry-questions.md` (**committed**) | the **orchestrator**, via `Write` | |
| answers → a decision record under `<paths.adr>` | **`adr-scribe`, AMENDED — see below** | `Read, Grep, Glob, Write` (`adr-scribe.md:5`) — the house ADR writer, but its trigger does not cover this |

**Two agent files change, and this design owns both changes.** The first revision of this document
said `researcher` was reused "unchanged", which was false on three counts, all in its own file:
`researcher.md:30` is headed *"Output — write to the project's design-input directory"* and orders
a write it has no tool for; the section pins a **seven-section design-input template** that a
candidate list does not fit; and it caps output at *"~2000 words"*, which a proposal over a large
tree will exceed. Reusing an agent is only free when it is genuinely unchanged.

- `agents/researcher.md` — the Output section becomes *return the document; the caller writes it*.
  This is a one-line correction to a defect that already exists for every current use, filed as
  `T-20260801-reviewer-agents-cannot-run-the-tools-the`. This design does not depend on that task
  being done; it makes the change itself, and the task shrinks. The template and word cap become
  conditional on which artefact was asked for.
- `agents/adr-scribe.md` — its `description` triggers on *"after `approach-reviewer` returns
  APPROVED"*. An answered entry question is not that, and the file never mentions questions at all.
  The trigger gains the second case. The earlier claim that it was "already the house writer for
  answered questions" was an overstatement: it is the house ADR writer, and the operator's decision
  that answers become ADRs is what puts this work in its hands.

**Neither change grants a new tool.** `researcher` loses an instruction it could never follow;
`adr-scribe` already holds `Write`. No agent is added, so `DESIGN-NOTES` §0's standing charge is
unmoved.
| task files | **the operator**, running `kit-task.sh` lines | |

Why this split: it adds **no agent** (§0), grants **no new write capability to anything**, keeps the large report out of the main context (researcher reads it; only the much smaller proposal transits), and matches `LESSONS` §5 without adding a parser — the orchestrator has `Write`, so nothing needs scraping *or* deserialising. Do **not** grant `researcher` `Write`. Do not create an `entry-analyst`. On a small repo the orchestrator could do both halves itself; the crossover is simply `report ≫ proposal`, so the subagent wins on exactly the large repos this is for.

**Honest statement of the control, per decision 4.** `kit-entry.sh` cannot write a task file — that is structural, and it is the *only* structural part. The orchestrator holds `Write` and `Bash`; `kit-guard.sh` permits every in-root path (`hooks/hooks.json:5` matches `Write|Edit|NotebookEdit`, and `kit-guard.sh` allows in-root writes); `kit-task.sh` is not a gate. So: **the task file's acceptance criterion "hold the task list unconfirmed until questions have answers" is NOT met by this design.** It is met by convention. That is a known unmet criterion to be accepted or rejected at the walkthrough, not a gap to be papered over with a flag.

One live boundary, named because design 1 did not: the model is handed named files from an
**untrusted** third-party repository to read, and then emits shell lines a human pastes.

**Who enforces the title charset, stated as plainly as the hold.** Nobody, today. Restricting
candidate titles to `[A-Za-z0-9 ._-]` is an instruction to the model about its own output, and the
model is the actor the restriction exists to bound — the same shape as a session certifying its own
`Via:`. `kit-entry.sh` never sees the titles, so it cannot check them; `kit-guard.sh` matches
`Write|Edit|NotebookEdit` and permits every in-root path anyway; and §B3 cannot test it, because a
fixture can gate the tool and not the model. **So this is convention, and it is the second one in
this design.** It differs from the hold in that a mechanical fix exists and is cheap:
`kit-task.sh --title-file` (or stdin) deletes the shell round-trip entirely, at which point no
charset rule is needed because nothing is ever parsed by a shell. That belongs on
`T-20260815-kit-task-sh-documents-a-confirm-gate-it-`, and until it lands, the honest statement is
that a hostile candidate title is bounded by the operator reading the line before pasting it.

### B3. The fixture (must be able to fail)

One step in the existing grammar — `if step "an undocumented choice is reported and no task file appears"; then … fi` — modelled on `tests/conformance.sh:1027`. Fixture: `git init`, `kit-init.sh`, `src/retry.go` containing `maxRetries = 7` with **no** comment, `src/cache.go` carrying a 12-line rationale block, two commits.

**What counts as a tracked file, because the pinned numbers depend on it.** `git ls-files` minus
`.claude/`, `<paths.state>`, `<paths.tasks>`, and top-level dotfiles. `kit-init.sh` itself creates
`.claude/project-profile.md` and updates `.gitignore` and `.gitattributes`, so a fixture that runs
`kit-init.sh` and then pins `tracked_files 2` is counting the kit's own footprint as subject code
unless this rule exists. **The exclusion is COUNTED, not silent** — `skipped kit-owned 3` — per
`LESSONS` §11, because an exclusion nobody can see is indistinguishable from a file that was missed.

**Fixture.** `git init`, `kit-init.sh`, then `src/retry.go` containing `maxRetries = 7` with **no**
comment, `src/cache.go` carrying a **12-line** rationale block, and `src/edge.go` carrying a
**9-line** block. Two commits.

**Presence assertions, each with the mutation that turns it red:**

| assertion (against the grammar above) | red when |
|---|---|
| `grep -qx 'tracked_files 2'` | the kit-owned exclusion is dropped (yields 5) or added twice |
| `grep -qx 'skipped kit-owned 3'` | the exclusion stops being counted |
| `grep -qx 'commits 2'` | history reading is removed |
| `grep -qE '^run src/cache\.go:[0-9]+-[0-9]+ 12$'` | the run scanner is removed |
| **`! grep -q '^run src/edge\.go:'`** | the threshold drops below 10 |
| `grep -qE '^history (ok\|degenerate\|unavailable)'` | the degeneracy state stops being emitted |
| `grep -qE '^cochange (ok\|empty)'` | the four-way co-change ambiguity is no longer named |
| `grep -qE '^src/retry\.go\t' entry-facts.tsv` and its `comment_lines` field is `0` | zero-comment files are skipped instead of reported as zero |

The pair `cache.go` **must** appear at exactly 12 and `edge.go` **must not** appear pins the
threshold from both sides. The first revision asserted `1[0-9]` on a 12-line block, which stays
green for any threshold at or below 12 — the assertion could not fail in the direction the
threshold moves, which is `LESSONS` §1 inside the fixture written to satisfy it.

**Absence assertions (necessary, not sufficient), by count not listing:** task files under `paths.tasks` equal before and after; `SELECT COUNT(*) FROM task` unchanged after a reindex; no line in either artefact matching the task-file grammar.

The pairing is the point: the run proves the tool **did the work and still wrote nothing**. A `kit-entry.sh` of `exit 0` plus a `touch` fails four assertions. A second step covers the single-commit case by asserting `history degenerate: single-commit` is present. **The model half cannot be gated by a fixture** — stated, not implied.

### B4. Self-ingest pass condition, registered before the run

AC5's "usable" means all five, measured on this repository as-is:

1. **Superseded — the original condition was VOID, and its replacement has now been run.** See
   "The localiser, measured" below. The original wording is kept here only so the record shows what
   was replaced: *"the top-40 list contains ≥3 of these 4 known rationale sites: `kit-index.sh` §4
   (~935-961), `kit-finding.sh:1-26`, `kit-lib.sh:71-88`, `schema.sql:55-59`."*
2. ≤25 candidates after dedup against the 93 existing task nodes.
3. Between 1 and 15 questions, each naming a path and a line range that exist.
4. Zero candidates duplicating an open task, checked by the operator against `paths.tasks` — not asserted by the model about its own output.
5. Zero new files under `paths.tasks` attributable to the run.

**What would change my mind:** a trial showing candidates routinely >30 (→ reopen the batch-writer question the operator excluded, with evidence); rationale living outside the repo on the first external subject (→ the tool is a file census and the questions come from the operator interview, which is a smaller thing again).

### The localiser, measured — and the result is 60%, invariant

**Why the first condition was void, not failed.** It named four target sites. `schema.sql:55-59`
sits in an 8-line comment run, which the ≥10 threshold excludes *by construction*, so "3 of 4, one
miss allowed" was silently "3 of 3 reachable, no miss allowed". Worse, the two sites it scored as
FOUND are exactly the two it had read, and the two it missed are exactly the two it had not. It
measured whether the targets had been verified, not whether the localiser works. **`delete, not
tune` never fired, because the condition never ran.**

**The replacement, designed against that failure.** Ground truth is chosen by an agent that cannot
see the scanner: read-only, no sight of any localiser output, asked to name the 12 places in this
repository where "an explanation whose loss would cause a competent maintainer to change the code
and break something" lives. It returned 12 with line ranges and a one-clause reason each. Ten are
in files the scanner covers; two are not code comments at all (`docs/DESIGN-NOTES.md:398-433` and
`.gitattributes:1-19`) and are out of scope by design, which is itself worth recording — **one
sixth of this repository's load-bearing rationale is not in code comments and never will be.**

**Result, this repository, union matcher, cap 40:**

| min run | runs ≥ min | recall @ top-40 | recall @ all runs | top-40 files | max slots one file |
|---|---|---|---|---|---|
| 4 | 246 | **6/10** | 9/10 | 15 | 10 |
| 6 | 142 | **6/10** | 8/10 | 15 | 10 |
| 8 | 104 | **6/10** | 8/10 | 15 | 10 |
| 10 | 72 | **6/10** | 7/10 | 15 | 10 |
| 12 | 47 | **6/10** | 6/10 | 15 | 10 |
| 15 | 26 | 4/10 | 4/10 | 10 | 7 |

**Read this before choosing a threshold.** Recall into the *artefact* is **6 of 10 and does not
move** anywhere between a 4-line and a 12-line threshold. Lowering the threshold adds runs that all
land below the cap; **the cap binds, not the threshold.** So "lower the threshold until it passes"
was never available, which is the answer to the question `LESSONS` §5 asks.

**Two of the ten are unreachable at any threshold, for a reason that indicts the premise.** The
longest comment run overlapping `kit-guard.sh:25-31` is **3 lines**; overlapping
`kit-index.sh:736-748` it is **5**. That rationale is *interleaved with the code it explains*, in
fragments. The invention assumes rationale appears as a long contiguous block, and for these it
simply does not. No matcher and no threshold recovers them; only reading the file does.

**And the concentration never improves:** one file holds 10 of 40 slots at every threshold, so a
quarter of the model's budget goes to `kit-status.sh` on a 170-file repository.

**The cap on a real subject, now measured too.** At a 10-line threshold prometheus yields **921
runs** and the cap of 40 keeps **4.3%** of them; at 5 lines it yields 1,515 and the cap keeps 2.6%.
actix-web: 287 and 477. So the artefact discards 96-97% of what the scanner found on a large
subject, while on this 170-file repository recall into that same artefact is already stuck at 60%.
Both numbers indict the cap, and neither is an argument for moving it here — a cap set to make a
recall figure look better, in the document that measured the recall, is worth nothing. What it is
an argument for is that **the top-K report is the wrong delivery mechanism for this input**: the
per-file comment counts are already uncapped in `entry-facts.tsv`, and the model can `Grep` them
without any ranking decision being taken on its behalf. That is the change to weigh at the
walkthrough, and it is a smaller design than either raising the cap or deleting the localiser.

**Registered pass condition, replacing condition 1.** The localiser is kept **only if** it puts
**≥6 of 10** blind-nominated sites into the top-40 — which it does, exactly, today — *and* the
operator accepts 60% into the artefact plus ~20% reachable only by uncapping. If 60% is judged
insufficient, the fallback above applies: drop localisation, keep the census. **I am not raising
the cap to improve this number in the same document that measured it** — that is tuning after the
fact, and the cap's real value belongs in a trial where the token cost is visible.

**What this does to the invention's status.** It is demoted from "the replacement for the rationale
map" to *one input among the census, with a measured 60% recall and a known blind spot for
interleaved rationale*. The claim that it is where the rationale is remains true in bulk and is
false in detail, and the design says both.

## Open questions

1. **Name:** `kit-entry.sh` vs `kit-inventory.sh` vs `kit-survey.sh`. Cosmetic.
2. **Report cap** — the default K for each section (proposed 400 files / 40 blocks / 5 neighbours). A number, not a principle, but it must be a number.
3. **Do entry questions belong in `paths.design_input`?** They are design input that precedes an ADR, which is why it is proposed — but that directory is otherwise researcher-authored topic docs, and this is orchestrator-authored.
4. **Does the operator accept the unmet hold criterion** (B2) as convention, or is the task's acceptance criterion amended?
5. **Nothing causes this to be run.** No hook, no `--if-stale`, no skill mentions it. `INSTALL.md` §C is the natural home and is another task's scope — does this design take a one-line dependency on it?
6. **Is the first external subject trusted?** It decides whether the judgement half needs an input boundary at all.
7. **`kit-task.sh --title-file`** — worth adding to the filed task, which would remove the paste path entirely?

## What I did not check, and what remains hypothesis

**Verified by reading, this session:** `researcher.md:5`, `adr-scribe.md:5`, `documenter.md:5`, `coder.md:5`; `kit-task.sh` in full; `kit-lib.sh` in full; `hooks/hooks.json`; `.gitignore`; `.claude/project-profile.md`; `schema.sql` `cochange`; `kit-accel.sh:75-163`; `kit-finding.sh:1-60`; `conformance.sh:1-120`, its 40-step list, step 4 (`:213-229`) and step 18 (`:1027-1116`) in full; `DESIGN-NOTES` §0-§2; `LESSONS` §1-§11; all three `T-20260815-*` task files.

**New finding, and §B2 DEPENDS ON IT — the first revision said "depended on by nothing here", which
was false.** `tests/conformance.sh:213-229` exists to catch "an agent told to run a tool it does not
have" and checks only ``Run `kit-*.sh` `` against a missing `Bash`. `agents/researcher.md:30`
instructs the agent to *write* to a directory with no `Write` grant. The step that should have
caught the defect that killed design 1 misses it because its pattern is Bash-only — and §B2's whole
writer table is an argument about which agent may write what, so it rests on this gap being closed
rather than merely noted. Widening the step to cover `Write` is therefore **in scope for this
design**, not filed separately: it is the control that makes the writer table checkable instead of
asserted. `LESSONS` §4 — sweep the shape, do not fix the instance.

**Hypothesis, unmeasured.** The comment-block localiser. I attempted to measure it three times in this session (awk over tracked files, twice; PowerShell once) and the sandbox refused each; rather than assert it, its pass condition is pre-registered above with a delete-not-tune consequence. Two of its four target sites I have read directly and they are genuinely ≥10-line rationale blocks (`kit-finding.sh:1-26`, `kit-lib.sh:71-88`), so the hypothesis is not unsupported — it is unquantified.

**Also unmeasured:** the report's token cost on a 20k-file monorepo (the cap makes it bounded; the bound's *value* is unmeasured); whether the `/* */` state machine is needed on the first real subject; whether 200 lines is the right size estimate.

**Not read:** `kit-index.sh` beyond the cited regions, `kit-status.sh`, `kit-plan.sh`, `kit-preflight.sh`, `kit-guard.sh`, `INSTALL.md` §C, `HANDOFF.md`, `TRIAL-PROTOCOL.md`, and 38 of the 40 conformance step bodies. I did not reproduce any figure in `inventory-*.md` or `measured-index-state.md`; they are taken as given, including the corrected churn column.

**What would have to be true for this to fail:** (1) the comment-block localiser is noise — pre-registered, and the fallback is option C, a skill; (2) rationale is not in the repository at all — the fd trial's nearest measurement is `no roadmap document, so the input the adoption path is designed to consume was absent`, and this design has no answer beyond reporting `0 comment lines` honestly; (3) the operator, holding a proposal and a shell, files candidates before answering questions — nothing prevents it, and B2 says so out loud.

## References

- `.project/tasks/T-20260814-one-entry-mechanism-brownfield-is-the-ge.md`; `T-20260815-kit-task-sh-documents-a-confirm-gate-it-`, `T-20260815-co-change-withheld-disabled-and-empty-ar`, `T-20260815-an-ingest-adapter-can-insert-a-task-row-`
- `docs/design-input/2026-08-15-entry-mechanism.md` (superseded) and both approach reviews, 2026-08-15
- `inventory-ai-assisted-claude-coding-kit.md`, `inventory-actix-web.md`, `inventory-prometheus.md`, `measured-index-state.md`; `docs/TRIALS/2026-08-12-fd-throwaway.md`
- `tooling/schema.sql:55-66`; `tooling/kit-accel.sh:81-163`; `tooling/kit-task.sh`; `tooling/kit-lib.sh`; `tooling/kit-finding.sh:1-26`; `hooks/hooks.json`
- `tests/conformance.sh:213-229` (step 4), `:1027-1116` (step 18, the fixture idiom)
- `docs/LESSONS.md` §1, §4, §5, §6, §10, §11; `docs/DESIGN-NOTES.md` §0, §1, §2
