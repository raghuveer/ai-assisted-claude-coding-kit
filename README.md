# ai-assisted-claude-coding-kit

A risk-tiered review pipeline and derived project state for AI-assisted coding with
Claude Code. Stack-agnostic baseline.

## What changed in 0.2.0

- **Distributed as a plugin**, not copied. Copies drift; versions are what make feedback
  from other developers interpretable.
- **Status is derived, not maintained.** Task files and git trailers are the truth.
  SQLite is a rebuildable index. `STATUS.generated.md` is output.
- **Zero MCP servers.** `git` and `sqlite3` are Bash calls at no resident cost. An MCP
  server for either would charge tool definitions on every request, forever.
- **Commands became skills — except the checkpoint, which became a hook.** A checkpoint
  that depends on someone typing `/checkpoint` is skipped exactly when sessions run long.
- **Findings are recorded with language and defect class**, which is the mechanism by
  which the accelerators are improved from real work rather than invented.

## Three principles

1. **One kind of truth, one file.** Anything derivable is derived. Nothing is maintained
   in two places.
2. **Verify at the level the failure lives.** The ladder states obligations, not commands.
   A rung with no tooling in this stack is *declared unavailable and raises the tier* —
   less mechanical verification means more adversarial reading, not a lower bar.
3. **Session length is the cost lever.** Tier before spawning. Load the least context
   that supports the work.

## Layers

| Layer | Holds | Resident cost |
|---|---|---|
| Always-on (`templates/CLAUDE.kit.md`) | tiering obligation, write boundary, where truth lives | ~15 lines, cached |
| Hooks | write guard, checkpoint, trailer validation | zero |
| Skills (5) | task-context, tier-classify, verify-ladder, status-report, checkpoint | ~100 tokens each at rest |
| Subagents | your reviewers | zero until spawned |
| MCP | none | zero |

Skill bodies and bundled scripts load only on use, so the whole tooling layer costs
roughly five descriptions at rest — in every repo on the machine, which is why the skill
count is fixed and **accelerators arrive as reference files, not new skills**.

## Install

```sh
/plugin marketplace add <this-repo-url>
/plugin install coding-kit@ai-assisted-claude-coding-kit
```

`coding-kit` is the plugin; `ai-assisted-claude-coding-kit` is the marketplace that
carries it. They are not interchangeable in that second command.

Then, in each repo that should use it:

```sh
bash ~/.claude/plugins/cache/ai-assisted-claude-coding-kit/tooling/kit-init.sh
```

The kit is **inert** in any repo without `.claude/project-profile.md` — every script
exits silently and creates nothing. It will be enabled in other people's unrelated
projects; it must not litter them.

## State lives in the project repo

```
.project/tasks/*.md      source of truth — intent, acceptance criteria   (committed)
.project/events.ndjson   append-only transitions and findings            (committed)
.project/index.db        derived index                                   (gitignored)
STATUS.generated.md      generated view                                  (gitignored)
```

Never in plugin storage: that is tied to the plugin's lifecycle, so uninstalling would
take a project's history with it. Deleting `index.db` and rebuilding must always be
lossless — that invariant is what keeps the index from quietly becoming a second truth.

## Dependencies

`git` **2.32 or newer** — older git cannot expand `%(trailers:…,valueonly)`, so every
commit would index as untagged; `kit-index.sh` warns if it finds one. Plus `sqlite3` and
the POSIX text utilities that ship alongside it: `awk`, `sed`, `grep`, `sort`, `cut`,
`tr`, `wc`. No language runtime. Bash is reachable on Windows via the shell git already
ships, and git is a hard dependency anyway since status is derived from it.

## Trailers — frozen once adopted

Trailers are written into commit history, so changing the vocabulary later means either
rewriting history or parsing two dialects forever.

| Trailer | Required | Values |
|---|---|---|
| `Task-Id:` | non-trivial commits | task ID |
| `Tier:` | non-trivial commits | `T0` `T1` `T2` `T3` |
| `Task-Status:` | when it changes | `started` `progress` `blocked` `unblocked` `done` `abandoned` |
| `Fixes-Escape-Of:` | on escape fixes | task ID |

`Tier:` is not bookkeeping. Without it, escape rate per tier is not computable, and the
tier table in `project-profile.md` stays a guess instead of becoming a measured output.

## Accelerators

Imported per project, never installed globally. See `accelerators/README.md`. The two
seeds shipped here are drafts — plausible, not observed. The findings table is what
replaces them with earned content:

```sh
sqlite3 .project/index.db "SELECT lang, class, COUNT(*) FROM finding
                            GROUP BY lang, class ORDER BY 3 DESC;"
```

## Known limits

- Full reindex only; no incremental. Fine at the scale this is built for.
- `depends_on` edges are built from declared `blocked_by` frontmatter and consumed by
  `kit-plan.sh`. What does not ship is a per-stack extractor deriving them from the code
  itself, so blast radius reports **unknown, not low** — `tier-classify` treats unknown
  as at least T2.
- The write guard is a net, not a security boundary. It fails open on a malformed payload,
  because a guard that blocks every edit on a parse error is a guard people remove.
- Coder and reviewer currently share a model family, so they share blind spots.
  "Independent judgment" is partly aspirational until that changes.
