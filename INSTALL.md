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
is about, and the comparison you are running becomes uninterpretable. Unpinned resolves
to the default branch, which moves under you between one install and the next.

Tags are `vMAJOR.MINOR.PATCH`. See [`docs/VERSIONING.md`](docs/VERSIONING.md) for what a
bump means here — the compatibility surface is state committed to your repo, not an API.

Verify:

    /agents                    # the 8 should be listed
    /plugin                    # coding-kit enabled

The plugin is now available in *every* project on this machine. It stays inert in all
of them until a project opts in — see below.

---

## Which case are you in?

Three, and they need different things. Read the one you are in.

| | you have | go to |
|---|---|---|
| **B** | an empty folder — no git, no code | [B. Empty folder](#b-adopting-into-an-empty-folder) |
| **C** | a codebase with history that has never seen the kit | [C. Existing codebase](#c-adopting-an-existing-codebase) |
| **D** | a clone of a repository that already adopted it | [D. Joining](#d-joining-a-repository-that-has-already-adopted) |

B and C are both *adoption* and share steps 1-5 below; C additionally has to decide what the kit
should believe about history that predates it, which is the whole of its extra work. D is not
adoption at all — the decisions were made by whoever did B or C.

---

## B. Adopting into an empty folder

**`git init` first.** `kit-init.sh` locates the repository with `git rev-parse --show-toplevel`
and stops when there is none — it prints git's own `fatal: not a git repository` followed by
`not a git repository`, **and exits 0**, so a script that only checks the status code will
continue as though it worked.

    mkdir myproject && cd myproject
    git init
    $CLAUDE_PLUGIN_ROOT/tooling/kit-init.sh

Creates `.claude/project-profile.md`, generates the `commit-msg` and `pre-push` hooks, and writes
`.gitignore` / `.gitattributes` entries.

**What is inert until there is code**, so you do not spend an afternoon wondering:

- `commands.build` / `test` / `lint` / `typecheck` name tools that do not exist yet. Write them
  for the stack you are about to build, or leave them empty — an empty ladder rung is *declared*
  and raises the tier, which is the correct behaviour and not a bug.
- `tier.rule` globs match no files, so every task takes `tier.default` until directories exist.
- Co-change is derived from history. There is none, so blast radius is unknown for everything.
- **`kit-plan.sh` is at its measured worst here.** With no `touches` edges and no co-change, 22
  greenfield tasks collapsed into 2 layers and the scaffolding task everything depends on ranked
  eleventh. Until you have history, sequence the first few explicitly with `blocked_by:` in the
  task frontmatter rather than trusting the ordering. Known limit, owned by
  `T-20260801-kit-plan-has-no-notion-of-prerequisite-w`.

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

If the repository you are adopting is *itself* a Claude Code plugin, put it in
`.claude/CLAUDE.md` instead. Both locations load as project context, but a `CLAUDE.md` at a
plugin root is not loaded as plugin context, and `claude plugin validate --strict` fails on
one. This kit hit that when it adopted itself.

**3. Commit the shared parts.**

    git add .claude/project-profile.md .project/tasks .gitignore .gitattributes
    git commit -m "chore: adopt coding-kit"

**4. Delete any hand-maintained `STATUS.md` and task CSV.** Delete, not deprecate. A
surviving copy will be edited by someone, and then you have two truths again.

**5. Create work and go.**

    kit-task.sh --title "Bound retry budget" --tier T2 --lang go
    kit-index.sh && kit-plan.sh --next 5

---

## C. Adopting an existing codebase

Run the same `kit-init.sh` and the same steps 1-5 as B — the repository already exists, so there
is no `git init` question. What B does not have to decide, and you do, is **what the kit should
believe about the history that predates it.**

**1. Choose `git.adopted_at`.** One commit-ish in the profile, and it decides how much history
the indexer reads: it becomes the range `<adopted_at>..HEAD`, and unset means all of it.

- **Unset (all history).** Every pre-adoption commit is scanned and none of them carry trailers,
  so they all count as untagged and the trailer-discipline warning reads as though the team is
  ignoring the rule. What you get for it: `touches` edges and co-change over the full history.
- **Set to the adoption commit.** The discipline numbers describe only work done under the kit,
  which is the honest denominator. Cost: nothing before that point contributes edges.

Neither is wrong. Set it if you want the discipline metrics to mean something from day one;
leave it unset if you want blast radius from history more than you want clean counters.

**2. Expect the backlog to over-tier at first, and know why.** `touches` edges need a `Task-Id`
trailer, so a freshly adopted repository has an empty edge table. Blast radius is unknown for
everything, and unknown floors at T2 — so the whole backlog tiers high until trailers accumulate.
Co-change exists precisely to fill that gap and needs no trailers, only history; but it withholds
itself entirely if the graph comes out denser than `cochange.max_degree`, reporting nothing rather
than reporting "everything is connected to everything" with confidence. Both behaviours are
deliberate. Neither is a misconfiguration to hunt.

**3. Bring the backlog you already have.** A roadmap document, an issue tracker, or a tree of
analysis and task files does not need retyping into `kit-task.sh`. `ingest.tasks` in the profile
takes an executable that emits SQL, and the kit reads your source instead of its own — see
[docs/ADAPTERS.md](docs/ADAPTERS.md) and `templates/ingest-tasks-csv.sh`. Adapters are the
built-for-this answer to "we already have a backlog"; the index is derived and disposable, so
pointing it at your source loses nothing.

**4. Back-fill what was already finished — including work the kit did not do.** Mark completed
tasks `state: done` in their frontmatter, and add a lowercase **`via:`** key there (`kit`,
`agent`, `manual`) on work whose provenance you know. This matters more than it looks: escape
rate is reported over the kit-run population *and* over every task, side by side, so an
inventory that cannot say "done, but not by this pipeline" makes the pipeline look responsible
for outcomes it never touched. Provenance is set by you, never by the agent that did the work.

> The frontmatter key is lowercase **`via:`**, not `Via:`. `Via:` is the **git trailer**, and it
> only exists on a commit — which back-filled work does not have, since you cannot add a trailer
> to a commit already written. This paragraph said `Via:` for three days and the indexer, which
> reads `via`, silently recorded every back-filled task as `unknown`.

**5. A `Task-Id` that matches no task file** — from a typo, or from a task you have not filed yet
— is **not** counted as work. It is named in the `Unresolved task ids` section of
`STATUS.generated.md`, with the commit that introduced it, and it reconciles automatically if the
file turns up later. On a brownfield history you may have several; they are evidence about
trailer discipline rather than a backlog.

---

## D. Joining a repository that has already adopted

    git clone <repo> && cd <repo>
    $CLAUDE_PLUGIN_ROOT/tooling/kit-init.sh     # says "joined an already-adopted repo"
    $CLAUDE_PLUGIN_ROOT/tooling/kit-index.sh

That is the whole thing. Your profile, the backlog and the event log arrived with the
clone; the index is rebuilt locally and never shared.

**Why running `kit-init.sh` is not optional.** Git does not share hooks. `.git/hooks/`
is per-clone, so trailer validation does not exist for you until you generate it. The
hooks are generated rather than symlinked because the plugin's path differs per machine.

Two are generated, and they guard different moments:

| | when | why both |
|---|---|---|
| `commit-msg` | as you commit | cheapest place to fix a trailer — you are still writing it |
| `pre-push` | before anything is shared | `--no-verify` skips the first, and a teammate who never ran `kit-init.sh` never had it |

`pre-push` is the last point a wrong trailer can still be corrected. After a push, a commit
message can only be changed by rewriting shared history, so a typo'd `Task-Id` becomes permanent.
It no longer becomes a phantom task: an id with no task file is reported under `Unresolved task
ids` with the commit that introduced it, and is in no backlog count or escape-rate denominator.
This kit carries one from before the hook existed, and it appears there.

---

## The CI gate — the only check that survives a clone

Because hooks are per-clone, a teammate who skips `kit-init.sh` has **no** enforcement,
and the repo looks protected. Copy `templates/github-trailer-gate.yml` to
`.github/workflows/kit-trailers.yml` and commit it:

    cp $CLAUDE_PLUGIN_ROOT/templates/github-trailer-gate.yml .github/workflows/kit-trailers.yml

It checks out the kit at a pinned tag and runs `kit-trailers.sh range … --enforce` over the
commits in a pull request. Pin it: an unpinned gate changes its own rules under you, and
then a red build tells you nothing about whether your commits moved or the rules did.

The hook and the gate call the **same** validator. That is not tidiness — 0.2.1 fixed a bug
that existed precisely because two readers of the same trailers disagreed, so commits passed
one check and vanished at the other. Two copies of these rules would drift; one cannot.

**What CI cannot see.** If you squash-merge, GitHub composes a new commit message at merge
time from the PR title and body, editable in the merge dialog, and no CI run observes it
before it lands. The workflow's `push` trigger is the mitigation: it checks after the fact,
so a bad squash turns the default branch red immediately rather than quietly costing you a
task. That is detection, not prevention. For prevention with squash-merge, require the check
on a merge queue, which builds the real merge commit before it lands.

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

    python3 validate.py                                            # structure (bundled)
    claude plugin validate . --strict                              # marketplace manifest
    claude plugin validate .claude-plugin/plugin.json --strict     # plugin manifest

**Both `claude plugin validate` invocations are needed.** The command validates one
manifest, chosen from the path you give it — and because the plugin and the marketplace
share a root here, plain `.` resolves to `marketplace.json` and the plugin manifest is
never checked. `--strict` turns warnings into a non-zero exit, which is what you want in
CI and before publishing.

The bundled one catches what silently produces a plugin that loads but does nothing:
components in the wrong directory, stray `.md` files in `agents/` being loaded *as*
agents, hook commands missing `${CLAUDE_PLUGIN_ROOT}`, absolute paths from the author's
machine. Run all three before publishing.

### Seeing what it costs to have installed

    claude --plugin-dir . plugin details coding-kit

Component inventory plus projected token cost, split into always-on and on-invoke. This is
the number to watch when adding a skill or an agent — **agent descriptions are resident**,
because that is how the harness routes to them, so an agent is not free until spawned.
