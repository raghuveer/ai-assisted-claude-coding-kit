# Starting a new project with this kit — the copy checklist

The authoritative answer to "what do I copy, and what do I write." The kit splits into a **portable core**
(never edited per project) and a **thin project layer** (written once, then grown).

> ⚠️ **This file used to say the per-project delta was "a light grep-and-swap in the agents — swap the
> test-framework name and you're done."** That was wrong, and splitting the agents is what proved it: the
> project-specific content turned out to be decision-record IDs, package names, service topology and named
> exploit precedents — none of which a framework-name grep finds, and all of which would have been
> silently **false** on a new project. The core/overlay split exists so that class of content has somewhere
> honest to live.

---

## Step 1 — Copy verbatim (never edited per project)

```
agents/core/              the 8 agents' portable method
agents/README.md          pipeline + tiering + the core/overlay model
agents/overlay/README.md  how to write an overlay; the destination guard
sync-agents.ps1           the composer
```

**One kit checkout per project.** The overlay selector picks the overlay, not the destination — the sync
writes to the container root of the checkout it lives in, and refuses a destination already claimed by
another project (`.claude/.kit-project`, exit 3).

## Step 2 — Do NOT copy (project state — start fresh)

- The live status pointer and its archive — create an empty one.
- Any other project's `agents/overlay/<name>/` — that is their vocabulary and their scar tissue, and it
  would be false in your codebase.
- Cost/experiment records.
- Auto-memory is per-project already; nothing to copy.

## Step 3 — Write the thin project layer (the only real work)

1. **`project-profile.md`** — from `templates/project-profile.TEMPLATE.md`. The agents read this for
   everything project-specific. The **risk-tiering table is the highest-leverage thing in the kit**:
   without it, routine work defaults up to the full pipeline and the expensive model tier becomes your
   largest cost line.
2. **`agents/overlay/<yourproject>/_shared.md`** — the only overlay file you must write. Stack and
   layering · fail-mode discipline (what fails closed, what fails open, and the status codes) · packages
   that are mandatory on certain calls · where decisions and live status live · what is operator-owned and
   must never be edited · local runtime traps.
3. **Your agent-instructions file** (`CLAUDE.md` or equivalent) — project context, environment, working
   agreements.
4. **The rituals** — adapt `templates/commands/` and `templates/settings.json`. They are real working
   files from another project and **name its repos, paths and scripts**; see the table in the kit README
   for what must be replaced.
5. **Per-agent overlays — write none yet.** Add one when a review finds something the core method did not
   cover *in your codebase*. Inventing scar tissue you have not earned is how a kit accumulates
   confident-sounding fiction.

## Step 4 — First session

- `pwsh sync-agents.ps1 -Project <yourproject>`, then **read one composed agent end to end by hand**. It is
  the only way to catch an overlay that contradicts core.
- Confirm the agents loaded in your harness.
- Set the session to the mid model tier; the agents pull the expensive tier only where their frontmatter
  says so.
- Decide how item status is recorded **before** you accumulate items. Deriving it from commit trailers
  costs nothing per commit; maintaining it by hand costs a stale tracker, and the staleness is invisible
  until someone audits.

---

## The delta, summarized

| Copy verbatim | Write per project |
|---|---|
| `agents/core/*` (8) | `project-profile.md` (from the template) |
| `agents/README.md`, `agents/overlay/README.md` | `agents/overlay/<name>/_shared.md` |
| `sync-agents.ps1` | your agent-instructions file |
| — | `templates/commands/*` + `settings.json`, adapted |
| — | a fresh status pointer |

The method, the rituals, the pipeline and the tiering travel unchanged. **The citations do not** — those
you earn, and they are what makes the reviewers sharp on your codebase rather than someone else's.
