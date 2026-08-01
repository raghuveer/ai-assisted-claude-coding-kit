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
3. **Spawning is the cost lever, and reuse is the only way to lower it.** Tier before
   spawning, because one task is two agents and one design stage is three. Then make the
   result reusable — a finding that becomes an accelerator is paid for once, and a session
   trimmed by a few thousand tokens is not.

## What it costs

Measured on a real greenfield project, not estimated. Full figures and method in
[`docs/MEASUREMENTS.md`](docs/MEASUREMENTS.md).

| | tokens |
|---|---|
| One T2 task — coder + implementation review | **220,336** |
| One T3 design stage — researcher + two reviewers | **196,060** |
| Resident always-on cost | **1,259** — *0.57% of one task* |

**This kit does not save tokens. It spends them deliberately.** Read the third row against
the first: everything the plugin costs by merely being installed is half a percent of a
single task. Optimising it is not where the money is, and a document that leads with it is
pointing at the wrong number.

The cost lever is **how many agents you spawn and on which model**, which is what
`tier-classify` exists to decide. And the models cannot simply be downgraded: measured on
one design review, haiku missed the critical security finding entirely and sonnet found it
but returned REVISE where opus returned REJECT — a calibration failure, and the more
dangerous kind. The tiering is expensive on purpose.

### What that buys

On the same project: two High security findings absent from a 28-item human review
register, and two escapes found in work that had already passed review and been committed.
One of those escapes had `ladder.rung3` reporting **available** while proving nothing, so
every task was being reviewed one rung shallow.

Whether that is worth 220k per task is a judgement about your defect economics, and the kit
should give you the number rather than an adjective.

### The bet

Per project, per task, this costs more than it returns. The wager that changes that is
**amortisation**: the 196k spent designing a cache port is a one-time cost if it becomes an
accelerator and a recurring one if it does not. Trimming context within a session cannot
compete with not re-deriving the same design in the next project.

That bet is currently **unproven**. It was unprovable until the findings loop was repaired,
because nothing was accumulating. The test that settles it is to earn an accelerator on one
project, import it into a second, and measure whether the equivalent stage costs 196k or
30k.

### Resident cost, for completeness

~1,259 tok: five skills at ~440, eight subagent descriptions at ~840, hooks and MCP at zero.
Agent descriptions are resident because routing matches against them, so all eight are in
context whether or not any runs. Bodies load only on use.

It is a footnote, not a headline — but it is why **accelerators arrive as reference files
rather than new skills or agents**: a reference file costs nothing until read, and the
catalogue is meant to grow without bound.

## Install

```sh
/plugin marketplace add raghuveer/ai-assisted-claude-coding-kit
/plugin install coding-kit@ai-assisted-claude-coding-kit
```

`coding-kit` is the plugin; `ai-assisted-claude-coding-kit` is the marketplace that
carries it. They are not interchangeable in that second command.

Pin a version when handing it to others — `@ref` with no version resolves to the default
branch, which moves:

```sh
/plugin marketplace add raghuveer/ai-assisted-claude-coding-kit@v0.2.0
```

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
commit would index as untagged; `kit-index.sh` warns if it finds one.

`sqlite3` **3.25 or newer** for cluster context packs, which use window functions.
Everything else works on 3.8+; `kit-plan.sh` warns and withholds the packs rather than
failing, so an older sqlite costs you the caching, not the plan.

Plus the POSIX text utilities that ship alongside those: `awk`, `sed`, `grep`, `sort`,
`cut`, `tr`, `wc`. No language runtime. Bash is reachable on Windows via the shell git
already ships, and git is a hard dependency anyway since status is derived from it.

## Platforms

| | verified on | awk | bash |
|---|---|---|---|
| Linux | CI, every push | mawk | 5.2 |
| macOS | CI, every push | one-true-awk 20200816 | **3.2.57** |
| Windows | git-bash | gawk 5.0 | 5.2 |

Not a compatibility claim — `tests/conformance.sh` builds a fixture with fixed author and
committer dates, so every commit SHA is identical everywhere, and asserts that the derived
index comes out byte-identical. All three currently produce the same fingerprint.

That check exists because it earned its place: running one fixture on a second platform is
what exposed timestamps being stored with the author's local offset and compared as strings,
which could derive state from the wrong commit. Neither platform showed anything wrong
alone — only the diff between them did.

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

**Trailers must be the last paragraph.** Git only parses a trailer block at the end of the
message, so anything after them — most commonly the `Co-authored-by:` lines GitHub appends
on squash-merge — strands them where `%(trailers:)` cannot see them. The `commit-msg` hook
rejects that shape, and `kit-index.sh` recovers it with a full-message scan and says so,
because a merge flow that mangles trailers will also defeat anything else that reads them.

**Enforcement needs both sides.** `.git/hooks/` is per-clone and git cannot share it, so
the hook only protects developers who ran `kit-init.sh`. Copy
`templates/github-trailer-gate.yml` into `.github/workflows/` for the server-side check
that survives a clone. Both call the same validator — `tooling/kit-trailers.sh` — because
two copies of these rules would drift, which is the bug 0.2.1 existed to fix.

## Accelerators

Imported per project, never installed globally. See `accelerators/README.md`. The two
seeds shipped here are drafts — plausible, not observed. The findings table is what
replaces them with earned content:

```sh
sqlite3 .project/index.db "SELECT lang, class, COUNT(*) FROM finding
                            GROUP BY lang, class ORDER BY 3 DESC;"
```

## Documentation

| File | What it answers |
|---|---|
| [`INSTALL.md`](INSTALL.md) | Installing, adopting in a new repo, joining one that already uses it |
| [`docs/HANDOFF.md`](docs/HANDOFF.md) | Why it is built this way — requirements, decisions with rationale, verified state, open gaps, and the constraints that must not be broken |
| [`docs/VERSIONING.md`](docs/VERSIONING.md) | What MAJOR/MINOR/PATCH mean here, tag format, and the release sequence |
| [`docs/ADAPTERS.md`](docs/ADAPTERS.md) | Reading project state from somewhere other than the built-in text sources — GitHub issues, an API, a database |
| [`docs/MODELS.md`](docs/MODELS.md) | Which tier each agent runs on, pointing the kit at your own endpoint, and why agent frontmatter must never pin a model ID |
| [`docs/MEASUREMENTS.md`](docs/MEASUREMENTS.md) | What the kit actually cost and found on a real greenfield run, and what remains untested |
| [`docs/DESIGN-NOTES.md`](docs/DESIGN-NOTES.md) | Proposed and **not built**: per-component accelerator binding, the solution overlay, a versioned accelerator library — and what must be measured before any of it ships |
| [`docs/MIGRATION.md`](docs/MIGRATION.md) | Moving from the 0.1 copy-based kit: commands → skills → hooks, and what was retired |
| [`docs/agents-README.md`](docs/agents-README.md) | The subagent pipeline, risk tiering, and how routing picks a model |

Read `docs/HANDOFF.md` before changing anything structural. It records the reasoning behind
decisions that look arbitrary from the code alone — why the index is disposable, why cycles
are withheld rather than ordered, why accelerator export redaction is structural rather
than procedural.

## Known limits

- Full reindex only; no incremental. Fine at the scale this is built for.
- `depends_on` edges are built from declared `blocked_by` frontmatter and consumed by
  `kit-plan.sh`. What does not ship is a per-stack extractor deriving them from the code
  itself, so blast radius reports **unknown, not low** — `tier-classify` treats unknown
  as at least T2.

  Co-change edges narrow this without closing it. They are derived from raw history and
  need no trailers, so a repository adopted brownfield gets *some* signal on day one — but
  measured recall@10 is 0.24, meaning roughly three quarters of genuinely related files are
  absent. They turn "unknown" into "unknown, and at least these", never into "only these",
  and `kit-index.sh` withholds the graph entirely when it measures as a hairball.
- The write guard is a net, not a security boundary. It fails open on a malformed payload,
  because a guard that blocks every edit on a parse error is a guard people remove.
- Coder and reviewer currently share a model family, so they share blind spots.
  "Independent judgment" is partly aspirational until that changes.
