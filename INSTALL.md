# Installation & configuration

Two audiences: someone starting a project with this kit, and someone joining a project
that already uses it. The steps differ, and doing the wrong one is the usual mistake.

Prerequisites: `git` **2.32 or newer**, `sqlite3` (**3.25+** for cluster context packs),
`bash`, and the POSIX text utilities (`awk`, `sed`, `grep`, `sort`, `cut`, `tr`, `wc`).
No language runtime — no Node, no Python, no PowerShell. That is deliberate, so a Go or
Rust team can adopt this without installing something they do not otherwise want.

The git floor is not incidental: below 2.32 the `%(trailers:…,valueonly)` format expands
to nothing, so every commit indexes as untagged and derived status silently reports an
empty backlog. `kit-index.sh` warns when it sees an older git. `validate.py` below is the
one exception to "no runtime" — it is an authoring check, never run by the kit itself.

---

## A. Install the plugin (everyone, once per machine)

### Trying it out — no marketplace, no install

    claude --plugin-dir /path/to/ai-assisted-claude-coding-kit

Loads agents, skills and hooks for that session. Edit a file, run `/reload-plugins`,
changes apply without restarting. Best loop for developing the kit itself.

### Installing properly

    /plugin marketplace add raghuveer/ai-assisted-claude-coding-kit
    /plugin install coding-kit@ai-assisted-claude-coding-kit

Pin a version when handing it to others:

    /plugin marketplace add raghuveer/ai-assisted-claude-coding-kit@v0.2.0

Pinning is not fussiness. Without it you cannot tell which version someone's feedback
is about, and the comparison you are running becomes uninterpretable.

Verify:

    /agents                    # the 8 should be listed
    /plugin                    # coding-kit enabled

The plugin is now available in *every* project on this machine. It stays inert in all
of them until a project opts in — see below.

---

## B. Starting a NEW project

    cd your-repo
    $CLAUDE_PLUGIN_ROOT/tooling/kit-init.sh

Creates `.claude/project-profile.md`, generates `.git/hooks/commit-msg`, and writes
`.gitignore` / `.gitattributes` entries.

Then, in order:

**1. Fill in `.claude/project-profile.md`.** This is the highest-leverage file in the
kit — it is what makes core agents work on your stack without naming your tools.

    commands.build / test / lint / typecheck    how to run things here
    ladder.rung3 / rung5                        leave EMPTY if the stack has no tooling
    tier.rule                                   path globs -> minimum review tier
    accelerator.technology / .industry          which apply, and which agents get them
    priority.w_unblocks / w_escapes / w_tier    scoring weights for kit-plan

On empty ladder rungs: an unavailable rung is *declared* and **raises the tier**. Less
mechanical verification means more adversarial reading, not a lower bar. Silence here
means a T3 pipeline quietly reviewing at T2 depth with nobody aware.

Below the frontmatter, write prose about the codebase: stack and layering, what fails
closed versus open, where decisions live, what is operator-owned. Durability test —
would this line still be true in six months regardless of what is in flight? If not, it
belongs in a task file.

**2. Append `templates/CLAUDE.kit.md` to your `CLAUDE.md`.** ~15 lines: the tiering
obligation, the write boundary, where truth lives.

**3. Commit the shared parts.**

    git add .claude/project-profile.md .project/tasks .gitignore .gitattributes
    git commit -m "chore: adopt coding-kit"

**4. Delete any hand-maintained `STATUS.md` and task CSV.** Delete, not deprecate. A
surviving copy will be edited by someone, and then you have two truths again.

**5. Create work and go.**

    kit-task.sh --title "Bound retry budget" --tier T2 --lang go
    kit-index.sh && kit-plan.sh --next 5

---

## C. JOINING an existing project

    git clone <repo> && cd <repo>
    $CLAUDE_PLUGIN_ROOT/tooling/kit-init.sh     # says "joined an already-adopted repo"
    $CLAUDE_PLUGIN_ROOT/tooling/kit-index.sh

That is the whole thing. Your profile, the backlog and the event log arrived with the
clone; the index is rebuilt locally and never shared.

**Why running `kit-init.sh` is not optional.** Git does not share hooks. `.git/hooks/`
is per-clone, so trailer validation does not exist for you until you generate it. The
hook is generated rather than symlinked because the plugin's path differs per machine.

If the plugin later moves or you reinstall it, re-run `kit-init.sh`. The hook fails
loudly if it cannot find its library — a validation hook that silently passes is worse
than no hook, because the repo looks protected when it is not.

---

## What is shared, and what is not

| Path | Git | Why |
|---|---|---|
| `.claude/project-profile.md` | **commit** | the team needs the same tiering rules and pins |
| `.project/tasks/*.md` | **commit** | the backlog is shared |
| `.project/events.ndjson` | **commit** | shared history; `merge=union` handles concurrent appends |
| `.gitattributes` | **commit** | carries that merge rule |
| `.project/index.db` | ignored | derived; binary merges are unresolvable |
| `STATUS.generated.md` | ignored | generated; committing it means churn on every rebuild |
| `.git/hooks/commit-msg` | cannot be | git never shares hooks — hence `kit-init.sh` |

Ownership is derived, not assigned: the commit author of a task's latest `started`
event becomes its owner, so `STATUS.generated.md` shows `@name` with nothing to sync.

---

## Verifying the plugin itself

    python3 validate.py                        # structure (bundled, no deps)
    claude plugin validate .                   # official schema check

The bundled one catches what silently produces a plugin that loads but does nothing:
components in the wrong directory, stray `.md` files in `agents/` being loaded *as*
agents, hook commands missing `${CLAUDE_PLUGIN_ROOT}`, absolute paths from the author's
machine. Run both before publishing.
