# ADR 0009: Contribution is a set, assignment is a declaration

- **Date:** 2026-08-22   **Status:** **Proposed**   **Supersedes:** —   **Related:** [[0004-where-the-plan-lives]], [[0008-the-task-state-vocabulary-and-its-partitions]]

Decides the **shape** of two facts the kit currently has one broken column for: who has worked on
a task, and who is responsible for it now. It does not decide field names or write code — that is
`T-20260822-derived-owner-flips-to-whoever-committed` and
`T-20260822-a-task-has-no-authored-assignee-so-a-cla`. It exists because those two tasks would
otherwise each re-derive the same constraints, and because the constraint that rules out the
obvious design is not obvious.

Every figure below was produced by a command on this repository on 2026-08-22, named beside it.
ADR 0005 and 0006 were both rejected for a load-bearing claim that was confident, checkable and
false; the discipline is a response to that.

## Context

### One column is answering two questions

`kit-index.sh:1270` sets `task.owner` to the actor of the most recent activity event, ordered by
`seq`. **Reproduced**, one task, three commits, two authors:

    alice commits Task-Status: progress   ->  owner = alice
    bob   commits Task-Status: progress   ->  owner = bob
    alice commits Task-Status: progress   ->  owner = alice

It flips on every commit. After a merge, `seq` is rebuild order over the combined history, so the
value depends on which side committed last and changes again on the next rebuild with no edit to
any file.

The defect is not the query. It is that two different facts are wearing one column:

| | shape | authored by | behaviour |
|---|---|---|---|
| **Contribution** — who has worked on this | a **set**, monotonic | derived from history | never flips; only grows |
| **Assignment** — who is responsible now | a **declaration** | a person, in advance | contested; must conflict |

`owner` is *derived* like the first and *singular* like the second. It therefore reads as an
assignment and means "last committer" — authoritative-looking and wrong, which is worse than
absent.

### Multi-contributor is already the measured case, not a future one

    sqlite3 .project/index.db "select n, count(*) from (select task_id, count(distinct actor) n
      from event where actor<>'' and task_id<>'' group by task_id) group by n;"
    # 1 actor: 40 tasks    2 actors: 9 tasks

    git log --format='%(trailers:key=Task-Id,valueonly)' | grep -v '^$' | sort | uniq -c | sort -rn
    # up to 19 commits on one task

**Nine tasks already have two contributors and the column keeps one**, discarding the other with
no report that it did so.

### The two evidence sources disagree, and that must be decided rather than inherited

81 tasks have exactly one distinct **git author**, while 9 have two distinct **event actors**.
They are not measuring the same thing: `event.actor` is taken from git config at the moment an
event is written, so an agent-written event carries a different actor from the human who commits.
Whichever source a contribution set is built from, the other will disagree, and picking one
silently is how a number becomes untrustworthy.

### Nothing can currently declare a claim

    grep -n 'v\["owner"\]\|v\["assignee"\]' tooling/kit-index.sh   # frontmatter never read for it
    grep -nE '\-\-owner|\-\-assign'         tooling/kit-task.sh    # no flag
    grep -nE 'owner|assignee'               templates/task.md      # no field
    grep -n  'owner'                        tooling/schema.sql     # DERIVED column only

## The constraint that decides the design

**A claim cannot live in the cache.** `.gitignore:3` ignores `.project/index.db`, so it does not
exist in a fresh clone and is rebuilt per machine. A claim recorded there is invisible to a second
clone and to any agent working in one — while looking exactly as authoritative as a claim that
works. That is the failure mode this repository refuses everywhere else: a control whose failure
produces a confident wrong answer rather than an error.

**Nor can it live in the event log.** `.gitattributes:20` marks `.project/events.ndjson`
`merge=union`, deliberately, so concurrent appends merge cleanly. That is exactly wrong for a
claim: two people claiming the same task would both merge, and both would be valid.

**So it lives in the task file's frontmatter** — not because frontmatter is convenient, but
because it is the one location where two claimants produce a **merge conflict**, which is the
coordination signal wanted. The plan file is already treated this way and says so
(`.gitattributes:23`: *"Deliberately NOT merge=union, unlike the log above"*).

## Options

### Option A — fix the `owner` query

Order by commit date, or prefer the first actor rather than the last.

**Rejected.** Every variant still returns one name for a set of contributors. It answers a
question nobody asked, more consistently.

### Option B — add a `claimed` task state

**Rejected, on measured grounds.** `blocked` and `unblocked` have **zero uses across 130 tasks**
while `blocked_by:` is used by 3, because blockedness is carried structurally by the dependency
edge and `kit-plan.sh` reads that edge for layering. A `claimed` state repeats the shape: a state
duplicating something structural. It would also be unenforceable, and — if read from the cache —
authoritative-looking and wrong. ADR 0008 records the same evidence for refusing a `paused` state.

### Option C — two objects, separately shaped

Contribution derived as a set; assignment authored as a declaration in committed text.

**Adopted.**

## Decision

1. **Contribution is a SET, derived, monotonic.** Two contributors on one task must both survive a
   rebuild, and the value must not change when nothing has changed.
2. **Assignment is a DECLARATION, authored, in task-file frontmatter.** Set by a person or
   proposed by an agent, before the work, not inferred after it.
3. **Assignment is a set too**, not a single name. Nine tasks already have two contributors, and
   the operator's framing is contributors rather than an owner.
4. **A claim is ADVISORY.** The only mutual exclusion in a distributed repository is the push:
   first push wins, the second gets a non-fast-forward. Anything stronger claimed in
   documentation would be a control that cannot fail — `docs/LESSONS.md` §1.
5. **An agent may propose a claim and never self-certify one**, the same rule as `Via:` and as
   finding dispositions, for the same reason: a self-reported claim from the actor that benefits
   from it carries no information.
6. **`owner` as it exists is retired or redefined**, never left reading as an assignment while
   meaning last-committer.

## Consequences

**The two open tasks implement this and neither is a trial blocker.** Both say so in their own
Notes, and neither is added to `T-20260808-trial-the-kit-on-one-unfamiliar-brownfie`'s
`blocked_by`. The trial is single-operator; this matters for a team and for unattended agents,
which is later. Recording that here is deliberate: a backlog that grows blockers faster than it
closes them is the failure mode this session was called to break.

**The git-author versus event-actor disagreement becomes an explicit decision** with a named
answer, rather than whichever source the first implementation happened to read.

**Nothing here changes what is safe to run concurrently.**
`T-20260808-parallel-task-execution-has-no-isolation` owns that, and records that the obvious
approach is already measured void — a worktree path in a prompt does not isolate a subagent. This
ADR is about recording who did the work and who intends to; it provides no isolation and must not
be read as providing any.

**What is deliberately not decided:** the field names, whether `owner` is dropped or redefined,
which evidence source wins for contribution, and whether an assignment expires. Those belong to
the tasks, with the constraints above binding them.
