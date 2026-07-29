# Writing a project overlay

> ## ⚠️ Historical — superseded in 0.2.0. Do not follow these instructions.
>
> The overlay/composition model described below is retired. `agents/core/` and
> `agents/overlay/` no longer exist, `sync-agents.ps1` is kept unwired as
> `legacy-sync-agents.ps1`, and nothing generates `.claude/agents/` any more.
>
> **What to do instead:** agents are flat files in `agents/` and read
> `.claude/project-profile.md` when they spawn. Project-specific evidence lives in the
> `finding` table, recorded by `kit-finding.sh` and promoted by `kit-accel.sh`, not in
> per-agent prose. See `docs/agents-README.md` and `docs/MIGRATION.md`.
>
> Kept only for the reasoning in the destination-guard section, which is why one kit
> checkout served exactly one project.

An overlay is what makes the portable agents in `../core/` true for *your* project. Composition is
`core/<agent>.md` + `overlay/<project>/_shared.md` + `overlay/<project>/<agent>.md` → `.claude/agents/`.

Run: `pwsh docs/ai-workflow/sync-agents.ps1 -Project <name>` (the `-Project` flag is optional when exactly
one overlay directory exists).

## 🔴 One kit checkout per project — and a guard that enforces it

**The overlay selector picks the overlay; it does NOT pick the destination.** The script always writes to
the container root of the checkout it lives in:

```
<container>/docs/ai-workflow/sync-agents.ps1   →   <container>/.claude/agents/
```

So `-Project b` run inside project A's checkout would compose B's agents over A's live set — silently,
with no diff to notice, leaving A's reviewers speaking B's vocabulary and asserting B's decision IDs as
rules. One wrong flag, no error.

`.claude/.kit-project` records which project a destination belongs to. A mismatch **refuses and changes
nothing** (exit `3`); re-pointing a checkout deliberately needs `-Force`. The marker is written only after
a successful compose, so a failed run never claims ownership it did not deliver. Deleting it is safe — the
next sync re-adopts the checkout.

Two overlays can live side by side in one kit for convenience, but they cannot share one destination.

## The one file you must write: `_shared.md`

Appended to every agent. No frontmatter — start with a heading. Cover:

| Tell the agents | Because without it they will |
|---|---|
| Stack, layering, test runner | invent conventions from their defaults |
| **Fail-mode discipline** — what fails closed, what fails open, and the status codes | guess, and guess permissively |
| Shared packages that are *mandatory* on certain calls | write a call that skips auth or resilience |
| Where decisions live, and where live status lives | duplicate state into prose and drift |
| What is **operator-owned / never touch** | edit something they must not |
| Local runtime gotchas (container CLI, stale-image traps) | believe a live check that tested the wrong artifact |

## Per-agent overlays: add them as you learn, not up front

Start with none. Add a file when a review finds something the core method didn't cover *in your codebase*.
Each per-agent overlay may open with a frontmatter block whose keys **override** core's — use it to retune
`description` (the trigger text the harness shows, which should name your real high-stakes surfaces) or
`model` (a cost decision the project owns).

**What belongs in an overlay:**
- Concrete names: services, packages, decision-record IDs, config helpers.
- Your **ledger of shipped defects** — the class lives in core, the citation lives here. `core` says "a
  positive-direction guard passes on every absent value"; the overlay says "shipped four times here, as <your decision id>".
- Local rules with teeth: "this route prefix is exempt from the token gate", "migrations are checksum-
  tracked so an applied file cannot be edited".
- Baselines a reviewer should notice moving (test counts, latency budgets).

**What does not belong:**
- Anything true of software generally — that is a `core/` improvement, and every project should get it.
- Aspirations. An overlay states what *is*, or it becomes the next stale doc.

## The rule that makes this worth doing

**`core/` holds the method; the overlay holds the evidence.** A new project inherits four consecutive
demonstrations that adversarial review beats a green suite — but it inherits them as *classes to check*,
not as facts about code it does not have. It then earns its own citations. Keeping those separate is what
lets `core/` improve for everyone while each project's hard-won specifics stay where they are true.

## Checklist for a new project

- [ ] `overlay/<name>/_shared.md` written (the table above)
- [ ] `project-profile.md` rewritten — risk tiers, test commands, session hygiene
- [ ] `STATUS.md` reset; `CLAUDE.md` project-context block replaced
- [ ] **separate kit checkout** for this project (the destination guard will refuse a shared one)
- [ ] `sync-agents.ps1 -Project <name>` run; `.claude/agents/` inspected once by hand
- [ ] a status-marking convention chosen (this kit derives item status from commit trailers)
- [ ] **no per-agent overlays yet** — resist writing them before the project has taught you something
