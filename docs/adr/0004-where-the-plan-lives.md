# ADR 0004: Where the plan lives

- **Date:** 2026-08-17   **Status:** **Accepted — Option D**   **Amended:** 2026-08-17   **Supersedes:** —   **Related:** [[0003-whether-an-ingest-adapter-is-trusted]]

> **Amended the same day, after a T3 review chain returned REVISE / REVISE / REJECT on the
> implementation of option C.** The amendments are in place rather than in a successor ADR,
> matching the convention ADR 0001 set. Three things changed and each is marked below:
> **option D is added and chosen** over the C that shipped; the **rejection of option A loses its
> second argument**, which did not discriminate; and the **decision now states what the digest
> does not cover**. The Context section was verified true by that review and is unchanged.

Serves AC2 of `T-20260817-kit-index-deletes-the-plan-so-task-conte`, which requires this to be a
recorded decision rather than a reflex, because three answers are live and they differ in what a
stale plan means.

## Context

`kit-index.sh` rebuilds into a fresh database from `tooling/schema.sql` and moves it into place.
`goal` and `plan_item` are the **only two tables written by a different tool** — `kit-plan.sh` —
and they are **not derivable from any text source**, so every rebuild drops them. The word "plan"
does not appear anywhere in `kit-index.sh`. The `meta` key `plan_withheld:<goal>` goes the same
way, and it is the only record of how many tasks a plan withheld and why.

Measured 2026-08-17 at `1f83fe8`, on a clean tree:

| Action | `plan_item` | `goal` | packs on disk |
|---|---|---|---|
| after `kit-plan.sh` | 77 | 1 | 11 |
| after one plain `kit-index.sh` | **0** | **0** | 11, orphaned |
| `--if-stale`, nothing changed | 77 | 1 | 11 |
| `touch` one task file, then `--if-stale` | **0** | **0** | 11, orphaned |

`skills/task-context/SKILL.md` step 1 is `kit-index.sh --if-stale` and step 4 reads `plan_item`.
Any task edit, event or commit makes the index stale, so **the skill's first step deletes what its
fourth step reads**, during ordinary work. The pack files are left on disk looking current and
nothing warns.

This falsifies `docs/HANDOFF.md` §4.6 — *"The plan is state, not context … survives `/clear`,
session end, or a crash"* — and is the most likely explanation for `docs/MEASUREMENTS.md` §F,
*"13 cluster packs generated, read by nothing"*. Not that nobody followed the skill: that there
was no row left to find.

**The ownership rule already exists and this violates it.** `docs/ADAPTERS.md` tells adapter
authors: *"Do not write to `plan_item` or `goal` — those belong to `kit-plan.sh`."* The indexer
does not write them either. It destroys them, which is the one operation the ownership rule never
contemplated.

## Options

**A — carry the two tables across the rebuild.** Copy `goal`, `plan_item` and the
`plan_withheld:` meta rows out of the old database before the swap and back in after.

Smallest diff, roughly fifteen lines, and no new file format. But it makes `index.db` the sole
home of state that exists nowhere else, and `index.db` is **gitignored and machine-local**: a
fresh clone, a new laptop or a `rm index.db` still loses the plan with nothing announcing it.
That is decisive on its own.

> **Amended — the second argument is withdrawn.** This rejection also said A breaks the invariant
> `kit-task.sh` states in its own header, *"nothing is ever written to the database directly"*.
> **Option C as first implemented broke that invariant identically**: `kit-plan.sh` executed
> generated SQL straight into the live index and then dumped the text file back out of the
> database it had just written. An option cannot be rejected on a rule the chosen option also
> breaks. A reviewer reading the code rather than the ADR caught it, and option D below is the
> shape that makes the invariant literally true.

**B — re-derive the plan during indexing.** Have `kit-index.sh` run the planner.

Removes the persistence question entirely. Rejected on two grounds. Planning is an explicit act
with its own weights and goal — `/goal` computes an ordering **once** — and re-deriving it on
every index would silently reorder live work whenever a task's tier or `blocked_by` changed
mid-session. It would also destroy pack byte-identity, which `kit-plan.sh:305-313` depends on:
the packs are *"written once per plan and byte-identical thereafter"*, and a plan recomputed on
every rebuild has no "thereafter".

**C — the plan is a text file, and the index is derived from it like everything else.**
`kit-plan.sh` writes `.project/plans/<goal>.tsv`; `kit-index.sh` reads it and populates `goal`,
`plan_item` and the withheld count on every rebuild.

Largest diff of the three. It is the only option that makes the documented guarantee true rather
than approximately true: the plan then survives a rebuild, a fresh clone, a deleted index and a
different machine, for the same reason task files do. It also puts the plan under the rule the
rest of the design already follows, so there is one answer to "where does truth live" instead of
two.

**D — one writer. `kit-plan.sh` writes only the text file, then calls `kit-index.sh` to derive
the tables from it, then builds the packs from the derived rows.** *(Added by amendment.)*

Not considered when this ADR was first written, and named by the review that read the shipped
code. C's second Consequence below exists **because C creates the possibility of `kit-plan.sh`'s
writer and `kit-index.sh`'s reader drifting apart**, and answers it with a conformance step that
detects the drift. D deletes the possibility instead of testing for it — which is the standard
this repository applies everywhere else, and the same reasoning ADR 0003 used when it chose the
structurally checkable option. It also makes the `kit-task.sh` invariant literally true, which is
the ground option A was rejected on.

It costs one extra index run per plan. That is real and is the reason it is not obviously right;
it is not enough to prefer a design whose correctness rests on a test.

## Decision

**Option D, amending the option C originally recorded here.** The plan is text, the index is
derived from it, and **only one thing writes each**.

`kit-plan.sh` emits tab-separated rows, assembles `.project/plans/<goal>.tsv`, and then runs
`kit-index.sh`. It no longer writes `goal`, `plan_item` or the `plan_withheld:` meta key at all —
the withheld count travels as a header line and is derived with everything else. Packs are built
last, from the derived rows, so they cache the FILE rather than an ordering that existed only
inside one process.

**`kit-plan.sh --packs` rebuilds the packs from the plan already on disk, without recomputing the
ordering.** This is the half the original option C was missing, and the review's only critical:
the packs are gitignored and the plan is committed, so a fresh clone arrives with plan rows and
no packs — and the only way to get a pack back was to re-run the planner, which recomputes the
ordering and discards the plan that was just cloned. *Recovering the cache destroyed the thing
cached*, which made this ADR's own claim — a pack is a rebuildable cache of the plan — false as
written. Verified after the change: a clone with 83 plan rows and zero packs gets ten packs from
`--packs`, with the plan file byte-identical and its digest unmoved. `kit-status.sh` now reports
plan rows with no packs on disk, so the state is discoverable rather than requiring the flag to be
known in advance.

**What the digest does NOT cover** *(added by amendment; two reviewers raised it independently)*.
`kit_plan_digest` answers *"is this the same backlog the plan was computed from"*, **not** *"is
this still the ordering that backlog produces"*. It covers `id|tier|epic|blocked_by` over open
tasks. It excludes `touches` edges deliberately — they move on every commit, and a warning that
is always on is one people learn to skip. It also excludes `escaped` events and the profile's
`priority.w_*` and `cluster.hub_cap`, all of which feed the score or the clustering and can
reorder a plan that still reports fresh. That is a real residual risk and it is stated here rather
than left to be discovered: retuning `cluster.hub_cap` in response to
`T-20260817-one-shared-file-merges-two-whole-epics-s` would silently renumber every cluster in a
plan that reports itself current, and the cluster number is what step 4 resolves to a file.

The rest of the mechanism is as originally decided:

Concretely:

- `kit-plan.sh` writes `.project/plans/<goal-slug>.tsv` — a `#`-prefixed metadata header (goal,
  creation timestamp, withheld count, and a digest of the task set it was computed from) followed
  by one tab-separated row per plan item: `goal_id, task_id, layer, rank, score, cluster`.
- `kit-index.sh` gains section 3c, which reads those files and emits the `goal`, `plan_item` and
  `plan_withheld:` rows. It runs after the task and event sources and before derivation.
- The creation timestamp moves **into the file**. It was `strftime('now')` inside the emitted SQL,
  which would have re-stamped the goal on every rebuild and made "delete the index, rebuild,
  compare" false for a reason unrelated to the plan.
- `.project/plans/` is **tracked in git**, not gitignored. Packs are a rebuildable cache of the
  plan and stay ignored; the plan is the decision they are cached from. `.project/events.ndjson`
  is tracked for the same reason.

  > **Amended.** That sentence was the load-bearing justification for committing one artefact and
  > ignoring the other, and **it was false when written** — nothing rebuilt a pack from a plan
  > file. It is true now, and only because `--packs` exists. If that flag is ever removed, this
  > bullet stops being an argument and the ignore decision has to be re-made.

**The plan can now go stale, and that is the cost of this option.** Under the old behaviour a plan
never outlived its inputs because it never outlived anything. Carried forward, it can describe
tasks that have since closed, split or changed tier. So the header records a digest of the open
task set at plan time, the indexer recomputes it and stores `plan_stale:<goal>`, and
`kit-status.sh` reports a stale plan rather than serving it silently. **A carried-forward plan
that cannot say it is stale would be a worse defect than the one being fixed** — it would replace
a plan that visibly vanished with one that is confidently wrong, which is the same trade
`T-20260808-cluster-packs-are-generated-and-read-by-` AC4 refuses for packs.

## Consequences

- `docs/HANDOFF.md` §4.6 becomes true and is left standing. Until this lands it is a published
  guarantee the code does not keep.
- A conformance step asserts the round trip: plan, reindex, and the rows are identical — not
  merely present. Identity is what catches `kit-plan.sh`'s writer and `kit-index.sh`'s reader
  drifting apart, which is the failure this option introduces the possibility of.
- A second conformance step derives its expectation from the authority instead of restating it:
  every table in `schema.sql` must either be populated by `kit-index.sh` or restored from text.
  A seventh table added later is covered without anyone remembering to edit the test.
- `kit-status.sh` reports pack directories with no plan rows, so an orphaned pack cannot outlive
  its plan silently again.
- The plan is now shared through git, which is a behaviour change for a team: two people planning
  the same goal will conflict in `.project/plans/default.tsv`. That is a visible merge conflict
  over an ordering decision, which is the correct place for that disagreement to surface. It was
  previously invisible because neither person's plan survived their own next session.

  > **Amended 2026-08-20 — merge conflicts are not the whole team cost**, and a review said so
  > before this shipped. Two more follow from the plan being a tracked file, and both are
  > everyday rather than occasional:
  >
  > **Every replan dirties a tracked file**, so it needs a commit — and under
  > `git.trailer_enforcement: enforce` that commit needs `Task-Id:` and `Tier:` trailers unless
  > it matches `git.trivial_pattern`. Re-running the planner is no longer free.
  >
  > **In an active team the stale notice will be on more often than off.** Any merged task add
  > or close moves the digest, so `plan_stale` fires until someone replans. That is the
  > always-on warning `kit_plan_digest`'s own comment cites `MEASUREMENTS.md` §B.6 to avoid,
  > arriving through a channel that comment did not consider. It is accepted here rather than
  > designed away — the alternative is a plan that goes stale silently — but if it fires on most
  > sessions in practice, the digest granularity is wrong and that is the signal to re-cut it.
- **Not addressed here:** whether the ordering itself is any good.
  `T-20260817-one-shared-file-merges-two-whole-epics-s` records that 61 of 77 open tasks currently
  land in one cluster. Persisting a degenerate plan faithfully is still persisting a degenerate
  plan, and this ADR fixes only where it lives.
