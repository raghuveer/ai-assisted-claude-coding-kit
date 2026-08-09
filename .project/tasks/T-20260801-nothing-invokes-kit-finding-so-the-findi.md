---
id: T-20260801-nothing-invokes-kit-finding-so-the-findi
title: Nothing invokes kit-finding so the findings loop is open circuit
epic: feedback-loop
tier: T2
state: open
---

## Intent

The README says findings "are recorded with language and defect class, which is the
mechanism by which the accelerators are improved from real work rather than invented."

On a real project that had run a T2 implementation review and a T3 design review, the
finding table held ZERO rows. Both reviewers had emitted correctly formatted
`Findings (recordable)` blocks. Nothing consumed them.

The agent files say the lines "are piped straight into `kit-finding.sh --batch`" -- but
nothing does the piping. No hook, no skill step, no script. It happens only if the
orchestrating session does it by hand, which means it happens when someone remembers,
which is the failure mode the checkpoint hook exists to avoid.

Consequence: every escape-rate and accelerator claim in the README is computed from an
empty table. `T0 0/2, T1 0/5, T2 0/7, T3 0/13` reads as "nothing escaped" and actually
means "nothing was recorded."

19 rows appeared the moment the blocks were piped in manually.

## Acceptance criteria

- [ ] findings reach the table without the operator remembering
- [ ] a review that produces findings and records none is visible as a warning, the way
      trailer discipline already is
- [ ] rejected findings are surfaced at the point of rejection, not discovered later by
      querying

## First T3 review: REVISE + REJECT, 15 findings, and the hook is disabled

Both reviewers rejected. Everything below was reproduced against the shipped script, not argued.
**`hooks/hooks.json` no longer invokes the harvester** — the wiring is removed until this is
fixed, because the worst failure is permanent: malformed lines appended to an append-only,
committed `events.ndjson`.

**critical — the gap cannot see what the harvester drops.** `EMITTED` counts lines that survived
the harvester's own regex, not lines the reviewer wrote. The harvester is STRICTER than the
recorder it feeds: `kit-finding.sh` accepts `fail-open | major | bash | |` (it strips spaces per
field) and loudly rejects `Major`, while the harvester silently discards both before counting.
Reproduced: 5 findings emitted, 3 recorded, 2 lost, **zero** `finding-gap` events. That is the
original defect one layer up — the measurement reads clean while findings were lost.

**major — it is `task_known()` for the third time, and twice in one file.** `agent_id` from the
hook payload is interpolated into a `grep` pattern (`:81-82`) and into a `find -name` glob
(`:75`). Reproduced: agent `A.9` suppressed agent `AB9`'s findings; `agent_id` of `*` harvested a
DIFFERENT agent's transcript and filed its findings under `*`. I filed
`T-20260809-a-task-id-containing-a-regex-metacharact` this morning, whose acceptance criteria
say "check the same shape elsewhere before closing", and then wrote the same shape twice this
afternoon.

**major — retracted draft findings are recorded.** Every occurrence of the heading re-arms the
harvest, so a reviewer that drafts a block, retracts it in prose and emits a final block gets all
of them. Reproduced: 3 rows for 1 intended finding, including a `race|critical` the reviewer
explicitly withdrew and a severity it had downgraded. Severity distribution is what escape rate
and the accelerators are read from.

**major — findings bind to unrelated REAL tasks.** The existence test inside the selected row
stops binding to a phantom; it does nothing about an unrelated real task committing first.
Reproduced: a T3 review's `fail-open|critical` bound to an unrelated **T0** task, counted at T0's
tier, unattributed count 0, nothing in the report. The commit claim "reports what it cannot bind
rather than guessing" is true only for the phantom case.

**major — the transcript's JSON envelope leaks into the log.** The last line of a block picks up
the trailing `"}]}}`, and `kit-finding.sh` interpolates every field into the event JSON without
escaping — `esc()` exists in the harvester and is applied only to the gap event. The result is a
malformed line, permanent in an append-only log, and a silently truncated `pattern`, which is the
column the technology accelerator is derived from. Four-field findings hit this; five-field ones
escape only because the garbage lands in `domain` and is dropped by luck.

**major — a reviewer that emits no block is invisible.** Hook exits 0 and writes nothing, so a
review that recorded nothing is indistinguishable from a clean one. `agent_type` is in the
payload and already read, so this is distinguishable and is not distinguished.

**minor — rejected findings' CONTENT is destroyed.** `kit-finding.sh` exits non-zero on rejection
on the stated ground that the caller still holds them; on the hook path the caller is a script
that then exits, the status is swallowed by command substitution, and the gap event carries only
counts. Also `\n`-unescaping corrupts any field containing a literal backslash, and there is no
Stop-hook sweep for a reviewer that dies before SubagentStop.

## The approach, and why each piece is shaped that way

Six principles, because patching seven symptoms would leave the eighth.

1. **One owner for validation.** The harvester stops deciding what a finding looks like. It
   extracts every non-empty line between the heading and the next heading and hands all of them
   to `kit-finding.sh`, which already owns the vocabulary and already reports per line. This
   deletes the stricter-than-the-recorder class permanently rather than aligning two regexes that
   will drift again — the vocabulary drifted across four files once already.
2. **Never interpolate an untrusted field into a pattern.** `agent_id` is compared as a fixed
   string, and the transcript is located with a direct path test rather than `find -name`. A
   charset check on `agent_id` before it is used in a path at all, so a traversal or glob cannot
   be expressed.
3. **Parse the transcript as data, not as text.** Extract the JSON string value and decode its
   escapes explicitly, rather than `sed`-unescaping a whole line and hoping the envelope is not
   caught. This is what kills both the `"}]}}` leak and the backslash corruption.
4. **Escape at the writer.** `kit-finding.sh` escapes every field it interpolates into the event
   JSON. `events.ndjson` must stay parseable line by line no matter what a reviewer emits.
5. **Absence is a measurement.** A reviewer that emits nothing, or whose findings are all
   rejected, emits `finding-gap` carrying the rejected lines themselves — not counts alone, which
   cannot be acted on once the reviewer is gone.
6. **Do not guess attribution.** Bound the forward search so a finding cannot bind to a task
   whose transition is arbitrarily far away or in another session; what falls outside the bound is
   reported as unattributed, which is already a supported and visible state.

**Only the last block is harvested**, on the same reasoning as 5: a superseded draft is not a
finding, and "last message wins" is the only rule that matches how a reviewer actually works.

## Notes

Interacts with [[T-20260801-reviewer-agents-cannot-run-the-tools-the]]: even once
something does the piping, roughly half the emitted findings are currently rejected for
unknown classes, so fixing the plumbing alone would record a biased sample.

The checkpoint hook is the obvious home, but it fires per work unit and reviews happen
mid-unit, so the findings would need somewhere to accumulate first.
