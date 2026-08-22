# ADR 0008: The task state vocabulary, and where its partitions live

- **Date:** 2026-08-22   **Status:** **Accepted**   **Accepted:** 2026-08-22   **Supersedes:** —   **Related:** [[0004-where-the-plan-lives]]

Decides what a task's state can be, what a commit trailer can record, and where the open/closed
question is answered. Written for `T-20260808-task-state-cannot-express-no-longer-rele`, whose
framing this ADR **amends on two measured points** rather than implementing as written.

Every number below was produced by a command on this repository on 2026-08-22, and the command is
named beside it. ADR 0005 and ADR 0006 were both rejected for a load-bearing claim that was
confident, checkable and false; the discipline here is a response to that, not decoration.

## Context

### What the task asked for

One new state meaning *"this should not be done at all"*, distinct from `abandoned` (*"we
stopped"*) — attempt versus work. The stated harm: a brownfield inventory has items that were
never work, and filing them as `abandoned` misreports the project.

### Fact 1 — half the declared vocabulary has never been used

    for s in started progress blocked unblocked done abandoned; do
      grep -h "^state: $s\$" .project/tasks/*.md | wc -l
      git log --format='%(trailers:key=Task-Status,valueonly)' | grep -cx "$s"
      sqlite3 .project/index.db "select count(*) from event where kind='$s';"
    done

| state | frontmatter | trailer | events |
|---|---|---|---|
| started | 0 | 7 | 9 |
| progress | 0 | 87 | 88 |
| **blocked** | **0** | **0** | **0** |
| **unblocked** | **0** | **0** | **0** |
| done | 15 | 33 | 34 |
| **abandoned** | **0** | **0** | **0** |
| **open** | **115** | — | — |

Two consequences, and both amend the task.

**`abandoned` has zero instances**, so the harm the task describes has not occurred here and
cannot be pointed at. It remains a real prospective risk for brownfield adoption — which is the
case the kit is being readied for — but this ADR states it as prospective. Asserting an observed
distortion would be the exact failure that killed 0005.

**`open` is used 115 times and is not in the declared vocabulary** (`kit-trailers.sh:115`). The
validator has never seen it, because it validates the *trailer*, and `open` only ever appears in
frontmatter.

**`blocked` and `unblocked` are dead for a structural reason**, not by accident:

    grep -l '^blocked_by:' .project/tasks/*.md | wc -l          # 3
    sqlite3 .project/index.db "select count(*) from task where state='blocked';"   # 0

Blockedness is expressed by the `blocked_by:` edge, which `kit-plan.sh` reads for topological
layering. A state saying the same thing is redundant, and was never written. **This is evidence
about what kind of value survives here**, and it is why the lifecycle below has no `paused`.

### Fact 2 — validation has one home; the partition has nineteen

    grep -rc "'done','abandoned'" tooling/          # 19 occurrences, 4 files

| file | sites |
|---|---|
| `kit-status.sh` | 7 |
| `kit-index.sh` | 6 |
| `kit-plan.sh` | 5 |
| `kit-lib.sh` | 1 |

The vocabulary is enforced once, at `kit-trailers.sh:115`. The *partition* it feeds — which
states count as closed — is written out nineteen times. Adding a seventh value means finding all
nineteen and judging each, which is the drift `LESSONS.md` §4 describes: *"Filing a defect class
is not the same as sweeping for it, and the sweep is the cheap half."*

**And there were two more copies outside the code**, found only while implementing this:
`README.md` and `docs/HANDOFF.md` each carry a hand-written list of the vocabulary in a
reader-facing table. Both went stale the moment the values changed. The single-home check that
guards `kit_via_vocab` greps `tooling/` and `tests/` only, so nothing was watching them — the
sweep in §4 was itself swept short. A reader-facing table is legitimate documentation rather
than a second definition, so the answer is not to ban it but to require it to **agree**, which
is now asserted.

### Fact 3 — states and transitions are different objects

The measured split is clean. Trailers carry `started`, `progress`, `done`. Frontmatter carries
`open`, `done`. They overlap only on `done`.

That is not an accident of usage: **a trailer records a transition a commit made, and frontmatter
records the state a task rests in.** `open` is a state nobody transitions *to* — it is where a
task begins. `started` and `unblocked` are transitions with no restful state behind them, which
is a second reason they are thin or dead.

Conflating them is why the vocabulary reads as a bag of values rather than a lifecycle.

### Fact 4 — the task's escape-rate claim is false

The task says *"Escape rate and the tier reports count `done` and `abandoned` as closed."* For the
tier reports this holds (`kit-status.sh:701`, `:711`, `:712`). **For escape rate it does not.**
The denominator at `kit-status.sh:208-213` is:

    FROM task t LEFT JOIN event e ON e.task_id=t.id
    GROUP BY COALESCE(NULLIF(t.tier,''),'untiered')

There is **no state filter at all**, and the comment above it says that is deliberate: *"the `all`
column has no WHERE clause, so it counts the escapes of every task in the index … That is what
makes disappearance impossible by construction rather than by care."*

So the task's acceptance criterion — *"assert that a task in the new state is excluded from the
escape-rate denominator"* — would, implemented literally, **add a `WHERE` clause to the one query
built without one on purpose**, destroying a property that was argued for and won.

Where the harm actually lands is `kit-status.sh:56-58`, which prints `- N done, M abandoned` as a
headline. That is what would read as *"a project that abandons a great deal."*

## Options

### Option A — add one value beside the existing literals

Add `not-relevant` to `kit-trailers.sh:115` and update the nineteen partition sites by hand.

**Rejected.** It leaves nineteen copies of the rule, so the twentieth site written later will be
wrong, and nothing detects it. `LESSONS.md` §5: *"Prefer deleting a component to hardening it …
the cheapest component to secure is the one you deleted."* ADR 0004 set the same precedent when it
deleted the second plan writer rather than adding a conformance step to detect drift between two.

### Option B — one home for the vocabulary and its partitions, then the value

Introduce the definitions in `kit-lib.sh` beside `kit_via_vocab`, migrate every site to read them,
then add the value in that one place.

**This is the mechanism adopted.** `kit_via_vocab` (`kit-lib.sh:109-126`) already solves this exact
problem in this exact file, with a conformance step (`tests/conformance.sh:2737`) asserting no
second copy exists. Its own comment records why: *"The finding vocabulary was restated in four
places once and the agents emitted values the recorder threw away; this one starts with a single
home."*

### Option C — replace the bag of values with a lifecycle

Beyond the mechanism, change *what the values are*: a named lifecycle rather than six values of
which three are dead.

**Adopted, on operator input.** It supersedes the task's AC1 (*"one new value … with the existing
ones"*), which is recorded here rather than left implicit.

## Decision

### The state vocabulary — seven values, in frontmatter

| state | meaning |
|---|---|
| `created` | filed, after research and task segregation; not yet planned |
| `planned` | implementation approach decided and written down |
| `in-progress` | development or testing under way |
| `on-hold` | deliberately not being worked, after creation |
| `completed` | implementation finished |
| `cancelled` | **no longer relevant — this should not be done.** A judgement about the WORK |
| `abandoned` | **we stopped. A judgement about the ATTEMPT** |

`cancelled` and `abandoned` are both kept, and keeping both is the point of the task. Collapsing
them in either direction loses the distinction: filing dropped attempts as `cancelled` asserts
they were never worth doing, which is the original complaint mirrored.

**Why a lifecycle rather than the minimum viable set — the operator's reasoning, recorded because
it answers a challenge raised against this ADR in review.** The objection was that `abandoned` has
zero uses and `planned` has no consumer, so both are vocabulary grown on a forecast. The answer is
that the audience is not this repository:

- **The states are what a coding agent MARKS as work progresses**, not labels a human curates
  afterwards. A kit that moves a task through a lifecycle needs the lifecycle to exist first. The
  model is a Kanban board — cards move between named columns — and users arriving from Jira and
  similar tools will expect those columns to be there.
- **`completed` is terminal and is not retracted.** If the functionality is later changed or
  removed, that is a **new task**, not a retroactive edit of the old one. This is what stops
  `cancelled` from being used to rewrite history, and it is why the two closed-but-different
  verbs do not overlap in practice.

### `planned` has a consumer, and it is the agent

`planned` means an implementation approach exists and has been **reviewed** — whether a human
architect wrote it, or it came out of a coding agent's plan mode, or the two arrived at it
together. It is not a synonym for "not started yet".

The challenge against it was that no code reads it differently from `created`, which is exactly
how `blocked` and `unblocked` died. The distinction is that **its consumer is the next agent, not
the planner**: on a large task, `planned` is the difference between "implement this" and
"implement this, and the approach was already agreed" — which is the safer instruction, and the
one a reader can check.

On small tasks the state is skipped, and that is expected rather than a gap. Recording it
uniformly is what makes it verifiable: **the value is committed to git**, so another developer's
kit deployment sees the same state and the same dependencies for that task, without needing the
conversation it came from.

**No `paused`.** Blockedness is already carried by `blocked_by:`, and the measured fate of
`blocked`/`unblocked` — zero uses across 130 tasks — is what a redundant state gets here.

### Legacy values are ALIASES, normalised at the boundary — nothing is rewritten

The old values are not removed and no existing file or commit has to change. They stay **accepted
input**; the seven above are what is **stored and queried**. One mapping, applied once, where the
index is built:

| written | stored |
|---|---|
| `open`, `created` | `created` |
| `started`, `progress`, `unblocked` | `in-progress` |
| `blocked` | `on-hold` |
| `done`, `completed` | `completed` |
| `abandoned` | `abandoned` |
| `cancelled` | `cancelled` |

**This is forced for trailers and free for frontmatter.** 127 commits already carry
`Task-Status:` and are immutable:

    git log --format='%(trailers:key=Task-Status,valueonly)' | grep -v '^$' | sort | uniq -c
    # 33 done, 87 progress, 7 started

`kit-index.sh:1232` derives state from them, so a rename that orphaned them would delete readable
history to gain a tidier word. Having built the mapping for trailers, applying it to frontmatter
costs nothing and buys the whole migration.

**Normalising at the boundary is what keeps this simple rather than doubling the problem.** The
alternative reading of "keep the old ones too" — every consumer accepting both spellings — would
put two names for one state into nineteen partition sites, which is the drift this ADR exists to
end, made worse. Because the mapping runs once at index time, **every consumer downstream sees
exactly seven values** and no query is more complex than it is today.

Applied in two places only: `kit-index.sh:402`, where frontmatter state is read (and which
already defaults a missing value to `open`), and `:1232`, where the last transition event
overwrites it.

**Legacy usage is reported, not absorbed.** `kit-status.sh` gains a count of task files still
carrying legacy spellings. Silent acceptance is how two vocabularies become permanent; a number
that a reader can watch fall is how one drains. The count is expected to start at **130** —
115 `open` and 15 `done` — and no work is required to reduce it.

### The three partitions, and why one boolean is not enough

| definition | contents | read by |
|---|---|---|
| `kit_state_vocab` | all seven | `kit-trailers.sh`; the three `e.kind IN (…)` lists in `kit-index.sh` |
| `kit_state_closed` | `completed`, `cancelled`, `abandoned` | `kit-plan.sh` (5 sites), `kit-status.sh` open counts, `kit-lib.sh:105` |
| `kit_state_measured` | `completed`, `abandoned` | the populations that judge the pipeline |

**`cancelled` is closed but not measured, and that combination is the whole decision.** Work that
was never work must not count toward what the pipeline did or failed to do. `abandoned` *is*
measured: it was real work that this pipeline touched, and hiding it would flatter the record.

### The escape rate keeps its missing `WHERE` clause

The task's AC is **amended, not implemented**. The `all` denominator stays unfiltered, because
disappearance-by-construction is worth more than a tidier ratio, and because that property was
argued for once already and nothing here refutes it.

Instead, `cancelled` is reported **beside** the figure rather than subtracted from it — the
practice `LESSONS.md` §11 already names, *"record the measured value beside the required one"* —
and the `- N done, M abandoned` headline at `kit-status.sh:56-58` gains `cancelled` as its own
count, which is where the misreport the task describes would actually appear.

## Consequences

**A two-step migration, and the order is the safety property.** First the nineteen partition sites,
the three transition lists and the validator are migrated to read the new definitions, with the
sets **identical to today's literals** — a pure refactor, proven by a green conformance run before
any value changes. Only then are the lifecycle values introduced. Doing both at once would leave
any failure ambiguous between refactor and semantics, and this repository has paid for exactly that
ambiguity before.

**No task file has to change, and no commit is rewritten.** An earlier draft of this ADR migrated
130 task files; the alias table removes that step entirely. It was the largest and riskiest part
of the change and it bought nothing that normalising at the boundary does not buy more cheaply.
Files may be updated lazily, or never.

**Three dead values become aliases rather than being deleted.** `blocked` and `unblocked` are
superseded in meaning by `blocked_by:`, which `kit-plan.sh` already reads for layering; they map
to `on-hold` and `in-progress` so that any repository that did use them keeps working. Deleting a
declared value is a separate decision with its own migration question, and this ADR does not take
it.

**`open` stops being an undeclared value.** It has been the most-used state in this repository
(115 of 130 task files) while absent from the only list that claims to enumerate states. After
this it is a declared alias of `created`, which is what it always meant.

**A conformance case that fails on the pre-change tree**, per `LESSONS.md` §1 — a green check that
cannot fail is worse than no check. Four assertions:

1. the validator accepts the new values and still accepts every legacy one;
2. a task written `state: open` **indexes as `created`**, and one written `Task-Status: done`
   indexes as `completed` — the alias table binding, not merely being documented;
3. a `cancelled` task is absent from `kit_state_measured` while a `completed` one is present —
   the assertion with teeth, since this is the distinction the whole task exists to create;
4. each definition appears in exactly one file, extending the check that already guards
   `kit_via_vocab`;
5. the reader-facing tables in `README.md` and `docs/HANDOFF.md` list the same states the code
   defines — the gap that let both go stale unnoticed.

Assertion 2 is the one that would silently rot: an alias table that is written down but not
applied looks identical to one that is applied, until a query returns nothing. Assertion 5 was
added *because* it had already failed: both documents were stale when this was implemented, and
verifying that the new check bites on the pre-change tree confirmed it rather than assuming it.

**What this does not decide.** Whether `kit-plan.sh` should surface `on-hold` differently from
`created` in its layering — both are open, both are plannable, and no evidence here says they
should differ. And it takes no position on ADR 0007, which
`T-20260821-if-stale-watches-the-head-file-which-git` reserves for the disposition-evidence
successor to ADR 0006.
