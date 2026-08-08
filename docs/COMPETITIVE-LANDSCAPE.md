# Competitive landscape — external, cited

> **Status: observed, not assumed.** Every factual claim below was verified by a
> multi-source research pass (25 claims, 3-0/2-1 adversarial votes, 0 refuted) on
> 2026-08-08. Facts carry a source; the two *judgements* this memo makes — where the kit's
> defensible ground is, and build-on vs build-own — are marked `[judgement]` and are the
> only parts a future project is free to overturn. Time-sensitivity is high: the closest
> competitor changed its architecture materially in early 2026 (§1), so re-verify before
> acting on §5.

Read `HANDOFF.md` for why the kit is built the way it is, and `DESIGN-NOTES.md` for what is
proposed on top of it. This memo only covers what *else* exists, and what that means for
where this kit should and should not spend effort.

The frame is fixed and non-negotiable for this scope: **this is a coding _support kit_ that
rides on Claude Code, not an agent framework.** Systems that own the agent runtime
(claude-flow and the like) are a different category and are out of scope as competitors —
they are noted only where they mark the boundary.

---

## 0. The one-line finding

The kit's task/state/dependency machinery is being commoditised from two directions at
once — by Anthropic natively, and by Beads in the open — but the intersection the kit
actually occupies (**risk-tiered review × token/spend economics × dependency planning**) is
held by no shipped tool. That intersection is the product; the task store is not.

---

## 1. The closest system inverted its architecture

Beads (`bd`, Steve Yegge, Go, MIT) remains the nearest thing to this kit's vision, and that
makes its early-2026 change the most important external fact for us.

- Beads now uses an **embedded Dolt** database (a git-like versioned SQL store with
  cell-level merge and native branching) as its **sole source of truth**. `.beads/issues.jsonl`
  is explicitly demoted to a *non-authoritative export* — "not the source of truth or a
  backup." Source: github.com/steveyegge/beads, its CHANGELOG, steveyegge.github.io/beads.
- This is the **exact inverse of this kit's model**, where task files and git trailers are
  truth and `index.db` is a derived cache that can be deleted and rebuilt without loss.
- Beads is heavier for it: adopting it imports a Dolt runtime. For a support kit whose pitch
  is simplicity, that is a cost, not a feature.
- Yet Beads independently confirms our simplicity-first stance: its CHANGELOG records
  *rolling back* merged PostgreSQL and MySQL adapters before any tagged release, citing
  "dialect, credential, schema-lifecycle, migration, CI, and operational complexity at odds
  with our goal of keeping Beads as simple as possible." Even the reference tool treats
  backend proliferation as a liability.

What Beads does that this kit does not, and which is genuinely hard to replicate on plain
text/git: **merge-safe concurrent multi-agent claiming** — hash-based IDs (`bd-a1b2`) that
cannot collide across branches, Dolt cell-level merge for concurrent field edits, and an
atomic compare-and-set `ClaimNext` with idempotent re-claims and replica-aware leases. This
is the capability that would justify depending on Beads *if* true parallel multi-agent
writes ever become a hard requirement. For a solo dev with single-writer-per-repo, it is not
one today.

Beads also already solves agent-agnosticism (JSON output, `bd prime` context injection,
`bd setup` for Claude Code / Codex / Copilot / Cursor / Amp / Droid). Our "any coding agent"
goal is a *separate future project* — but note that if that future ever arrives, interop
with Beads is likely cheaper than re-solving it.

Caveats to re-check before acting: a "Beads Classic" and a `beads_rust` (SQLite+JSONL) port
still exist; one cited primary URL 404'd during verification though its content was
confirmed on the GitHub README. Verify Beads' current backend before building any interop.

---

## 2. What Anthropic commoditised — and what it left open

- **Commoditised (do not build these):**
  - *Just-in-time context retrieval as a pattern* — the Memory tool. Source:
    platform.claude.com memory-tool docs.
  - *Subagents as the token-optimisation primitive* — now Anthropic's official guidance:
    "the context window is the most important resource to manage," and subagents "run in
    separate context windows and report back summaries." This validates the kit's core
    design rather than threatening it. Source: code.claude.com/best-practices.
  - *Session-level task dependencies* — native Claude Code Tasks (`~/.claude/tasks/<id>/`,
    `CLAUDE_CODE_TASK_LIST_ID`, A-blocks-B). File-based, session-scoped, **not repo-aware** —
    so it does not deliver the collaborative, in-repo state that is this kit's premise.

- **Left open (our territory):** the **persistence layer**. The Memory tool is explicitly
  *client-side* — "you control where and how the data is stored." Storage architecture, task
  modelling, and the dependency graph are left to third parties.

- **The sobering counter-source** (blog, not primary): a practitioner argues native
  primitives (CLAUDE.md, auto-memory, plan mode, hooks, skills) already cover ~80% of what
  third-party memory/planning tools promise. Treat as a warning, not a fact: **"state +
  tasks" alone is not a defensible product anymore.** The differentiator has to be the layer
  above them.

---

## 3. The unoccupied intersection `[judgement]`

No surveyed system combines **risk-tiered review + token/spend economics + dependency
planning**:

- Beads has the planning and **zero** cost awareness ("no mention of tokens, costs, budgets,
  or spend"; its only context mechanism is semantic compaction of closed tasks).
- Cloudflare *proved* risk-tiered review economics in production — Trivial (≤10 lines, 2
  agents, ~$0.20) / Lite (~$0.67) / Full (7+ agents, ~$1.68), scaling agent count and model
  tier to change risk: "you don't need seven concurrent AI agents burning Opus-tier tokens
  to review a one-line typo fix." But it exists only as Cloudflare-internal infrastructure,
  **not a reusable plugin.** Source: blog.cloudflare.com/ai-code-review.

The economic premise is sound and independently evidenced: agentic tasks consume ~1000× the
tokens of chat, cost is driven by **input** re-ingestion, and **higher spend does not buy
accuracy** (it peaks at intermediate cost, then saturates or degrades). The kit's tier-floor
+ escape-rate design targets the right lever. Source: arXiv 2604.22750 (Stanford Digital
Economy Lab; multipliers and variance corroborated, absolute dollar figures not
independently re-extracted).

**This is the product.** The task store is undifferentiated; the review-and-cost economics
layered on top of it is not.

---

## 4. The top risk to the current design `[judgement]`

The **forecast-vs-actual** feature hits a model-capability ceiling. The same Stanford study
found agents **cannot self-predict token cost** (correlation ≤0.39), systematically
underestimate, and the same task varies **up to 30×** in total tokens.

Correction to make: **position forecasting as coarse budget _alerting_ and retrospective
tier-floor / escape-rate — not precise estimation.** The paper studies *agent
self-prediction* only; a **statistical/historical forecaster** keyed on past
actuals-by-task-type is out of its scope and may beat the ceiling. That is an untested edge
worth a spike, not a settled loss.

---

## 5. Direction and positioning `[judgement]`

For a solo dev who values simplicity and low token cost over feature breadth:

1. **Keep the kit's own lightweight plan** — task files + git trailers as truth, SQLite as
   derived cache. Do **not** take Beads as a hard dependency: its Dolt runtime and inverted
   truth-model both fight the kit's simplicity and its architecture. The kit's model is
   *more* aligned with support-kit simplicity than Beads' current design.
2. **Interoperate, don't absorb.** If Beads interop is ever wanted, do it through a thin
   adapter over its JSONL export (per the `docs/ADAPTERS.md` producer-swap contract) — this
   keeps the kit a kit, not a framework.
3. **Spend effort on §3's intersection.** Risk-tiered review × token economics × the
   existing plan is the empty niche. Everything else is table stakes or native.
4. **Demote forecast to alerting** (§4); spike a historical forecaster separately.
5. **Defer merge-safe concurrent claiming** (§1) until a real multi-writer requirement
   appears; single-writer-per-repo is fine for the current scope.

### Top risks, ranked
1. **Per-subagent token telemetry is exposed but not trustworthy as cost** — and the whole
   economics layer depends on it. **Spike resolved 2026-08-08**
   (`T-20260808-verify-the-plugin-surface-exposes-trustw`): per-agent transcripts DO exist
   (`subagents/.../agent-<id>.jsonl`), but the available surfaces disagree by **5–215×** on
   the same 105-subagent run. The harness `subagent_tokens` (2,463,029) turns out to be each
   subagent's **final context size** summed — matching the summed last-context to 0.012% —
   not the actual output work (169,383). It is blind to work done, which is why two identical
   agents reported ~43k despite 20× different output. **Verdict:** real cost is computable
   only from the per-agent transcripts, billing-weighted per field — never from
   `subagent_tokens` and never from a raw field-sum (kit-spend's current method overcounts
   ~7×). Fallback: session-level cost + coarse budget alerting, with `subagent_tokens` used
   only as a context-pressure signal. This does not undermine §3 — but it means the economics
   layer must own its own cost computation from transcripts, not trust a harness figure.
   **Acted on 2026-08-08:** `kit-spend.sh` now reads each agent's own transcript, stores the
   four counters raw with `scope`, `model` and final context size, and `kit-status.sh` prices
   them (input ×1, cache-write ×1.25, cache-read ×0.1, output ×5). The reader was checked
   against an independent JSON implementation over the same 105 agents — 0 mismatches — and
   its context column reproduces the harness aggregate to 0.012%, which is what makes "we are
   reading the records the harness reads, and pricing them differently on purpose" a checkable
   claim rather than an assertion. The risk is now **owned, not eliminated**: nothing here
   converts tokens to money, so a project mixing model tiers gets a mix printed rather than a
   dollar figure.
2. **Native encroachment** (§2): "state + tasks" is increasingly built-in. Mitigation: lead
   with the economics layer, not the store.
3. **Forecast over-promising** (§4): mitigated by re-framing to alerting.

---

## Sources
- github.com/steveyegge/beads · steveyegge.github.io/beads · beads CHANGELOG.md (primary)
- platform.claude.com/docs/en/agents-and-tools/tool-use/memory-tool (primary)
- code.claude.com/docs/en/best-practices · code.claude.com/docs/en/costs (primary)
- blog.cloudflare.com/ai-code-review (primary)
- arxiv.org/pdf/2604.22750 — Stanford Digital Economy Lab, agent token economics (primary)
- paddo.dev/blog/from-beads-to-tasks · lord.technology (2026-04-11) (blog, framing only)
