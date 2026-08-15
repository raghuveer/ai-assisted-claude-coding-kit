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

**C. No script — a skill instructing the model to run `git` itself.** Zero code, maximum flexibility, ~88 tok resident. Rejected in design 1 for unbounded context and non-reproducibility; **it is a much closer call now**, because the deterministic half is thinner than design 1 assumed. It still loses on the one job the tool does best: counting comment lines and locating comment blocks across 1,665 files is arithmetic, not judgement (`LESSONS` §6), and a model doing it produces a number nobody can regression-test or compare between trials. Kept explicitly as the **fallback** if the pre-registered pass condition below fails. *Reversibility: highest.*

**D. `ingest.extra` adapter emitting candidate rows.** **Reject**, and worse than design 1 knew: an adapter genuinely *can* `INSERT INTO task` (`T-20260815-an-ingest-adapter-can-insert-a-task-row-`), so this route puts unconfirmed candidates in the backlog count and the escape-rate denominator with nothing refusing them. *Reversibility: poor — ids in trailers are permanent.*

**E. Extend `kit-index.sh`.** **Reject**, unchanged: `--if-stale` runs per session; a whole-tree walk is once per adoption.

**F. `--confirm` batch writer.** Excluded by decision 4. A gate satisfied by passing a flag is laundering.

## Recommendation — option B

### B1. What the deterministic half emits

`kit-entry.sh` (name in Open questions). **One row per tracked file, no grouping.** Two outputs under `paths.state`, both derived and both added to `.gitignore`:

- `entry-facts.tsv` — complete, one line per file: `path · ext · lines · comment_lines · comment_blocks · commits · first · last · authors · doc_shaped · cochange_degree`. Uncapped, cheap, greppable.
- `entry-report.md` — **bounded**, model-facing and human-readable. Every section is a top-K with `showing K of N` and the dropped count printed beside it (`LESSONS` §11, and the `Below threshold` precedent in `kit-accel.sh`).

Five emissions, and what measurement did to each:

1. **Per-file history** (`commits`, `first`, `last`, `authors`) — **kept**. The collapse measured on prometheus and actix-web is an artefact of *aggregating to a directory*; `(root)` absorbing 13,258 commits is a true fact about `CHANGELOG.md` and `go.mod`, and it is only meaningless once it is called "the root area". Decision 1 is therefore not merely a constraint — it is what rescues this input.
2. **Comment localisation** — **the replacement for the rationale map, and the only new invention here.** For each file, count comment lines by extension (`#`, `//`, `///`, `--`, plus a small `/* */` state machine), and emit every **run of ≥10 consecutive comment lines as `path:start-end length`**, top 40 by length. This is where the rationale actually is on all three subjects. Locating and counting is deterministic; reading those ranges for meaning is the model's job, and it reads *kilobytes of named line ranges* instead of a tree. The tool never says "no rationale here" — only "0 comment lines here", which is a count.
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
| the proposal *text* | **`researcher`, unchanged and read-only** | `Read, Grep, Glob, WebFetch, WebSearch` (`researcher.md:5`) — it **returns**, it does not write |
| `<paths.state>/entry-candidates.md` (disposable, gitignored) | the **orchestrator**, via `Write` | writes the returned text verbatim |
| `<paths.design_input>/YYYY-MM-DD-entry-questions.md` (**committed**) | the **orchestrator**, via `Write` | |
| answers → a decision record under `<paths.adr>` | **`adr-scribe`** | `Read, Grep, Glob, Write` (`adr-scribe.md:5`) — already the house writer for answered questions |
| task files | **the operator**, running `kit-task.sh` lines | |

Why this split: it adds **no agent** (§0), grants **no new write capability to anything**, keeps the large report out of the main context (researcher reads it; only the much smaller proposal transits), and matches `LESSONS` §5 without adding a parser — the orchestrator has `Write`, so nothing needs scraping *or* deserialising. Do **not** grant `researcher` `Write`. Do not create an `entry-analyst`. On a small repo the orchestrator could do both halves itself; the crossover is simply `report ≫ proposal`, so the subagent wins on exactly the large repos this is for.

**Honest statement of the control, per decision 4.** `kit-entry.sh` cannot write a task file — that is structural, and it is the *only* structural part. The orchestrator holds `Write` and `Bash`; `kit-guard.sh` permits every in-root path (`hooks/hooks.json:5` matches `Write|Edit|NotebookEdit`, and `kit-guard.sh` allows in-root writes); `kit-task.sh` is not a gate. So: **the task file's acceptance criterion "hold the task list unconfirmed until questions have answers" is NOT met by this design.** It is met by convention. That is a known unmet criterion to be accepted or rejected at the walkthrough, not a gap to be papered over with a flag.

One live boundary, named because design 1 did not: the model is handed named files from an **untrusted** third-party repository to read, and then emits shell lines a human pastes. Candidate titles are restricted to `[A-Za-z0-9 ._-]` and single-quoted; the real fix is `kit-task.sh --title-file`/stdin, which deletes the shell round-trip and belongs on the filed `kit-task.sh` task.

### B3. The fixture (must be able to fail)

One step in the existing grammar — `if step "an undocumented choice is reported and no task file appears"; then … fi` — modelled on `tests/conformance.sh:1027`. Fixture: `git init`, `kit-init.sh`, `src/retry.go` containing `maxRetries = 7` with **no** comment, `src/cache.go` carrying a 12-line rationale block, two commits.

**Presence assertions (each red under a named mutation):**
- `grep -qE '^src/retry\.go\b.*\bcomment_lines 0\b' entry-report.md` — red if the tool skips zero-comment files.
- `grep -qE '^src/cache\.go:[0-9]+-[0-9]+ +1[0-9]$'` in the comment-block section — red if the block scanner is removed or its threshold moved.
- `grep -qx 'tracked_files 2'` and `grep -qx 'commits 2'` — exact values pinned, not `!= 0`.
- `grep -q 'co-change: '` with the state word present — red if the ambiguity handling is dropped.

**Absence assertions (necessary, not sufficient), by count not listing:** task files under `paths.tasks` equal before and after; `SELECT COUNT(*) FROM task` unchanged after a reindex; no line in either artefact matching the task-file grammar.

The pairing is the point: the run proves the tool **did the work and still wrote nothing**. A `kit-entry.sh` of `exit 0` plus a `touch` fails four assertions. A second step covers the single-commit case by asserting `history degenerate: single-commit` is present. **The model half cannot be gated by a fixture** — stated, not implied.

### B4. Self-ingest pass condition, registered before the run

AC5's "usable" means all five, measured on this repository as-is:

1. The top-40 comment-block list contains **≥3 of these 4** known rationale sites: `kit-index.sh` §4 (~935-961), `kit-finding.sh:1-26`, `kit-lib.sh:71-88` (`kit_via_vocab`), `schema.sql:55-59`. **Fewer than 3 → the localiser is noise and is deleted, not tuned** (`LESSONS` §5), and option C becomes the design.
2. ≤25 candidates after dedup against the 93 existing task nodes.
3. Between 1 and 15 questions, each naming a path and a line range that exist.
4. Zero candidates duplicating an open task, checked by the operator against `paths.tasks` — not asserted by the model about its own output.
5. Zero new files under `paths.tasks` attributable to the run.

**What would change my mind:** condition 1 failing (→ option C); a trial showing candidates routinely >30 (→ reopen the batch-writer question the operator excluded, with evidence); rationale living outside the repo on the first external subject (→ the tool is a file census and the questions come from the operator interview, which is a smaller thing again).

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

**New finding, offered separately and depended on by nothing here.** `tests/conformance.sh:213-229` exists to catch "an agent told to run a tool it does not have" and checks only ``Run `kit-*.sh` `` against a missing `Bash`. `agents/researcher.md:31` instructs the agent to *write* to a directory with no `Write` grant. The step that should have caught the defect that killed design 1 misses it because its pattern is Bash-only. This is `LESSONS` §4 — sweep the shape, do not file the instance.

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
