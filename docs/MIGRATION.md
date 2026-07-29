# Migration: copy-based kit -> plugin

## Commands -> skills, and what became a hook

`commands/` still works in plugins, but `skills/` is the current format and has a
materially better cost profile: a skill's metadata (~100 tokens) is resident, its body
loads only when invoked. A command's body behaves the same way, but commands are
user-invoked only — Claude cannot reach for one when it is relevant.

| Was | Is now | Why |
|---|---|---|
| `/resume-context` | skill `task-context` | Claude should reach for it at the start of work, not only when you type it. |
| `/checkpoint` (68 lines) | skill `checkpoint` + `Stop` hook + `kit-index.sh` | Steps 3, 4 and 7 were mechanical. A checkpoint that depends on someone remembering to type it is skipped exactly when sessions run long — which is precisely when it matters. |
| `/drift-check` (31 lines) | mostly **retired** | Its own text said a mechanical check against git is cheaper and should run automatically. With derived state, item-level drift is structurally impossible: `STATUS.generated.md` is regenerated from task files and trailers, so it cannot disagree with git. What survives is narrative claims, which `status-report` covers. |

The originals are kept in `legacy-commands/` for reference. They are not wired up.

**Recommendation: skills only, no command aliases.** Skills are invocable by name, so an
alias buys back muscle memory at the cost of a second resident description per ritual.
With five skills you are paying ~500 tokens in every project on the machine; aliases would
add to that for no capability.

## sync-agents.ps1 -> runtime reference

Kept as `legacy-sync-agents.ps1`. Plugins layer natively: plugin agents and a project's own
`.claude/agents/` coexist, so core no longer needs to be text-composed with an overlay
before use. Core agents read `.claude/project-profile.md` at spawn instead.

The cost is a per-session read rather than a build step; that read lands in the stable
cached prefix at 0.1x, so it is close to free. What it buys: no PowerShell dependency (the
last stack assumption in the kit), and no "read one composed agent end to end by hand"
verification burden — which never scaled to other people's projects anyway.

## project-profile

`templates/project-profile.LEGACY.md` is your original. `templates/project-profile.md` is
the new one: same risk-tiering role, plus flat frontmatter that the scripts parse with awk.
Merge your prose across; the frontmatter keys are new.

## Order

1. Publish as a plugin. Do this first — versioning is what makes feedback from other
   developers interpretable, and it changes the shape of everything after it.
2. Adopt derived state in one project. `kit-init.sh`, then delete `STATUS.md` and any task
   CSV. Not deprecate — delete. A surviving copy will be edited.
3. Turn on instrumentation (findings, vindication). Nothing visible ships, which is why it
   gets skipped; it is also the phase everything later depends on.
4. Hand the pinned version to other developers.

Run `ccmetrics.py --split <a date before you changed anything>` **before** step 1. That
control cannot be reconstructed later.
