# Ingest adapters

The kit derives project state from text sources. This document is the contract for
replacing one of those sources — with GitHub issues, a REST API, a hosted database, or a
CSV — without touching the indexer.

## The seam

`kit-index.sh` has two halves:

| Sections | Job | Knows about the source? |
|---|---|---|
| 1 — tasks | task identity, title, epic, tier, lang, dependencies | yes |
| 2 — commits | git trailers → state transitions and `touches` edges | yes |
| 3 — events | findings, vindications, transitions without a commit | yes |
| **4 — derivation** | current state, ownership, escape rate, tier resolution | **no** |

Everything above section 4 turns a source into SQL. Section 4 derives state from that SQL
and cannot tell where it came from. Replacing a source therefore means replacing one
producer, not rewriting the indexer.

**This only works because the index is derived.** Delete `index.db`, rebuild, and nothing is
lost — that invariant is what makes the ingest half interchangeable at all. An adapter that
puts something in the index that exists nowhere else breaks it, and everything here with it.

## Selecting sources

In `.claude/project-profile.md`:

```
ingest.tasks:   files      # files  | none | <path to executable>
ingest.events:  ndjson     # ndjson | none | <path to executable>
ingest.commits: git        # git    | none
ingest.extra:   <path>     # repeatable; always additive, never replaces a built-in
```

`none` disables a source.

### Where an adapter may live — enforced, not advised

**A path must be repository-relative, and the file must be tracked by git.** Both are refused by
`run_adapter` before anything executes, and a conformance step proves all three directions —
untracked refused, absolute refused, and a tracked adapter still running.

```
ingest.extra: tools/my-adapter.sh     # ok, once `git add`ed
ingest.extra: /opt/thing/adapter.sh   # REFUSED — not repo-relative
ingest.extra: ../shared/adapter.sh    # REFUSED — climbs out of the repository
ingest.extra: tools/new.sh            # REFUSED until tracked — an untracked file is in no diff
```

**Why.** The kit does not merely read what an adapter prints — it **executes** it, as a process
and again by feeding its stdout to the `sqlite3` CLI. The profile naming it sits inside the
project root, where `kit-guard.sh` permits every write by design, so without this an agent could
write an adapter and a profile line in one turn and get code execution on the next index. And
`kit-index.sh --if-stale` runs at the start of every session.

**The bound, stated so nobody reads more into it.** This binds a confused agent, a profile copied
between projects, and an ad-hoc path. It does **not** bind a determined one: `git add` is a `Bash`
call and the hook matcher is `Write|Edit|NotebookEdit`. `SECURITY.md` §4 keeps the sandbox gap;
ADR 0003 records the decision, the alternatives, and this limit.

**What is still convention.** That the tracked adapter is the one the *project* intended — as
recorded in the solution overlay or an ADR — is not checked by anything. Nothing compares the
profile against the overlay today, because the overlay is not yet built. Until it is, the
documented choice binds by review rather than by mechanism.

### Writing your own

An adapter is ordinary code that runs with the operator's permissions. Treat authoring one as
authoring privileged code: it emits SQL that is executed against the index.

Built-in sources run inline rather than through a process boundary. A bare process spawn
costs ~0.2s on Windows and the indexer runs at the start of every session, so paying three
of them to make the default path symmetrical would undo the optimisation section 1 exists
for. They honour the same contract; they are simply not invoked across a process boundary.

## The contract

An adapter is an executable invoked with one verb.

### `emit`

Write SQL to stdout. Nothing else — stderr is discarded, and any non-zero exit aborts the
build.

Insert into the tables you are the source for. `INSERT OR REPLACE` for rows you own,
`INSERT OR IGNORE` for edges. Do not write to `plan_item` or `goal` — those belong to
`kit-plan.sh` — and do not update anything section 4 derives (`task.state`, `task.owner`,
`task.closed_at`, `finding.tier`), because it will be overwritten in the same transaction.

A task-source adapter emits, per task:

```sql
INSERT OR REPLACE INTO node VALUES('<id>','task',NULL,'<title>');
INSERT OR REPLACE INTO task(id,epic,state,tier,lang,blocked_by)
  VALUES('<id>','<epic>','open','<tier>','<lang>','<blocked_by>');
INSERT OR IGNORE INTO edge VALUES('<id>','<dep-id>','depends_on');
```

Escaping is doubled single quotes and nothing else. `templates/ingest-tasks-csv.sh` is a
complete worked example, and mirrors section 1 row for row.

### `fingerprint`

Write a short opaque string describing the current state of the source.

This exists because `--if-stale` compares mtimes, and mtime is meaningless for a remote
source: a GitHub issue changes with no local file touched, so mtime would report fresh
forever and the index would quietly serve stale state. The fingerprint is stored in `meta`
under `fingerprint:<spec>` and compared on the next run.

An adapter that cannot answer honestly should print nothing, which forces a rebuild every
time. That is slow and correct, which is the right way round.

## Guarantees the indexer makes

**Failure leaves the index unchanged.** The whole build is assembled before the existing
`index.db` is touched. An adapter for a remote backend fails whenever the network does, and
destroying the index first would turn a transient outage into an empty backlog — which reads
as a finished project. On adapter failure `kit-index.sh` exits non-zero and says the index is
stale rather than wrong.

**Adapters run before any derivation**, so an adapter never has to reproduce derived state.
Emit facts; let section 4 do the rest.

## Guarantees an adapter must make

**Deterministic and idempotent.** Two runs against an unchanged source must produce
byte-identical SQL. Delete-and-rebuild is verified as lossless; an adapter that orders its
output by a hash-map walk or stamps a timestamp breaks that quietly, and breaks it across a
team rather than on one machine.

**Timestamps in canonical UTC: `YYYY-MM-DDTHH:MM:SSZ`.** Every timestamp column is TEXT and
every `ORDER BY` in the derivation compares it as a **string**, so lexical order has to be
chronological order. That holds only if every source renders in one zone and one format.

This is not theoretical. Before 0.5.2 the git source used `%aI`, which carries the author's
local offset: a commit at `05:30+05:30` sorted *after* one at `02:00Z` despite being earlier,
and state, owner and tier could be derived from the wrong commit. A GitHub adapter passing
through `created_at` unmodified would be fine — that API returns `Z` — but one reading a
database column typed `TIMESTAMP WITH TIME ZONE`, or a CSV written by a spreadsheet in local
time, would put the same defect back through a different door.

Convert at the adapter boundary. Do not assume the upstream already agrees.

**No schema statements.** `ATTACH`, `DETACH`, `PRAGMA`, `DROP`, `ALTER` and `VACUUM` are
refused and abort the build.

That filter is a net, not a security boundary. An adapter is named in a committed, reviewed
profile and necessarily emits SQL that gets executed — it is trusted code by construction.
The filter catches an adapter that reshapes the database by accident, not one that intends
to. Review adapters the way you review anything else that runs in your repository.

## Environment

| Variable | Meaning |
|---|---|
| `KIT_ROOT` | repository root, absolute |
| `KIT_PROFILE` | path to `project-profile.md` |
| `KIT_STATE_DIR` | `paths.state`, relative to root |
| `KIT_TASKS_DIR` | `paths.tasks`, relative to root |
| `KIT_ADOPT` | `git.adopted_at`, possibly empty |
| `KIT_DB` | path the index will be written to — for reference, **do not write to it** |

Credentials are not passed. An adapter needing a token reads it from the environment the
developer already has, or from a helper; never from the profile, which is committed.

## Worked example

```
ingest.tasks: .claude/ingest-tasks-csv.sh
```

```sh
cp $CLAUDE_PLUGIN_ROOT/templates/ingest-tasks-csv.sh .claude/
kit-index.sh
```

Task rows now come from `.project/tasks.csv`; commits and events still come from git and
`events.ndjson`; `kit-plan.sh`, `kit-status.sh` and `task-context` are unchanged and unaware.

## What this does not solve

Task **identity** must stay stable across rebuilds, because commit trailers reference task
ids and `Task-Id` is written into history permanently. An adapter keyed on something
mutable — a GitHub issue title, a row's position — breaks the link between commits and
tasks the first time that value changes, and the commits index as untagged with no error.
Use the issue number, not the title.
