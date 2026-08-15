# Entry mechanism — turning an existing codebase into a candidate task list

Design input for `T-20260814-one-entry-mechanism-brownfield-is-the-ge`. Not a decision record.
Written before implementation, to be attacked by `approach-reviewer` and walked through with the
operator before anything is built.

## Problem statement

Every mechanism in the kit is downstream of "a task already exists". `kit-index.sh` derives state
from task files, `kit-plan.sh` orders them, `task-context` loads one, the review chain gates work
on one. Nothing produces the first task from a codebase.

The task file settles the framing: brownfield is the general case, greenfield is brownfield with
an empty inventory, modernization is brownfield plus a source→target stack delta. This document
decides what is inventoried, how an undocumented design choice is handled, the output shape, how
the other two starting conditions specialise the same run, and where the code lives.

## Assumptions and constraints

- `bash` + `sqlite3` + `git` + `awk`. `python3` exists at exactly one boundary (`kit_findings.py`,
  the JSON reader/writer). This design adds no second boundary.
- Nothing is written to SQLite directly. Delete the index, rebuild, lose nothing.
- The kit proposes; a human confirms. Nothing files work unilaterally.
- The delivered product stays ordinary, and every artefact stays legible without this kit.

**Not solving here.** The component model (`T-20260731-component-model-for-polyglot-and-moderni`)
— this design must neither depend on it nor pre-empt its field names, which its own note marks
"seeded, not earned". The `INSTALL.md` §C rewrite (`T-20260808-adoption-paths-for-an-empty-folder-and-f`).
The trial itself (`T-20260808-trial-the-kit-on-one-unfamiliar-brownfie`). Adapters for a specific
issue tracker — those already exist and solve a different problem (see Option 1).

## The finding that shapes the rest

I checked this repository for decision records. There are none: `find` returns only
`agents/adr-scribe.md` and two task files whose titles mention ADRs. There is no `docs/design-input/`
either, and no profile key declaring where either lives — `adr-scribe.md:13` says "the project's ADR
directory" and nothing anywhere names it. Meanwhile 167 tracked files carry an unusual density of
rationale, in code comments, `docs/LESSONS.md`, `docs/DESIGN-NOTES.md`, task-file `## Notes`
sections and commit bodies.

So the obvious detector — *no ADR references this file, therefore its design choices are
undocumented* — would raise 167 questions against the one repository whose rationale is most
thoroughly written down. **Absence of an ADR is not absence of rationale**, and a mechanism that
conflates them fails its central rule in the direction the rule was written to prevent: it turns a
documented choice into a question, and a hundred bad questions are indistinguishable from noise, so
the real ones get skipped.

This drives the design below. The tool maps **where rationale lives** per area of the tree; it never
asserts that rationale is absent.

## Existing code considered

| Path | State | Bearing |
|---|---|---|
| `tooling/kit-index.sh` §2b co-change | **Complete-but-narrow** | Derives structural signal from raw history with no trailers, hub-filters, and withholds itself above `cochange.max_degree`. The only signal available on day one. **Read the `cochange` table; never recompute it.** |
| `tooling/kit-index.sh` §1–3 + `docs/ADAPTERS.md` | **Complete, and the wrong door** | The ingest seam admits *tasks*. A candidate is not a task. See Option 1. |
| `tooling/kit-accel.sh propose` (lines 81–163) | **Complete** | "Contribution is a proposal, never a write." Writes `accelerator-proposal.md`, checkboxes, applied by nobody. This is the artefact shape to copy. |
| `tooling/kit-task.sh` | **Complete** | One task per invocation, from flags, header comment: "a researcher proposes a breakdown, a human confirms and edits, then this writes". The confirm step already exists. |
| `tooling/kit-status.sh` | **Complete** | House conventions for a derived markdown report and for naming what could not be determined. Match them. |
| `schema.sql`: `node.type='adr'`, `edge.rel` `constrained_by`/`covers` | **Stub** | Declared, queried by `task-context` step 5, **written by nothing** — I grepped `tooling/` and found no writer. Free hooks, as `DESIGN-NOTES` §1 claims. |
| `DESIGN-NOTES` §1 component model, §2 solution overlay | **Absent (proposed)** | §2 is where the modernization delta belongs. Neither is built. |
| `.claude/project-profile.md` keys | **Absent** | No `paths.adr`, no `paths.docs`. The rationale map needs one; see Open questions. |
| `docs/LESSONS.md` §6 | — | "Models for judgement; deterministic code for data." `T-20260814-documents-and-adrs-are-produced-by-three` restates it as an acceptance criterion. This is the seam the design splits on. |

## Alternatives considered

### Option 1 — an `ingest.extra` adapter emitting candidate rows

Reuses the documented seam; candidates appear in the index and flow to `kit-plan.sh` for free.

**Reject.** Candidates would land in `task` rows — hence in the backlog count, the plan, and the
escape-rate denominator — before any human confirmed them. `kit-index.sh` lines 935–961 already
refuses exactly this shape for a typo'd `Task-Id`, at length: "silently INVENTED is worse than
either, because it reads as work." It also breaks the invariant the whole seam rests on: a
candidate's only home would be the analysis run, so delete-and-rebuild loses it. *Reversibility:
poor* — once an id is in the index and a human puts it in a trailer, it is permanent.

### Option 2 — a skill only; the model walks the tree

No new script. Maximum flexibility about weird repositories.

**Reject.** Unbounded context — the "reading a directory to get oriented" failure `task-context`
exists to prevent. Non-reproducible: two runs give different inventories, so nothing can be
regression-tested and no figure from a trial is comparable to the next. And it puts a model on a
grep's job. *Reversibility: high* (delete one file), which is its only merit.

### Option 3 — extend `kit-index.sh`

**Reject.** `kit-index.sh --if-stale` runs at the start of every session; a whole-tree walk is a
once-per-adoption act, not derived state, and paying it per session inverts the optimisation
section 1 exists for. It also grows the file the backlog already wants decomposed
(`T-20260808-decompose-kit-index-along-the-seam-it-al`).

### Option 4 (recommended) — one tool for the data, an existing agent for the judgement, an inert proposal

**`kit-inventory.sh`** (name undecided). Deterministic, two runs byte-identical. Reads:

- `git ls-files` → the tree; extension and marker files (`go.mod`, `*.csproj`, `package.json`,
  `Dockerfile`) → the stack per directory;
- `git log --name-only` → per-area churn, age, last-touched, author spread;
- the existing `cochange` table → structural clusters, or the fact that it was withheld;
- `paths.tasks` and commit bodies → which areas already have written rationale;
- a *classification by name and path* of documentation-shaped files. It enumerates them. It does
  not read them for meaning.

Writes **one markdown report** to `<paths.state>/inventory.md` and nothing else. No task file, no
SQL, no index row. Sections, in order: what was read → what could not be read → areas, with the
rationale sources found for each → raw counts.

**The judgement half** is the `researcher` agent, which already exists and is already resident, so
it adds no standing charge (`DESIGN-NOTES` §0: an agent is a permanent charge, a reference file is
not). It is given the report plus a bounded, named file list, and writes
`<paths.state>/entry-proposal.md` in the `accelerator-proposal.md` shape:

```
## Open questions          numbered, each with the evidence path that raised it,
                           a blank answer slot, and NO checkbox
## Candidate tasks         [ ] title, evidence paths, and the literal kit-task.sh line
## Could not determine     mechanical gaps from the report, plus judgement gaps
```

Questions first, so a reader meets them before the candidates.

**Confirm** is the operator answering the questions, then running the `kit-task.sh` lines they
accept. **There is no code path from the proposal to a task file.** That is the whole of the
structural prevention, and it is exactly as strong as that sentence — no more (see Scepticism).

**The fixture** (acceptance criterion 3) builds a repository containing an undocumented choice,
runs `kit-inventory.sh`, and asserts: exit 0 with a report; the `paths.tasks` listing byte-identical
before and after; zero new `task` rows after a reindex; no line in the report matching the task-file
grammar. That proves the *tool* refuses. A fixture can gate the model only against a recorded
transcript — say so rather than implying the refusal is proven end to end.

**Greenfield** is this run with every count at zero. Nothing special-cases it. The one real
requirement is that the tool must not error on an empty tree and must distinguish "nothing there"
from "did not look" — `kit-index.sh` has been bitten by both shapes already (awk with no file
operands hangs; an empty task file versus an unreadable one), so the discipline is borrowable.

**Modernization** is this run plus an input. The source→target delta belongs in the solution
overlay (`DESIGN-NOTES` §2: project-scoped, given not earned, never exported), not in anything the
tool derives — the repository cannot know its own target stack. The inventory says what exists, the
overlay says what the target is, and the candidate list is the difference. **No second code path:
the delta changes what the model is given, not what the tool does.** When `component:` lands, the
delta becomes structured and this design is unaffected.

### Option 4b — add `kit-inventory.sh --confirm`, gated on unanswered questions

A batch writer that reads checked candidates and refuses while any question is unanswered. It makes
the refusal a mechanical gate rather than an absence, which is easier to test and cheaper for an
operator facing forty candidates. It also adds a code path that *can* write task files, defended by
a check that can be waved through — against LESSONS §5 ("prefer deleting a component to hardening
it") and §1. **Defer** until the trial measures how much the hand-paste actually costs.

## Recommendation

**Option 4**, deferring 4b. Smallest new surface: one script, one existing agent, one existing
confirm command, one artefact shaped like one that already ships. Every existing mechanism is
reused at its own seam — co-change read not recomputed, the propose pattern copied not reinvented,
`kit-task.sh` as the gate it already documents itself to be. Nothing unconfirmed enters the index.

**What would change my mind:**

- Trial candidate lists routinely over ~30 items and pasting dominates operator time → 4b earns its
  place.
- The rationale map reads as noise on a real polyglot repository → drop the map, keep the inventory,
  and let the model do the whole judgement half from a bounded file list.
- Real subjects keep their backlog in a tracker → Option 1's adapter is right *for the confirmed
  backlog*. It stays wrong for candidates. These are not competing.

## What I did not check, and what is hypothesis

**Argued from code I read:** the ingest seam and its explicit refusal to invent tasks; `kit-accel.sh
propose`; `kit-task.sh`'s gate; `adr`/`constrained_by`/`covers` having no writer; the profile having
no ADR-path key; this repository having zero ADRs against 167 tracked files.

**Hypothesis, n=0:** that extension-and-marker stack classification is useful on a real polyglot
repository; that the rationale map is legible rather than noise; that the candidate count is
manageable. The nearest evidence on the last point is discouraging — `kit-plan.sh` measured at its
worst on a backlog it did not author (22 tasks collapsed to 2 layers, the scaffold everything
depended on ranked eleventh).

**Not checked:** I could not query `.project/index.db` in this session (sqlite reads were blocked),
so I make **no claim** about this repository's current co-change density, whether the graph is
withheld, or how many file nodes exist. The self-ingest test must measure that first. I also read
`tests/conformance.sh` only as far as its header, so the fixture above is a shape, not a verified
step, and I did not read `kit-guard.sh` or `kit-preflight.sh`.

**What would have to be true for this to fail:**

1. **Documentation on real subjects is mostly non-text** — PDF, Confluence, Word, diagrams. Then the
   tool enumerates filenames and knows nothing, the report is a file list plus a large "could not
   read" section, and the value collapses back into the model. That is Option 2 with extra steps.
2. **The model writes task files directly.** `kit-guard.sh` blocks Write outside the project root but
   not Bash writes, per `T-20260808-trial`'s own note. So the refusal is *structural for the tool*
   and *conventional for the model*. Claiming it structural outright would be the `false-rationale`
   class this kit refuses.
3. **"One mechanism" is nominal.** If greenfield ends up needing a different prompt, artefact and
   confirm step, the unification is a claim rather than a property. The test: the greenfield run must
   produce the same file with zeroes in it.

## Open questions

1. **Where do decision records live?** No profile key declares it; `adr-scribe` names a directory
   that does not exist here. Does `paths.adr` get added, or is rationale-location prose in the
   profile? This blocks the rationale map.
2. **Is the proposal committed or derived?** Questions are a durable record of what was asked;
   candidates are disposable once confirmed. They may not belong in one file.
3. **Where does an answered question land** — an ADR, the overlay, or profile prose? Three homes
   exist, and `T-20260814-documents-and-adrs-are-produced-by-three` already notes documents come
   from three agents and are reviewed by none.
4. **Who drives the judgement half** — `researcher` reused, or a new skill? A skill is a permanent
   resident charge (~88 tok on the current five-skill average) for a once-per-project act.
5. **Name:** `kit-inventory.sh`, `kit-survey.sh`, `kit-entry.sh`.
6. **Does the self-ingest test run against this repository as-is**, with zero ADRs? As-is is the more
   honest test and the more uncomfortable one.

## References

- `.project/tasks/T-20260814-one-entry-mechanism-brownfield-is-the-ge.md`
- `tooling/kit-index.sh` — ingest seam (lines 30–43), co-change (608–700), phantom-task refusal (935–961)
- `tooling/kit-accel.sh` — propose (81–163); `tooling/kit-task.sh` — the confirm gate
- `tooling/schema.sql` — `node.type`, `edge.rel`; `docs/ADAPTERS.md` — the `ingest.*` contract
- `docs/DESIGN-NOTES.md` §0, §1, §2; `docs/LESSONS.md` §1, §5, §6
- `skills/task-context/SKILL.md` steps 5–6; `INSTALL.md` §C
- Related tasks: `T-20260808-adoption-paths-for-an-empty-folder-and-f`,
  `T-20260808-trial-the-kit-on-one-unfamiliar-brownfie`,
  `T-20260731-component-model-for-polyglot-and-moderni`,
  `T-20260814-documents-and-adrs-are-produced-by-three`
