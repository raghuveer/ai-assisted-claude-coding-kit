# AI-assisted Claude coding kit

> **An independent personal project. Not affiliated with, endorsed by, or supported by Anthropic.**
> "Claude" and "Claude Code" are Anthropic's; they appear here only to describe the tool this kit is
> built for. Nothing here is an official practice or recommendation, and none of it carries any
> warranty — see LICENSE.

A file-based workflow for running substantial software work with Claude Code: eight risk-tiered
subagents, three session rituals, and the discipline that decides how much process a change gets.

**Extracted from real work, not designed in the abstract.** Everything in `agents/core/` earned its place
by catching something — a fail-open guard, a race behind a green test suite, a comment whose rationale
was false. What is deliberately *absent* is any single project's operational history. The method is here;
the war stories belong in whichever project produced them, where they are actually true.

⚠️ **Claude Code-shaped.** The *method* is portable, but the *packaging* is not: `.claude/agents/` with
`model:` frontmatter, slash commands, and `settings.json` hooks are Claude Code mechanics. Adapting to
another harness means keeping the agent prompts and rebuilding the plumbing.

## What is here

```
agents/core/             8 portable agents. Verified free of project-specific identifiers.
agents/README.md         pipeline, model tiering, the core/overlay model
agents/overlay/README.md how to write a project overlay; the destination guard
sync-agents.ps1          composes core + overlay -> .claude/agents/
NEW-PROJECT-SETUP.md     the copy checklist
templates/               starting points you fill in — profile, commands, settings
```

## Getting started

1. Copy this kit into your project, or clone it beside one. **One kit checkout per project** — the sync
   refuses a destination already claimed by another project.
2. Fill in `project-profile.md` from `templates/project-profile.TEMPLATE.md`. **Start here.** Its
   risk-tiering table is what keeps the expensive model tier proportional to risk, and it is the single
   highest-leverage file in the kit.
3. Write `agents/overlay/<yourproject>/_shared.md` — stack and layering, fail-mode discipline (what fails
   closed, what fails open), where decisions and live status live, what is operator-owned. This is the
   only overlay file you must write.
4. `pwsh sync-agents.ps1 -Project <yourproject> [-Destination <project-root>]`, then **read one composed
   agent end to end by hand**. It is the only way to catch an overlay that contradicts core.
5. Copy `templates/commands/` to `.claude/commands/` and `templates/settings.json` to `.claude/`, then
   adapt both to your repository layout and tooling.
6. **Write no per-agent overlays yet.** Add one when a review finds something the core method did not
   cover *in your codebase*. Inventing scar tissue you have not earned is how a kit fills with
   confident-sounding fiction.

`NEW-PROJECT-SETUP.md` has the longer checklist.

## The pipeline, in one line

Non-trivial work: `researcher → approach-reviewer → [your walkthrough] → adr-scribe → coder →
implementation-reviewer (+ security-reviewer if high-stakes) → tester → documenter`. Routine work skips
straight to `coder`. **Which path a change takes is a decision you make out loud, before spawning
anything** — otherwise everything defaults to the expensive path and the model tier becomes your largest
cost line.

## The three ideas worth taking even if you use none of the files

**One kind of truth, one file.** Decisions in decision records, code in git, live direction in one status
pointer, item status *derived* from commits rather than maintained beside them. Every duplicated fact
becomes a stale fact; the only question is when someone notices. The most reliable way to keep status
current is to make recording it a side effect of the commit you were already making.

**Verify at the level the failure lives.** Tests prove the code matches your mental model, so they cannot
tell you the model was wrong — that needs an adversarial reader. The ladder that works: tests →
**mutation-test the wiring, not just the parser** → drive it live → adversarial review on anything
security-relevant. **A surviving mutant is a finding**, and "I inspected it" is not evidence.

**Session length is the cost lever, and almost nothing else is.** A long window re-reads its growing
context every turn. Ending a unit and clearing is quality-neutral — same agents, same review depth — and
routinely worth more than every other optimisation combined. Subagents do not save tokens; they buy
independent judgment, which is a different thing worth paying for.

## Licence

MIT. Use it, fork it, take the ideas and leave the files.
