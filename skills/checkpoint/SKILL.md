---
name: checkpoint
description: End-of-work-unit ritual. Use when a unit of work is finished, before clearing context, or when the operator says checkpoint, wrap up, or commit this. Verifies the change at the right level, records findings, and ends the session lean.
---

# Checkpoint

The conversation is a scratchpad. It compacts, and it is lost on restart. Every durable
fact belongs in a file before this unit ends.

**What this skill does NOT do.** Status reconciliation, status-file regeneration, and event
recording are mechanical and now run without you: `kit-index.sh` rebuilds state from task
files and commit trailers, `kit-status.sh` regenerates the status view, and the `Stop` hook
appends the checkpoint event. Do not hand-write any of it. A derived field you edit by hand
re-creates the second source of truth the derivation removed.

What is left is the part that needs judgment.

## 1. Summarize the unit

Files touched, decisions made, anything left mid-flight. Name what you left undone —
a decision the operator interrupted is a checkpoint *output*, not a loose end to drop.

## 2. Verify at the level the failure lives

Run the affected component's test command from `commands.test` in the project profile. If a
runtime flow changed, drive it. Report actual results; never mark done on "should work".

If no product source changed, **say so** rather than implying a suite was re-run. Verify what
you did change with the tool that fits: syntax check and an actual `--help` run for a shell
script, an import check for a module, a config validator for config, a strict build for docs,
a migration-head check for a migration chain.

**Mutation-test the wiring, not the parser.** Revert each new guard or call site individually
and confirm a test goes red. A surviving mutant is a finding, not a formality. Where this
stack has no mutation tooling, `ladder.rung3` in the profile is empty — that means the rung is
*declared unavailable and the tier rises*, so read adversarially instead. It does not mean skip.

## 3. Record findings

Every finding from this unit's reviews:

```
kit-finding.sh --task <id> --agent <name> --class <class> --severity <sev> --summary "<one line>" [--lang <l>] [--pattern <p>] [--domain <d>]
```

A review produces several at once, and a reviewer now returns **one JSON object** rather than a
prose block. Pipe that object in **unchanged** — do not read it and retype the fields, which is
how `pattern` was dropped from twelve rows on 2026-08-10 and seven of them became
indistinguishable from each other:

```
kit-finding.sh --task <id> --agent <name> --json    < the reviewer's whole reply
```

Run `kit-finding.sh --contract` for the field list. Rejection is all-or-nothing and the
diagnostics name every problem at once, so a rejected review is fixed in one pass, not six.

`pattern` names the reusable DESIGN a finding is about -- `cache-port`, `retry-budget` --
independent of language and of industry. It is the axis with the best amortisation: a
design reviewed once and recorded here is not re-derived in the next project. `domain` is
an industry and is dropped unless the profile declared it.

`kit-finding.sh --vocab` prints the accepted classes and severities. Print them; do not
recall them. Every value is validated and an unknown one is rejected, not stored.

`class` and `lang` are not optional detail — they are the mechanism by which the technology
and industry accelerators are later derived from real work rather than invented. A finding
recorded without them is a finding that teaches nothing.

If a review call was later shown wrong, or right, say so:
`kit-vindicate.sh --task <id> --class <class> --real|--false`. Unvindicated findings promote
on raw counts, which launders reviewer noise into shared accelerators.

Whether a finding has been ADDRESSED is a different question again, and `kit-vindicate` does not
answer it. It is recorded with `kit-resolve.sh --finding <id> --fixed [--commit <sha>]`, and
`kit-resolve.sh --list --severity critical --unfixed` prints the ids. An unmarked finding counts
as outstanding, so a gate on open criticals — the trial protocol's first pre-flight box among
them — reads the backlog as blocked until the fixes are recorded.

**If you are an agent reading this: list the ids and PROPOSE the marks in your summary. Do not
run `--fixed` on findings against your own work.** Marking clears the gate that gates you, and a
session certifying its own output is the one signature that carries no information. Nothing
mechanically stops you; this is a convention the operator enforces, like `Via:`.

> Why this is spelled out: the first version of this paragraph simply told the reader to mark
> findings fixed, in a file only the agent reads. That is the wrong-addressee defect the
> provenance work found twice and split both CLAUDE files to prevent — repeated here by the
> same hand that fixed it there. An approach reviewer found it.

**For the operator:** you run `--fixed`, after deciding the fix is real. `--commit` must name a
commit that resolves, and a mark whose commit later leaves the history is reported by
`kit-index.sh`. `--open` retracts a mark. A revert is NOT detected — the commit still exists, so
the mark still reads as addressed.

## 4. Decision-record check

If a real decision was made, write or amend the record via `adr-scribe`. Records are
append-only: a Status field plus a banner is the only sanctioned edit to an existing one.
When superseding, scope it precisely — if a record decided two separable things and only one
died, mark it *partially* superseded and say which half still stands.

## 5. Commit

Stage the intended paths and commit on the current branch, with trailers:

```
Task-Id: <id>
Task-Status: done | progress | blocked
Tier: T0..T3
```

The `commit-msg` hook validates these. Recording status is a side effect of the commit you
were making anyway — that is why it stays current.

- **Push only with authorization.** Default is local-only. An explicit "push it" covers that
  unit and does not carry to the next.
- **Check every repository**, not just the one worked in. List each one's branch and
  ahead/behind state. A repo you forgot is a repo that silently diverges.
- **Never commit secrets.** Scan operator-authored prose for credential patterns before
  staging, and report hits rather than committing quietly.
- `git rm <path>` followed by `git add <same path>` aborts the whole `add` on the pathspec.
  Stage deletions and edits separately, or the commit silently carries half the change.

## 6. End lean

At a unit boundary, clear. The next unit rebuilds from files, and the reload is a cache read
rather than a fresh write, so clearing is close to free. Mid-unit, compact instead.

Do not carry more than one unit forward. A long window re-reads its growing context every
turn, and that read tends to dominate spend — this is the largest lever available and it is
quality-neutral: same agents, same review depth.
