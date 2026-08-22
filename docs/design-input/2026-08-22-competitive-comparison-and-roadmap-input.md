# Eight kits read at source: what the comparison changes, and what it does not

Design input, 2026-08-22. Produced from a working session between the operator and the coding
agent, prompted by the operator asking which tools compete with this kit and, after a first answer
that was partly wrong, asking for that answer to be verified against the tools' own code.

It records **what was measured, what it refutes, and what it suggests** — not a survey. Facts
carry the file they came from. The two kinds of claim are marked: unmarked statements were read
out of a repository today, and `[judgement]` marks an opinion a future session is free to
overturn.

> **FRAMING CORRECTED THE SAME DAY.** `2026-08-22-auto-mode-is-a-graduation.md` supersedes this
> document's **§3.1** and re-cuts its **§6**. Two errors: LangGraph was given as an *example use
> case* and is promoted here to a design pillar, which over-reads one example into a category; and
> the roadmap in §6 is organised by competitive gap, when the organising axis is the operator's
> terminal goal — multiple open-source projects developed in auto-mode. **§1, §2, §4, §5 and §7
> stand**: the measurements are unaffected by why they were taken. Corrected by banner rather than
> rewrite, for the reason §7 of that document gives.

**This does not replace `docs/COMPETITIVE-LANDSCAPE.md` (2026-08-08).** That memo asked to be
re-verified before acting on it, because its subject moves fast. §2 below does that. Read it
first; most of it still stands.

**Nothing here proposes marking anything done, and no defect is filed from it.** Where the
comparison implies work, it is written as a roadmap candidate with what would falsify it.

---

## 1. Method, and what it cannot see

Eight repositories were cloned at `--depth 1` on their default branches and searched by keyword
over source, docs and tests:

| | stars | what it is |
|---|---|---|
| `obra/superpowers` | 275,897 | skills framework + SDD methodology, Claude Code and 8 other hosts |
| `github/spec-kit` | 130,757 | spec-driven toolkit, agent-agnostic, with an extension catalogue |
| `Fission-AI/OpenSpec` | 65,875 | spec-driven change management, auditable before implementation |
| `bmad-code-org/BMAD-METHOD` | 52,158 | role-agent methodology across the delivery cycle |
| `eyaltoledano/claude-task-master` | 28,009 | PRD → task decomposition, multi-host |
| `gastownhall/beads` | 26,513 | Dolt-backed graph issue tracker for agents |
| `automazeio/ccpm` | 8,346 | PM layer over GitHub Issues + worktrees |
| `MrLesk/Backlog.md` | 6,519 | markdown backlog shared by humans and agents |

Star counts are from the GitHub API today. **Beads has moved** — `steveyegge/beads` now 301s to
`gastownhall/beads`, same org as Gas Town (17,715), and it was pushed to today.

**Limits, stated so a later reader does not over-trust this.** Nothing here was run. Keyword
search finds what is named and misses what is implemented under a different word — an absence
below means "not found by these searches", not "does not exist". Closed and commercial tools were
not examined at all: **Kiro, Tessl, CodeRabbit, Greptile, Cursor and Linear are unexamined**, and
CodeRabbit in particular sells on review metrics and could hold a counterexample to §4.1. Default
branches only; unreleased work in other branches is invisible.

---

## 2. Corrections to the 2026-08-08 memo

**§1 holds.** Beads still uses Dolt as its sole source of truth — `README.md:136` still says
`.beads/issues.jsonl` is "an export for viewers and interchange, not the source of truth or a
backup", and `bd init` now offers embedded (single-writer) and server (concurrent-writer) modes.
The inverted truth-model versus ours is unchanged, and so is the conclusion: interoperate through
the JSONL export, do not depend on the runtime.

**§3's first half holds.** Beads still has essentially no cost awareness: one hit in its README,
for semantic compaction of closed tasks. No tokens, no budget, no spend.

**§3's headline claim is now wrong.** The memo said no surveyed system combines risk-tiered review
with token economics, and that Cloudflare had proved the economics but only as internal
infrastructure. **Superpowers has since designed exactly that intersection in the open**, in
`docs/superpowers/specs/2026-06-10-strict-cost-sdd-design.md`:

- a measured cost breakdown by component of the run — ~$13/run, controller ~$6-7, implementers
  ~$5-6, task reviewers ~$1-1.5 — with the driver named for each;
- a tiering rule stated as an invariant, **"Cheapen mechanics, never judgment"**, with the
  judgment points enumerated so a rung cannot quietly demote one;
- a hard quality invariant gating every cost reduction: the
  `sdd-quality-reviewer-catches-planted-defect` pass rate over **N=5 runs**, with the remark that
  "single-run gates were this campaign's weakest methodology".

That is our thesis, arrived at independently, by a project with two orders of magnitude more
users. **The intersection is no longer unoccupied.** What keeps it *partly* open is that the
spec is headed "Proposed experiment ladder (not implementation)", and no harness for that eval
exists under `tests/` in the repository — it is a design, not a shipped control.

**§2's warning got sharper.** The memo's "sobering counter-source" said native primitives already
cover ~80% of third-party memory and planning. A year of ecosystem growth has not softened that;
it has produced a `Backlog.md` at 6.5k stars doing the markdown-backlog job in ~20 files.

---

## 3. What the goals are, restated, because the comparison only means something against them

Recorded here because they were given verbally this session and a goal held only in a transcript
is not held:

1. **Predictable, deterministic, nurtured** planning → research → analysis → development →
   tested quality outcomes.
2. **Functional and non-functional** scope, both.
3. **Any project, any industry**; three starting conditions — greenfield, brownfield,
   legacy modernization — as states of one project's life.
4. **Solo developer or a team.**
5. **Token optimization is equally important**, not a nice-to-have.
6. Delivered as a **Claude Code plugin now**, with the goal of working as a plugin **across
   coding agents** later.
7. **Deliberately not built:** an LLM/AI gateway, and an agentic framework. Both are to be
   consumed from what already exists, open-source or proprietary.
8. **The kit's users must be able to build agents** with the agentic framework of their choice —
   LangChain, LangGraph, or anything else.

### 3.1 Point 7 and point 8 are two different agnosticisms, and conflating them is a live risk

> **SUPERSEDED — see `2026-08-22-auto-mode-is-a-graduation.md` §1.1.** LangGraph was an example use
> case, not a scope. The section below builds a design pillar on it and that is an over-read; the
> surviving residue is one finding class (an acceptance criterion that is a distribution rather
> than a boolean), to be handled when non-functional finding classes are defined. Point 7's real
> justification is also narrower and stronger than given here: an add-on that requires a host
> organisation to adopt its runtime is not an add-on. Left in place unedited, because a design
> input rewritten to look always-correct is the failure being avoided.

They read as one sentence and are not. Point 7 is about **what the kit is**: it does not own a
model gateway or an agent runtime. Point 8 is about **what the kit's users build**: agent
applications, on frameworks the kit does not choose.

The second has a consequence the first does not, and it is not currently anywhere in the
design: **an agent application is itself non-deterministic, so "tested quality outcomes" for one
cannot mean what it means for a CRUD service.** A LangGraph app's correctness is a distribution,
not a boolean. Its regressions are prompt regressions, tool-selection regressions and cost
regressions. Goal 1 promises determinism about the *process*; goal 8 admits subjects where the
*product* is not deterministic, and the kit currently has no vocabulary for that difference.

`[judgement]` This is the most interesting thing the comparison surfaced, and it did not come
from a competitor having solved it — none has. It came from noticing that Superpowers' planted-
defect gate is the shape of control an agentic subject needs, and that we would need it *for our
users' projects*, not only for our own reviewers.

---

## 4. Dimension by dimension

### 4.1 Did anyone measure whether the pipeline caught the defect?

Searched all eight for `escape rate`, `escaped defect`, `defect escape`, `escapes to production`,
`leak rate`, case-insensitive, across every file type. **Zero matches.**

The nearest thing anywhere is Superpowers' planted-defect gate (§2), which measures reviewer
recall rather than production escape — arguably the better instrument, since it can be run on
demand instead of waiting for reality. It is designed and not built.

**And the comparison cuts at us too.** Our escape rate currently reads `0 / 0 via:kit` in every
tier, because nothing writes `Via:` without a human confirming it. We have a shipped instrument
with no readings; they have a designed instrument with none. Claiming this dimension outright
would be claiming a scoreboard, not a score.

### 4.2 Token and cost accounting

Two of eight measure it, and my first answer to the operator wrongly said none did.

**Task Master** computes per AI call: `inputTokens`, `outputTokens`, `totalTokens`, `totalCost`
in USD, `currency`, and an `isUnknownCost` flag, attributed to a `commandName`. It converts to
money, which we do not. But `scripts/modules/ai-services-unified.js:937` reads:

```
// TODO (Subtask 77.2): Send telemetryData securely to the external endpoint.
```

The number is displayed to the user and then discarded. No history, no attribution to a unit of
work, no rate projection.

**Superpowers** ships `tests/claude-code/analyze-token-usage.py`, whose docstring is "Analyze
token usage from Claude Code session transcripts. Breaks down usage by main session and
individual subagents" — tracking `input_tokens`, `output_tokens`, `cache_creation`, `cache_read`.
That is the same instrument as `kit-spend.sh`, read from the same source, minus the hook wiring,
the task attribution and the persistence.

**So the defensible claim is narrower than "we measure spend".** It is: nobody persists spend
attributed to a unit of work in a record that survives the session, and nobody reports what went
*unmeasured*. Our "5 subagent run(s) unmeasured" line has no counterpart in any of the eight.
Absent-is-not-zero is the differentiator; spend tracking is not.

### 4.3 Dispositions — a finding that is not a fix

Beads has the only real analogue: `bd human dismiss` closes an issue with a `"Dismissed"` reason,
`bd close --reason-file` exists so agents can write structured close reports, and per its
CHANGELOG (#5332) **`bd human stats` classifies dismissals by close-reason PREFIX**, counting
total / pending / responded / dismissed. Its status vocabulary also carries `invalid` and
`duplicate`.

Three differences: it is scoped to issues labelled `human`; the reason is free text matched by
prefix rather than a vocabulary; and nothing corroborates the mark.

BMAD's current skills-based release has **no waiver vocabulary at all** — zero matches for
`waiv*` under `src/`. The older v4 PASS/CONCERNS/FAIL/WAIVED quality gate is gone from this
release.

**Nothing in any of the eight requires evidence on the subject before accepting a disposition.**
`kit-resolve.sh` refusing `--superseded` unless the finding's own `file_path` carries a matching
`Superseded-by:` line — and refusing it when the file is *absent*, so deleting the evidence is not
the cheap way out — has no counterpart found. That specific property is the differentiator, not
"we have dispositions".

### 4.4 Risk-tiered effort

Not ours alone, and this is the second thing my first answer got wrong.

BMAD's `src/bmm-skills/plan/bmad-architecture/references/reviewer-gate.md` scales the gate to the
stakes and then states a floor:

> Scale *whether and how heavily the gate runs* to the stakes: a throwaway prototype may run it
> quietly or skip the gate entirely; a high-criticality or platform-altitude spine earns more
> lenses … But once the gate runs, the `{workflow.finalize_reviewers}` always run — they are the
> configured floor, never cherry-picked out; only the ad-hoc lenses are optional. (Headless never
> skips the gate.)

It also does what we do not: **dispatches each lens as a parallel subagent that writes its full
review to a file and returns only a compact summary**, explicitly so the parent never holds the
review text — and states that an inline self-check does not count, because the independent context
is the point.

Superpowers states the same principle as an invariant with its judgment points enumerated.

The difference left to us is that our floor is *computed and its violations reported* by
`kit-status.sh`, where theirs is prose the model is asked to honour. That is real but thin,
and our own record shows that section was silent because `templates/project-profile.md` ships zero
uncommented `tier.rule`. **A binding we have never exercised is not obviously stronger than a
prose floor a large user base follows daily.**

### 4.5 Non-functional scope

BMAD is materially ahead here and it is the dimension where we are weakest relative to a stated
goal. Non-functional requirements appear across 63 of its markdown files, structurally rather than
in passing — in the PRD template, the PRD validation checklist, the epics and stories steps, and
the architecture spine template. Its reviewer gate treats a whole silent dimension as a finding,
naming "the operational/environmental envelope (deployment & environments, infra/provider
strategy, operations) a domain-focused draft skips".

We have review classes and tiers, and the solution overlay carries baseline design patterns — but
nothing in the kit makes an absent NFR a finding.

### 4.6 Reuse: accelerators, constitutions, extensions

Two competitors have solved parts of the accelerator problem in ways worth copying.

**Spec Kit has the distribution mechanism we do not.** `extensions/catalog.community.json` is a
versioned registry with a `schema_version`, a `catalog_url`, and per-extension `requires`
(`speckit_version: ">=0.13.0,<0.16.0"`, plus required external tools with version ranges),
`provides` (command and hook counts), `category`, `tags`, `license`, and a `download_url` to a
release asset. There are four guides around it — user, development, publishing, API reference —
and an `RFC-EXTENSION-SYSTEM.md`. Extension and preset commands are applied **at install time**,
written into the agent's own directory (`.claude/commands/`).

That is the answer to a question our accelerator design has open: how a versioned, evolving,
cross-project artifact is published, discovered, version-constrained and installed. We have the
concept and the earning ladder; they have the packaging.

**Spec Kit's `/speckit.constitution` is a solution-overlay analogue** — "project governing
principles and development guidelines that will guide all subsequent development", established
once per project as step 0. Our overlay is richer by design (it carries the route as well as the
destination, the architect's answers, the debt strategy, and the accelerator selection) but the
comparison confirms the *position* of the artifact: first, authoritative, one-time, and above the
work rather than inside it.

**Beads has the cross-agent discovery convention.** `bd init` creates or updates **`AGENTS.md`**
by default, and `bd setup` has integrations for codex, claude, factory (Droid), mux, cursor and
more, with `bd onboard` printing a snippet to paste for anything unsupported.

### 4.7 Host agnosticism — the "any coding agent" goal

This goal is further behind the field than the roadmap assumes. Superpowers carries host-specific
test suites for `antigravity`, `codex`, `devin`, `kimi`, `opencode`, `pi` and `claude-code`, plus
a `gemini-extension.json` and a codex plugin sync. Spec Kit's installer names nine integrations in
source — `amp`, `auggie`, `claude`, `codex`, `copilot`, `gemini`, `kilocode`, `opencode`, `qwen` —
and its README documents that most hosts see `/speckit.*` while Codex CLI sees `$speckit-*`.

Two portability patterns are visible and neither requires an abstraction layer: **`AGENTS.md` as
the host-neutral discovery file**, and **install-time materialisation** of commands into each
host's own directory, so the artifacts are per-host but the source is one.

`[judgement]` Our hooks are the hard part, not our skills or agents. Everything that makes the
kit's record trustworthy — spend rows, checkpoints — is wired to Claude Code hook events, and no
`AGENTS.md` convention carries those. A second host will get the planning and review surfaces
long before it gets the measurement, and the roadmap should say so rather than discover it.

### 4.8 Team versus solo

CCPM is the team-native design: GitHub Issues as the substrate so the backlog is where the team
already is, plus worktrees for parallel agents. OpenSpec targets teams needing auditable change
documentation before implementation. Backlog.md ships a web UI so non-CLI humans can see the
board. Beads' server mode exists specifically for multiple concurrent writers.

We are single-writer-per-repo by design and the 2026-08-08 memo deliberately deferred concurrent
claiming. That deferral is still right for a solo operator `[judgement]`, but "or a developer
team" is a stated goal, and three of eight competitors treat the team case as the default rather
than the extension.

### 4.9 The three starting conditions

Nothing in the eight organises itself around greenfield / brownfield / modernization as states of
one project's life. Spec Kit and BMAD are greenfield-first with brownfield as an adaptation;
BMAD's reviewer gate does ask whether a spine "ratifies rather than contradicts a brownfield
codebase". Nobody has a modernization delta.

**This is the clearest unoccupied ground in the comparison, and it is the one we already decided
to build.** It is worth more than the task store and, on this evidence, more than the review
economics too.

---

## 5. The learnings, ranked by how much they should change what we do

1. **Our differentiator is the record, not the measurement.** Persistence attributed to a unit of
   work, and marks a tool can refuse. That is a claim about plumbing and it is copyable — which
   argues for getting readings into it soon, because an instrument with no readings converts to
   nothing if someone else ships one with readings first.
2. **The intersection we called empty is now designed by a project 10× our reach.** Not shipped.
   The window is real but it is a window, not a moat.
3. **A planted-defect gate is worth more than an escape rate we cannot populate.** It can be run
   on demand; escape rate waits for reality and for a human to confirm `Via:`. It is also the
   control our *users* will need for agentic subjects (§3.1). One mechanism, two payoffs.
4. **Accelerator distribution is a solved problem we can copy** rather than design: a catalogue
   with semver constraints, install-time materialisation, and a publishing guide.
5. **Non-functional coverage is a stated goal with no mechanism.** BMAD makes a silent dimension a
   finding; we cannot.
6. **Host portability is mostly hooks.** The planning surfaces port cheaply; the measurement does
   not, and that ordering should be explicit.
7. **`AGENTS.md` is becoming the cross-agent convention**, adopted independently by Beads and
   assumed by Spec Kit's Codex path. Writing one is cheap and buys discovery.
8. **Agentic subjects need a quality vocabulary we do not have** (§3.1) — distributions, prompt
   regressions, cost regressions, not pass/fail.

---

## 6. Roadmap candidates

> **RE-CUT — see `2026-08-22-auto-mode-is-a-graduation.md` §7.** The ordering below is by
> competitive gap. The organising axis is the terminal goal instead, which raises the readings work
> and the budget cap, makes model-capability structural, adds four items absent here entirely
> (divergence detection, disposition delegation, the practitioner layer, goal-as-delegation-unit),
> and lowers host portability to the deliberate later phase it always was. The individual items
> below remain accurate about *what* each is; that document is authoritative on *when* and *why*.

Each names what it is for and what would falsify it. **None of these is a decision**; they are
input to the operator's sequencing, and every one of them is downstream of the brownfield trial
that is currently unblocked.

### Short term

- **`AGENTS.md` for this repo, generated by `kit-init.sh`.** Cheap, and it is the discovery file
  two of the eight already assume. *Falsified if* it duplicates `.claude/CLAUDE.md` badly enough
  that the two drift — in which case generate it from one source.
- **A planted-defect eval for our own reviewer agents, run N≥5.** The single highest-value item
  in this document `[judgement]`. It converts "sub-agents raise real criticals" from an
  observation into a control that can fail, and it is the prototype for §3.1.
  *Falsified if* the harness cost per run exceeds what the finding is worth — measure it on one
  agent before building it for all.
- **Populate `templates/project-profile.md` with real `tier.rule` floors**, so the below-floor
  section has something to say. §4.4's advantage is unexercised until this lands.
- **Make one NFR dimension a finding class** — the operational envelope is BMAD's choice and a
  reasonable first — rather than adding a full NFR taxonomy.

### Mid term

- **Get readings into the record.** Whatever makes `via:kit` populated for real work, so escape
  rate stops being `0/0`. Learning 1 is worthless until this exists.
- **Accelerator catalogue with semver `requires`, modelled on Spec Kit's**, including the
  publishing guide. Do not invent the format; adapt theirs.
- **Parallel review lenses that return only a summary**, per BMAD's reviewer gate — full review to
  a file, compact summary to the parent. This is a token-optimization win (goal 5) with a quality
  argument attached (independent context), and it fits the existing review chain.
- **Decide the team story explicitly** — adopt CCPM's "the backlog lives where the team already
  is" via an ingest adapter, or state that solo is the scope and team is later. Three of eight
  make it the default; leaving it implicit is the risk.

### Long term

- **A quality vocabulary for non-deterministic subjects** (§3.1): eval-based acceptance, prompt
  and tool-selection regression, cost regression as a first-class finding class. This is what
  makes goal 8 real rather than "we do not stop you".
- **Host portability, staged and honest**: planning and review surfaces first via install-time
  materialisation, measurement second and only where a host exposes hook-equivalent events. Say
  which hosts get which tier of support.
- **Modernization delta** — still parked by operator decision, and still the ground nobody else
  occupies (§4.9).

---

## 7. What this document does not claim

- It does not claim the eight are all the competition. Kiro, Tessl, CodeRabbit, Greptile and
  Cursor were not examined; a commercial review tool may hold a counterexample to §4.1.
- It does not claim any absence is proof. Keyword search over one branch is evidence of what is
  named, not of what exists.
- It does not re-derive `docs/COMPETITIVE-LANDSCAPE.md`. Where the two disagree, this document is
  newer on §3 and that memo is more thorough on Anthropic's native encroachment and on the
  token-economics literature.
- It does not recommend depending on any of the eight. The one integration argument that survives
  is the 2026-08-08 conclusion unchanged: interoperate through exports, never absorb a runtime.
- **It closes nothing and files nothing.** The comparison is input to sequencing, and the
  sequencing decision — trial first or overlay first — is the operator's and remains open.
