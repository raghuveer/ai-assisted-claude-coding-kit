---
id: T-20260812-a-finding-cannot-be-marked-fixed-so-any-
title: A finding cannot be marked fixed so any gate on open criticals is uncomputable
epic: measurement
tier: T3
lang: sql
paths: tooling/schema.sql, tooling/kit-vindicate.sh, tooling/kit-status.sh
state: open
---

## Intent

The `finding` table records what a review found. It has **no column expressing whether the
finding was addressed**. Columns are `id task_id agent model tier lang class domain pattern
severity at vindicated summary file_path line_no`, and `vindicated` answers a different
question — *was this real or a false positive* — set by `kit-vindicate.sh --real|--false`.

So **"is there an open critical on this task" cannot be computed**, and anything gating on it
either blocks forever or gets ignored.

Found by executing `docs/TRIAL-PROTOCOL.md` on 2026-08-12. Its §0 pre-flight requires "no task
at `progress` carrying an unfixed critical". Run against this repository:

    SELECT COUNT(*) FROM finding f JOIN task t ON t.id=f.task_id
     WHERE f.severity='critical' AND t.state='progress';   -- 16

Sixteen — including findings fixed hours earlier the same day, such as *"file pattern lang and
domain are interpolated into the event"*, whose fix landed in `d907522`. The gate was overridden
to let the trial proceed, which is the honest outcome and also proof the gate is decorative.

**Three review rounds on that protocol did not find this. Running the first checkbox did.**

## Why it matters beyond the protocol

- The escape-rate story assumes findings accumulate as evidence. A table that cannot distinguish
  *outstanding* from *addressed* can count findings but cannot report **risk**.
- Any future gate — CI, a close check, the claim audit — hits the same wall.
- It interacts with `vindicated`: a finding can be real **and** fixed, real and open, false and
  irrelevant. One column cannot carry two orthogonal facts and currently is not asked to, so the
  second fact is simply absent.

## The change

Add the missing axis. The shape is a decision, not a detail, and belongs to whoever takes this:

- **A column** (`fixed_at`, or a `state` with a closed vocabulary) set by a command in the same
  family as `kit-vindicate.sh`; or
- **an event**, `finding-fixed`, keyed to the finding, which fits the kit's derive-from-events
  grain better and survives a rebuild.

The second is more in keeping with the rest of the design — `finding` rows are already derived
from `finding` events — but it needs a stable finding identity to key on, and today `id` is
`at:n`, a positional counter that **changes when events are re-read**. That is the real work
here, and it is why this is not a one-line fix.

## Acceptance criteria

- [x] A finding can be marked addressed, by a command, without editing derived state.
      `kit-resolve.sh --finding ID --fixed|--open` appends a `finding-fixed` event.
- [ ] "Open criticals on task X" is a query that returns 0 on this repository today, because
      every recorded critical has in fact been fixed. If it does not return 0, either the data
      or the claim is wrong and the discrepancy is the finding.
      **IT DOES NOT RETURN 0, AND THE CLAIM WAS WRONG. See "What the gate says" below.**
- [x] The mark survives `kit-index.sh` rebuilding from scratch — asserted, since findings are
      derived and a mark stored only in the database would vanish.
- [x] Marking a finding addressed is distinct from vindicating it. A fixture proves all four
      combinations are representable. **Un-ticked by the T3 round and re-earned:** the fixture
      exercised `--real` only, so `vindicated=0` appeared nowhere and the fourth state was
      asserted by the tick alone. It now vindicates a class `--false` and marks one of those
      findings fixed, so *false and fixed* — a reviewer was wrong and the code changed anyway —
      is constructed rather than claimed.
- [x] `docs/TRIAL-PROTOCOL.md` §0's gate becomes computable, or is deleted. **A gate nobody can
      evaluate is worse than no gate**, because it launders "we ignored it" into "we checked".

## Identity had to come first, and the instability was worse than filed (2026-08-13)

The task said the id "changes when events are re-read". Measured rather than assumed:
appending ONE event dated earlier than the rest — the case `.gitattributes` `merge=union`
makes routine — **renumbered all 219 findings**, every id shifted by one. So a mark keyed on
`at:n` does not fail to resolve. It silently reattaches to the NEIGHBOURING finding, which is
worse than no mark at all.

The id is now `<at>:<FNV-1a 32 of the event line>`. The line is append-only, so the id is
stable for exactly as long as the event is, and it is a function of content rather than of
position.

**A third option was available and is not in this write-up, which costed content-hashing only
against `at:n`.** A WRITER-ASSIGNED id — a uuid emitted by `kit_findings.py` at record time —
is stable by construction, needs no hash, and cannot collide. It was rejected because the 219
findings already in the log carry no such field, so every one of them would need a derived id
anyway and the repository would run two identity schemes at once; and because an id that is not
a function of the line cannot be recomputed if the field is ever lost. Content-hashing is one
rule for old and new rows alike. That is the argument, and it was missing. Byte-identical lines take an occurrence suffix instead of collapsing: two
pre-contract findings on one task in one second serialise alike, and dropping one silently is
the failure mode this repository exists to refuse. A true hash collision — two different lines,
one id — keeps both rows and is announced on stderr.

Seven mutations, all killed. One SURVIVED first and is the lesson worth keeping: the hash
check pasted the algorithm into the test and compared it against the published FNV-1a vectors,
which proves an algorithm correct **without proving it is the one in use** — breaking the
multiply inside `kit-index.sh` left it green. Replaced with a golden id asserted end to end
through the indexer, which also pins the value across CI platforms.

## What the gate says (2026-08-13)

Computable now, and the answer is not zero. **18 unfixed criticals became 11**, verified one at
a time against the current tree rather than against memory:

- **7 marked fixed**, each with the commit that did it — the four one-writer criticals
  (`d907522`), the empty-prompt false-clean (`dcd78e6`), and the two trial-protocol revision-1
  criticals (`436df35`).
- **2 are genuinely still open**, and re-reading them confirmed the finding rather than
  retiring it: `§0` still permits "**A COPY** or a clone with its remote removed" while `§4`'s
  remote-removal control covers only the clone path, and `§0`'s spend check still reads
  `.project/index.db`, which a live hook does not populate until `kit-index.sh` runs.
- **9 cannot be assessed at all.** They predate the `summary` column and carry only
  `class|severity|task`. Nobody can say what "it" was, so nobody can say it was fixed, and
  marking them would be precisely the laundering this task exists to stop. They stay
  OUTSTANDING and the pre-flight gate stays red on their tasks. **This is a real cost of the
  bare-counter era and it should be filed, not absorbed here.**

## T3 review round (2026-08-13): REJECT, 10 findings, 1 critical — all fixed

Two blind reviewers in separate processes, read-only enforced, both recorded through
`kit-review-record.sh` on the first attempt with no human in the path.

**The critical was in the control written against this exact failure.** `kit-status.sh`'s
Outstanding criticals section could not tell a FAILED query from an EMPTY result: `q()` discards
stderr and yields `""`, so against an index built before `fixed_at` existed — which the
readability check at the top of that file passes, because `task` is intact — the gate read
clean. Reproducing it found something worse than reported: the "none outstanding" branch could
never print **in any case**, because its format string began with `-` and bash `printf` parses
that as an option. The line had never once run. LESSONS §1 inside a control written against §1.
Now three distinct outputs — unreadable, none, some — with the exit status read and `--` ending
option parsing.

**Both reviewers independently found the false AC** about the four combinations. See above.

The rest, all fixed and each mutation-proved:

- `--list` exited 0 on a failed query, so a broken listing read as "no findings". It now fails
  loudly and says explicitly when a result is genuinely empty.
- Orphaned and ambiguous marks were announced on stderr only — unread from a hook, from CI, or
  from inside `kit-status.sh`. Counted into `meta` and reported in the status file.
- **A collision made a mark inheritable.** The occurrence suffix is assigned by stream position,
  so a different line hashing alike could take the first slot and push the original to `:2` —
  and the original's mark, keyed on the unsuffixed id, would land on the newcomer. Marks on any
  id at a collided base are now REFUSED and counted. Proving it needed a real collision: two
  distinct lines sharing one `at` and one FNV-1a 32 value, brute-forced in 1.7M tries and
  hard-coded into the fixture, because a control that cannot run is not a control.
- Whole-second timestamps sorted AFTER sub-second ones in the same second (`.` < `Z`), which is
  backwards — a whole second denotes its start. The sort key is normalised; the payload is not.
  `--at` is validated, being the ordering key rather than a label.
- The fixture used one task, so anything task-scoping the indexer's per-finding arrays was
  invisible. It now uses two.
- The existence probe CREATED the database it was checking for (`sqlite3 <path> <query>` does),
  leaving a stray empty index a later `kit-status.sh` reads as a repository with no tasks.
- `--note` was sanitised, recorded, and read by nothing. It has a column and `--list` shows it.

**Not fixed, filed instead:** `kit-review-record.sh` builds each reply in a `mktemp -d` with a
cleanup trap and records only the `findings` array, so the reviewer's `verdict` and `narrative`
are destroyed. The reasoning behind every finding above now exists nowhere.

## Unmet at closure — stated, not left blank

An unticked box on a closed task cannot be told from a forgotten one, so the one criterion that
is NOT met is named here rather than left as an empty checkbox someone has to interpret.

**AC2 — "open criticals on task X returns 0 on this repository today" — IS NOT MET, deliberately.**
It returns 11. Seven were marked fixed against the commit that did each; two were re-read and
confirmed genuinely open; nine cannot be assessed at all because they predate the `summary`
column, and are filed as `T-20260813-nine-criticals-predate-summary-and-canno`. The criterion
itself anticipated this: it said that if the query did not return 0, either the data or the
claim was wrong and the discrepancy was the finding. The claim was wrong. Forcing the number to
zero by marking findings nobody can read would be the laundering this whole task exists to stop.

## T3 approach round (2026-08-14): 10 findings, 4 major

Run after two implementation rounds had converged, on the argument that convergence in one
dimension says nothing about the others. It found four majors neither implementation round
raised, because none of them is a line-level defect:

- **The gate was bypassable by closing the task.** §0 filtered `t.state='progress'`, so a
  critical on a done task did not count — "fix it" and "close it" cleared the pre-flight
  equally, and two of this repository's own outstanding criticals were invisible to it. The
  gate no longer filters by task state, and criticals on closed tasks are named separately.
- **`--commit` was never validated**, so a mark with no evidence and a mark citing a SHA that
  never existed were the same row. It must now resolve, and is stored in full.
- **Nothing reacted to a fix commit leaving the history.** Checked on rebuild and reported. A
  REVERT is still not detected and the limitation is written down rather than implied.
- **No authority model, in the worst possible place.** The instruction to mark findings fixed
  was written into `skills/checkpoint/SKILL.md` — the file the AGENT reads — telling the session
  that wrote the code to clear the gate that gates it. This is the wrong-addressee defect the
  provenance work found twice and split both CLAUDE files to prevent, repeated by the same hand
  that fixed it there. Split by addressee now, in the skill and in `.claude/CLAUDE.md`, and
  stated as convention rather than mechanism because nothing here can enforce it.

The six minors: refuted criticals blocked the gate forever with no honest way to retire them
(now excluded and counted); marks are ordered by local wall clock, which `merge=union` puts two
machines' worth of into one file (documented, not solved — see below); `finding-fixed` events
carried no `task` key so no task timeline showed its findings resolved; the identity write-up
never named the writer-assigned alternative; the nine-criticals task said four tasks when three
was right; and this section exists because of the last one.

**Known and NOT fixed, deliberately:** two marks on one finding from two machines are ordered by
their local clocks, and nothing here can establish a true order between them. A monotonic
counter would collide across branches, and a vector clock is a distributed-systems apparatus
this kit has no other use for. Single-operator use is unaffected; the limit is stated in
`kit-resolve.sh` so it is a known bound rather than a surprise.

## Notes

Filed 2026-08-12 from the first execution of the trial protocol
(`docs/TRIALS/2026-08-12-fd-throwaway.md`, finding T-1). Blocks closing that protocol task
honestly: its §0 cannot be satisfied as written.
