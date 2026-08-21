---
id: T-20260821-if-stale-watches-the-head-file-which-git
title: if-stale watches the HEAD file which git never touches on commit so a commit reads as fresh
epic: measurement
tier: T3
lang: bash
paths: tooling/kit-index.sh, tooling/kit-preflight.sh, skills/task-context/SKILL.md
state: open
---

## Intent

`kit-index.sh --if-stale` decides whether to rebuild by comparing mtimes against a `WATCH` list:
the profile, the tasks directory, `events.ndjson`, the plans directory, and **`.git/HEAD`**.

`.git/HEAD` is the wrong file. On a branch it holds the text `ref: refs/heads/main` and **git does
not rewrite it when you commit** — the commit updates `refs/heads/<branch>`. So every input derived
from git history is invisible to the staleness check.

Measured on this repository 2026-08-21, and this is the whole finding:

    .git/HEAD              mtime  19:24:26
    .git/refs/heads/main   mtime  19:41:14
    tip commit (c873d73)          19:41:14

**`.git/HEAD` is seventeen minutes older than the commit it points at.** Two independent reviewers
found this in the same hour, and one evaluated the predicate directly: `--if-stale` reports
**fresh** right now, with HEAD moved well past the last build.

## Why this is T3 and not a tidy-up

`skills/task-context/SKILL.md` step 1 is `kit-index.sh --if-stale`. It is **the** rebuild a session
performs, so anything a session believes about git-derived state can be arbitrarily stale:

- `touches` edges, and therefore `tier_floor`, blast radius, and co-change
- `commits_trailers_recovered`, `finding_fix_commit_missing`
- every count `STATUS.generated.md` reports about commits

It is also load-bearing for a decision **not yet taken**. Both ADR 0005 and ADR 0006 were rejected,
and both rested on evidence being re-derived at rebuild. Under 0006 the entire fail-closed property
was *"removing the marker lapses the exclusion, automatically"* — automatic via a rebuild that this
defect prevents from firing. **No design that re-verifies evidence at index time can work until this
is fixed**, which is why it is filed before 0007 is written rather than inside it.

## The second half: nothing that reads the gate rebuilds at all

Even with the watch fixed, `kit-preflight.sh --criticals` opens the database and queries it — it
never rebuilds. `kit-status.sh` rebuilds only when the database is **absent**. And `.project/index.db`
is gitignored, so the gate's answer is a function of *when someone last ran the indexer*.

`kit-preflight.sh --spend` already does the right thing and says why: it rebuilds first, because
querying the index straight after an agent runs reads whatever the last rebuild contained. The same
reasoning applies one box up and was not carried across.

## Acceptance criteria

- [ ] Staleness compares the **resolved commit** — `git rev-parse HEAD` against a value recorded in
      `meta` — not the mtime of any file. A resolved SHA is what the derivation actually depends on;
      a file mtime is a proxy that has now been wrong in the direction that fails open.
- [ ] It is correct on a **detached HEAD**, during a **rebase**, and in a **worktree**, where
      `.git` may be a file and `refs/` may be shared or absent. Watching `refs/heads/<branch>`
      instead would fail on all three, so it is not the fix.
- [ ] **A packed ref is not missed.** After `git gc`, `refs/heads/main` may not exist as a file at
      all — it lives in `packed-refs`. Any file-based watch has this second hole; `rev-parse` does
      not.
- [ ] The gate decides explicitly: either `kit-preflight.sh --criticals` rebuilds before querying,
      as `--spend` does, or it **refuses on a stale index** rather than reporting a number derived
      from an unknown point in history. Reporting silently is the one option to reject.
- [ ] A check that can fail, in the shape the defect takes: build a fixture, commit a change that
      touches **nothing** in the current watch list, run `--if-stale`, and assert it rebuilt. That
      test fails on today's code. A test that touches a task file as well would pass on the broken
      version and prove nothing.
- [ ] Whatever lands is measured for cost. `--if-stale` exists to avoid a rebuild that costs ~39s
      on this machine, so a fix that rebuilds every time defeats its purpose; `git rev-parse HEAD`
      is one spawn.

## Notes

Found 2026-08-21 by both reviewers in the T3 chain on ADR 0006, independently, at critical severity.
The security review put it plainest: the correct watch target is `git rev-parse HEAD` compared
against a value in `meta`, not a file mtime.

**Pre-existing, and older than anything it now threatens.** It has been wrong since `--if-stale` was
written; it became load-bearing only when a design proposed re-deriving evidence at rebuild. That
ordering is the reason it was never noticed: nothing depended on it being right.
