# Handoff brief — ai-assisted-claude-coding-kit v0.2.0

Paste this into a Claude Code session as context. It is self-contained: requirements,
decisions with rationale, what is built and tested, what is not, and the constraints
that must not be broken.

Repository: https://github.com/raghuveer/ai-assisted-claude-coding-kit (v0.1 released)
Target: commit this work as v0.2.0 under the same repo name.

Status: committed on branch `v0.2.0` off v0.1, pushed, **not released**. The tarball this
brief was originally written against is superseded — git is now the artifact of record.

Two things remain undone before release: load the plugin in Claude Code and run one real
task, and exercise it once on macOS or Linux. A third is easy to miss — `main` still points
at v0.1, and unpinned installs clone the default branch, so **what a new user gets today is
0.1**. See `docs/VERSIONING.md` for the release sequence and §8 for what else is open.

---

## 1. What the kit is

A Claude Code plugin providing a risk-tiered review pipeline (8 subagents, T0–T3 routing)
over a project whose status is **derived rather than maintained**. Used for AI-assisted
coding with a human in the loop — not autonomous agentic runtime.

Constraints that define it:

- **Stack-agnostic.** Must work for projects in any language. Tooling is `bash` +
  `sqlite3` + `git` + `awk` only. No Node, no Python, no PowerShell in the runtime path.
- **Human-legible.** The operator is the orchestrator's peer. Any state a human cannot
  read without running a query is a design failure.
- **Token efficiency is a first-class goal**, weighted equally with output quality.
- **Zero MCP servers.** MCP loads all tool metadata upfront every request; `git` and
  `sqlite3` via Bash cost nothing resident.

---

## 2. The problem being solved

Previous setup: a hand-maintained `STATUS.md` that grew without bound, plus a task list
in CSV, plus a ritual of context-load command → work → checkpoint command → `/clear`.

Failure modes:

- `STATUS.md` update cost is `2 × |file|` per task forever (read-modify-write on a file
  that is O(project history)).
- Two files holding overlapping facts means one is always stale. An agent planning
  against stale status degrades output quality, not just cost.
- `/clear` was destroying prompt cache because the reload assembled a *different* bundle
  each time — paying the 1.25× cache-write premium repeatedly instead of 0.1× reads.

Core insight: **stop maintaining state that can be derived.**

---

## 3. Requirements (as stated)

1. Track project status without a growing file or CSV.
2. Group related tasks by dependency.
3. Order tasks by completion priority.
4. Derive industry-specific accelerators from real work.
5. Support externally-provided technology and industry accelerators, loaded **per
   project**, with contributions derived back after project completion.
6. Each project loads only its related accelerators.
7. Shareable with project team members so they can co-develop.
8. Project data stays in the project's own folder.
9. Distributed as a plugin, not copies.
10. Accelerators deliberately deferred as *content* — seed initial drafts, improve
    iteratively — but the baseline must not foreclose them.

Explicit non-goals for the baseline: no MCP servers, no incremental indexing, no graph
engine, no UI beyond generated markdown, no rewriting pre-adoption git history.

---

## 4. Architecture — decisions and rationale

### 4.1 Three layers, one direction of dependency

```
source of truth   .project/tasks/<id>.md        prose: intent, acceptance criteria
   (text, git)    .project/events.ndjson        append-only state transitions
                  git commit trailers           state changes as a side effect of work
                        │
                        ▼  kit-index.sh         deterministic, no LLM
derived index     .project/index.db             SQLite — gitignored, rebuildable
                        │
                        ▼  kit-status.sh
generated view    STATUS.generated.md           never hand-edited
```

**Nothing is ever written to SQLite directly.** The index is derived; a direct write is
erased by the next rebuild. This is the single most common misunderstanding.

Invariant to preserve: **delete `index.db`, rebuild, output must be byte-identical.**
If something is lost, it existed only in the DB and is in the wrong place.

### 4.2 Commit trailers

Frozen vocabulary — retroactively expensive to change because they are written into
history that will not be rewritten:

| Trailer | Purpose |
|---|---|
| `Task-Id:` | links commit → task; everything rests on this |
| `Task-Status:` | started / progress / blocked / done / abandoned |
| `Tier:` | T0–T3 actually used — required for escape-rate measurement |
| `Fixes-Escape-Of:` | links a fix back to the task whose tier should have caught it |

Validated by a generated `commit-msg` hook, warn or enforce mode.

### 4.3 Task IDs

`T-YYYYMMDD-<slug>`. No central counter (avoids merge conflicts when two branches create
tasks simultaneously), chronologically sortable, legible in `git log` where a human reads it.

### 4.4 Dependency grouping and priority ordering

`kit-plan.sh` — graph work in awk (Kahn's algorithm gives cycle detection free):

- `blocked_by` frontmatter → `depends_on` edges
- Union-find → clusters (connected components)
- Kahn → topological layers
- Score = `w_unblocks × transitive_dependents + w_escapes × escapes + w_tier × tier_rank`

**Rule: topology beats priority.** A high-scoring task blocked by a low-scoring one
cannot go first. Score ranks *within* a layer, never across layers.

**Cycles are withheld and named, never ordered around.** A cycle is a data error in
someone's `blocked_by`; sequencing it produces a confident wrong answer.

### 4.5 Accelerators

Technology (`go`, `rust`, …) and industry (`bfsi`, `govtech`, …) profiles.

- **Bound to agents, not sessions.** `resolve --agent coder` returns the stack profile;
  `--agent compliance-auditor` returns the industry obligations; `--agent orchestrator`
  returns **nothing**. An accelerator is small at rest and large when loaded — keeping it
  out of the orchestrator's window is the token lever, because that window is re-read
  every turn.
- **Ship centrally, bind per project, pin the version.** Distribution is free (unread
  files cost zero); context is not. Selection is a deterministic path lookup from
  `project-profile.md`, never a model judgement.
- **Contribution is a proposal, never a write.** An accelerator that auto-accumulates
  compounds one project's mistake across every project that later loads it.
- **Export is aggregate-only by construction.** `(kind, key, class, n, vindicated,
  refuted, project-hash)`. The query cannot select finding text, paths, task ids or
  titles. Required for BFSI/GovTech client work — this must stay structural, not
  procedural.
- **Promotion ladder:** 1 occurrence = not a pattern → ≥N in one project = project
  overlay → **≥1 in ≥2 distinct projects** = shared accelerator candidate. Refutations
  block promotion regardless of volume.
- **Provenance per line:** `[seeded]` vs `[earned]`. Seeded drafts are fine; unmarked
  seed content becoming permanent is the failure mode.

### 4.6 Context management

Layered by volatility:

| Layer | Content | Cost |
|---|---|---|
| Stable prefix | `CLAUDE.kit.md`, `project-profile.md`, agent definition | cached, 0.1× |
| — cache breakpoint — | | |
| Volatile tail | one task's spec, specific files, tool output | paid fresh |
| Outside context | tasks, events, index, plan, findings | zero |

Consequences:

- `/clear` is cheap because the stable layer is byte-identical across sessions.
- Session cost no longer grows with project age (O(open work), not O(history)).
- **The plan is state, not context.** `/goal` computes an ordering once, writes it to
  `plan_item`, ends. Each task session reads one row (~20 tokens). An n-task goal becomes
  n constant-window sessions instead of one quadratic session — and survives `/clear`,
  session end, or a crash.

### 4.7 Extension-layer budget

Measured with `claude --plugin-dir . plugin details coding-kit`, superseding the estimates
this section originally carried:

| Layer | Contents | Resident cost |
|---|---|---|
| Always-on | tiering obligation, write boundary, where truth lives (~15 lines) | small, cached |
| Hooks (2) | write guard, checkpoint, trailer validation | zero — harness-only |
| Skills (5) | task-context, tier-classify, verify-ladder, status-report, checkpoint | **~440 tok** (80–100 each) |
| Subagents (8) | the reviewers | **~840 tok** — descriptions are resident |
| MCP | none | zero |
| | | **~1,259 tok always-on** |

**Correction to the original estimate: subagents are not "zero until spawned".** Routing
matches the request against each agent's `description`, so all eight sit in context on
every request. At ~840 tok they are two thirds of the always-on cost — more than the five
skills combined, and the opposite of where this section first pointed the budget.

Both are resident in **every** project on the machine, including ones not using the kit.
Keep the skill count fixed at five and treat a ninth agent as a larger standing charge
than a sixth skill. Accelerators must arrive as bundled reference files inside existing
skills, never as new skills or agents, or resident cost grows linearly with the catalogue.

Agent descriptions are therefore the largest single lever on resident cost — and they are
currently 2–4 sentences each. Shortening them trades against routing accuracy, so measure
routing before and after rather than trimming on principle.

### 4.8 Commands → skills → hooks

`commands/` is legacy for plugins; `skills/` is current. But it is a three-way split,
not a rename:

| Was | Now | Why |
|---|---|---|
| `/resume-context` | skill `task-context` | model-invocable — Claude should reach for it |
| `/checkpoint` (68 lines) | skill + `Stop` hook + `kit-index.sh` | mechanical steps became a hook; a checkpoint you must remember is skipped exactly when sessions run long |
| `/drift-check` (31 lines) | mostly **retired** | item-level drift is now structurally impossible; status is regenerated from task files and trailers so it cannot disagree with git |

Recommendation: **skills only, no command aliases.** Skills are invocable by name; an
alias costs a second resident description per ritual for no capability.

### 4.9 Verification ladder

Stated as **obligations with declared substitutes**, not fixed steps, because mutation
tooling is unevenly distributed (good: JS/PHP/Python/Java/Rust; thin: Go; painful: C++).

An unavailable rung is **declared** in `project-profile.md` (empty value) and **raises
the tier** — less mechanical verification means more adversarial reading, not a lower
bar. Silent absence is the failure: a T3 pipeline quietly reviewing at T2 depth.

### 4.10 Model tiering

Different model families for coder vs reviewer is not currently feasible. Substitutes,
in order of value:

1. **Context independence beats weight independence.** Never pass the coder's rationale
   to the reviewer — pass the diff and acceptance criteria only. Shared context is
   likely a bigger source of correlated blind spots than shared weights.
2. **Deterministic gates are the only genuinely uncorrelated reviewer.** Linter,
   typechecker, mutation, race detector share zero weights with any model. Order:
   static → tests → mutation → LLM review, reviewer sees only what survived.
3. Capability asymmetry (reviewer one tier above coder).
4. Objective asymmetry ("find the failure mode; assume one exists").

Sample ~5% of T0/T1 router classifications and re-run at T2 — under-tiering is invisible
until something escapes.

---

## 5. Team sharing

The kit is machine-wide and versioned; project data travels with the repo.

| Path | Git | Why |
|---|---|---|
| `.claude/project-profile.md` | commit | team needs the same tiering rules and pins |
| `.project/tasks/*.md` | commit | shared backlog |
| `.project/events.ndjson` | commit | `merge=union` in `.gitattributes` — append-only, ordering irrelevant because the indexer sorts by timestamp |
| `.project/index.db` | ignored | derived; binary merges unresolvable |
| `STATUS.generated.md` | ignored | generated; committing means churn every rebuild |
| `.git/hooks/commit-msg` | **cannot be** | git never shares hooks |

**Ownership is derived, not assigned:** commit author of a task's latest `started` event
becomes its owner. `STATUS.generated.md` shows `@name` with nothing to keep in sync.

The hook is **generated, not symlinked** — the plugin path differs per machine, and
`.git/hooks` is per-clone. This is why every team member must run `kit-init.sh` after
cloning, and re-run it if the plugin moves.

---

## 6. Current state — built and tested

**Structure (validated, 6 ok / 0 warnings / 0 errors via bundled `validate.py`):**

```
ai-assisted-claude-coding-kit/
├── .claude-plugin/     plugin.json (name: coding-kit, v0.2.0), marketplace.json
├── agents/             8 agents, FLAT (see §7 bug 1)
├── skills/             5, each a directory with SKILL.md
├── hooks/hooks.json    PreToolUse guard, Stop checkpoint — ${CLAUDE_PLUGIN_ROOT}
├── tooling/            14 scripts + schema.sql
├── templates/          project-profile, task, CLAUDE.kit + legacy copies
├── accelerators/       technology/go, industry/bfsi (seeded drafts)
├── docs/               HANDOFF, VERSIONING, ADAPTERS, DESIGN-NOTES, MODELS, MIGRATION, agents
├── legacy-commands/    3 originals, kept for reference, not wired
├── INSTALL.md  validate.py  README.md  LICENSE
```

**Scripts:** `kit-init`, `kit-task`, `kit-index`, `kit-plan`, `kit-status`, `kit-finding`,
`kit-vindicate`, `kit-accel`, `kit-event`, `kit-checkpoint`, `kit-guard`, `kit-lib`,
`commit-msg`.

**Verified end to end:**

- inert in a repo with no `project-profile.md` (silent, exit 0)
- `kit-init` idempotent; distinguishes new adoption from joining
- trailer hook correct in warn and enforce modes
- delete `index.db` + rebuild → byte-identical output
- malformed frontmatter and junk NDJSON warn and skip, do not fail
- diamond dependencies, disconnected clusters, and a 3-cycle
- two-developer simulation: Alice adopts and starts work, Bob clones, runs init,
  rebuilds, sees the same status including `@Alice`
- accelerator per-agent binding (orchestrator correctly receives nothing)
- export leaks no task ids, paths, or titles
- clean extraction from the tarball, full chain re-run

---

## 7. Bugs found during testing — all fixed, worth knowing

1. **Agents were in `agents/core/`.** Plugin discovery is flat — nested agents never
   load, and `agents/README.md` would have been parsed *as an agent*. Flattened; READMEs
   moved to `docs/`. (`core/`/`overlay/` only existed for `sync-agents.ps1`, now retired.)
2. **`commit-msg` hook loaded its library from a hardcoded path — and when it failed,
   the commit went through anyway.** A validation hook that silently passes while the
   repo looks protected is the fail-open class the security-reviewer exists to catch.
   Now generated with the resolved path, and fails loudly.
3. **Task existing only in commits never had state or tier derived** — ordering bug,
   rows backfilled after derivation ran.
4. **`finding.tier` resolved before task tiers existed** — silently reported every
   finding as untiered, breaking escape-rate-by-tier, the headline metric.
5. **`kit-finding.sh` took six positional args with no validation** — wrong order wrote
   plausible garbage into the table accelerators are derived from. Now named flags with
   validated vocabularies.
6. **Domain-tagged compliance findings were surfacing as technology candidates**, which
   would have polluted the Go profile with BFSI obligations.

---

## 8. Not built — open work

- **Cross-project accelerator aggregation.** `export` writes per-project NDJSON;
  something must collect across projects and count distinct project hashes. Blocked on a
  layout decision: public marketplace folder vs private collection repo. Recommendation
  given the client mix — private collection, public promotion.
- **Accelerator line budget and eviction.** Recommended, not implemented. Every
  mechanism currently only adds; an accelerator that grows monotonically eventually costs
  more than it buys, multiplied across every project that pins it. Eviction order:
  refuted → stale → lowest occurrence.
- **Priority weights are unvalidated.** `unblocks×3 + escapes×2 + tier` is defensible,
  not proven. Recalibrate once escape data exists.
- ~~**`claude plugin validate` not run**~~ — **done.** Both manifests pass `--strict`,
  exit 0, on Windows with CLI 2.1.220. Note it validates ONE manifest, chosen from the
  path given: plain `.` resolves to `marketplace.json` and leaves the plugin unchecked,
  so `claude plugin validate .claude-plugin/plugin.json --strict` is also required.
  `validate.py` remains the structural check and is complementary, not redundant.
- ~~**A malformed event line still produces a degenerate empty finding row**~~ — **done.**
  `kit-index.sh` drops findings carrying no class and reports the count on stderr. A
  classless finding cannot be grouped, counted or promoted, so it only added noise.
- ~~**`%(trailers:...)` needs git ≥ 2.32**, no version check~~ — **done.** `kit-index.sh`
  warns on older git and says what degrades: every commit indexes as untagged, which looks
  like an idle repository rather than a broken one.

---

## 9. Measurement — do this before switching over

`ccmetrics.py` (separate, Python, deliberately NOT in the plugin — it reads
`~/.claude/projects/` machine-wide, which would violate the kit's write-boundary
invariant, and would impose a Python dependency on a stack-agnostic kit).

```
python3 ccmetrics.py --split <a date BEFORE any changes> --repo <path>
```

Reports cache-read ratio, effective input multiplier (0.10×–1.25×), peak window per
session, tokens per commit, model mix. **Run it before installing** — the control period
cannot be reconstructed later.

Definition of "better than existing", agreed up front so the baseline phase can end:
three numbers (tokens per merged change, cache-read : cache-creation, escape rate) plus
one qualitative gate — **a finding, from someone who is not the author, that the core
method caught and their prior setup would have missed.**

Caveat to hold onto: every metric here improves if you simply review less. Token
efficiency is necessary and not sufficient; pair it with escape rate before concluding
anything.

---

## 10. Sequencing

1. Run `ccmetrics.py` for the control period. **Cannot be done later.**
2. `python3 validate.py`, plus BOTH official checks — `claude plugin validate . --strict`
   (marketplace) and `claude plugin validate .claude-plugin/plugin.json --strict` (plugin).
3. Test locally: `claude --plugin-dir ./ai-assisted-claude-coding-kit`, iterate with
   `/reload-plugins`.
4. Adopt in one project. Delete the old `STATUS.md` and CSV — delete, not deprecate.
5. Turn on instrumentation (findings + vindication). Ships nothing visible, which is why
   it gets skipped; everything later depends on it.
6. Release per `docs/VERSIONING.md`: merge to `main` first — unpinned installs clone the
   default branch, so a release that stops on a side branch has not shipped — then tag
   `v0.2.0` on main and hand pinned versions to other developers.
7. Collect paired feedback: same repo, their prior fortnight vs the kit. The load-bearing
   question is **"what did you turn off, and why?"** — anything switched off cost more
   than it returned, and that is the prioritised backlog handed over.

---

## 11. Constraints that must not be broken

- Delete-and-rebuild must stay lossless. Nothing exists only in the index.
- No core agent names a stack-specific tool. Everything indirects through
  `project-profile.md`.
- The kit never writes outside the project root.
- Inert without `project-profile.md`.
- Findings carry language and defect class from day one — the only genuinely lossy thing
  if skipped, since findings cannot be retroactively tagged.
- Accelerator export stays aggregate-only by construction, not by convention.
- Skill AND agent counts stay fixed; accelerators are bundled files, not new skills or
  agents. Agent descriptions are resident (~840 tok for eight), so a ninth agent costs
  more at rest than a sixth skill.
- Topology beats priority. Cycles are withheld, not reordered.
- Zero MCP servers.
