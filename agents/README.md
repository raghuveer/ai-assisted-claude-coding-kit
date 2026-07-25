# Subagents — routing, risk-tiering, and the core/overlay split

Eight agents. The harness auto-routes to them by matching your request against each agent's
`description`, so the `description` line is a routing decision, not documentation.

## The pipeline

```
                         ┌─ NON-TRIVIAL design only ─┐
  researcher(opus) → approach-reviewer(opus) → [operator walkthrough] → adr-scribe(sonnet) ┐
                                                                                           ↓
  ROUTINE change ──────────────────────────────────────────────────────────→  coder(sonnet)
                                                                                           ↓
                                      implementation-reviewer(sonnet)  +  security-reviewer(opus, HIGH-STAKES only)
                                                                                           ↓
                                                                                  tester(sonnet)
                                                                                           ↓
                                                                                documenter(haiku)
```

## Model tiering — keeps expensive fan-out proportional to risk

| Agent | Model | Runs when |
|-------|-------|-----------|
| researcher | opus | non-trivial design only |
| approach-reviewer | opus | non-trivial design only |
| security-reviewer | opus | **high-stakes changes only** |
| adr-scribe | sonnet | after APPROVED + the operator walkthrough |
| coder | sonnet | every implementation |
| implementation-reviewer | sonnet | every change (escalate to opus for high-stakes) |
| tester | sonnet | after review approves |
| documenter | haiku | after tests / a feature-state change |

**Risk tiering is defined in your `project-profile.md`** — see `templates/project-profile.TEMPLATE.md`.
Name the tier and cite the trigger *before* spawning agents, or routine work quietly defaults to the full
pipeline and the expensive tier becomes your largest cost line.

**Do not skip phases** on non-trivial or high-stakes work — the review→code→review→test chain is the
correctness story. **Do** go straight to `coder` for a one-line routine fix; running the full gauntlet on
a CRUD tweak is wasted quota.

## Model selection — what it can and cannot do

There is **no** dynamic router that classifies each request and picks the cheapest capable model per call.
Selection happens at two fixed points: the **session model**, and the **`model:` line in each agent's
frontmatter** (static per agent).

What this kit gives you is *effective* task-based routing without a router: the harness routes your prompt
to whichever agent's `description` matches, and that agent carries a fixed tier. The chain is
**task → agent (by description) → model (by frontmatter)**. Routine work matches the cheaper agents; hard
design and security work matches the expensive ones.

**Practical default:** set the session to the mid tier, let the agents pull the expensive tier only where
their frontmatter says so, and reach for a manual override only for a hard stretch in the main loop.

## Structure — core + overlay

The agents are **composed**, not edited in place:

```
agents/core/<agent>.md                portable method; owns the frontmatter
agents/overlay/<project>/_shared.md   project context appended to EVERY agent
agents/overlay/<project>/<agent>.md   per-agent project vocabulary (optional; may override frontmatter)
        ↓  pwsh sync-agents.ps1 -Project <name>
.claude/agents/<agent>.md             generated — never edit this copy
```

⚠️ **Edit `core/` or `overlay/`, never `.claude/agents/`** — the sync overwrites it. And see
`agents/overlay/README.md` for the destination guard: the overlay selector picks the overlay, **not** the
destination, so one kit checkout serves one project.

## What transfers, and what has to be earned

**Transfers unchanged:** the three-pass reviews, the HALT verdict and its asymmetry, the fail-closed bias,
the output contracts, the universal defect classes (a/b/c/f/h) and test traps (d/e/g), the mutation
discipline, and the diminishing-returns cap on design review.

**Does not transfer — and this is the point:** the *citations*. `core/` ships the class ("a guard written
in the positive direction passes on every absent value"); your overlay adds "shipped four times, here, as
&lt;your decision id&gt;". A new project starts with the classes and accumulates its own evidence
underneath them. **That ledger is the part no kit can ship** — it is the compound interest of running the
process, and it is why the overlay grows while core stays still.
