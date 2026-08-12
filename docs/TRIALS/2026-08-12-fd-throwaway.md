# Trial: sharkdp/fd — 2026-08-12 (throwaway)

> Deliberately small and disposable. Run after three review rounds on
> `docs/TRIAL-PROTOCOL.md` produced 20 then 24 findings, on the reasoning that a real execution
> would tell us what matters faster than a fourth round. It did.

| | |
|---|---|
| Question | Do the brownfield degradations actually bite, and is the protocol executable? |
| Kit SHA | `af88dcb` |
| Time-box / actual | 1h / ~25min |
| Subject | `sharkdp/fd` — Rust, 2005 commits, 2017-05→2026-08, `rs`/`md`/`yml`/`toml`/`sh` |
| Greenfield / brownfield | **brownfield**, full history, not truncated |
| Outcome | **COMPLETE** |
| Baseline before the kit | `cargo check` **passes, 33s**. Tests not run (time-box) |
| Instruments verified live | **NO** — see finding T-2. Spend was never captured |
| Copy isolation verified | **YES** — `git remote -v` printed nothing |

## Cost

**Not measured, n=0.** No agents were run: this trial exercised the kit's *machinery* against a
real repository, not its agents. Every figure below is a count from the index, not a cost.

The BTE apparatus was therefore never exercised, and that is the single biggest gap in this
trial. See "Not exercised".

## Which brownfield degradations bit

**1. Over-tiering from an empty edge table — CONFIRMED, and worse than stated.**
`edge` is **completely empty** and `task` has **0 rows**. No `Task-Id` trailers in 9 years of
history means no `touches` edges, so blast radius is unknown for every file. Expected.

*Not previously stated:* the shipped profile template contains **zero `tier.rule` lines**, so a
freshly adopted brownfield repo has **no tier floors at all** — every task falls to
`tier.default`. The degradation is not merely that floors meet existing paths awkwardly; there
are no floors to meet them.

**2. Co-change — DID NOT DEGRADE. It is the headline result.**

| | |
|---|---|
| rows / pairs | 1444 / 722 |
| files | 97 |
| avg degree | 14.9 (threshold `cochange.max_degree: 50` — correctly **not** withheld) |
| commits used | 1576 |

Qualitatively good. For `src/main.rs`:

    src/walk.rs      84
    tests/tests.rs   75
    src/app.rs       66
    src/output.rs    39
    src/internal.rs  32
    CHANGELOG.md     30

Those are the files a developer changing `main.rs` would need, ranked plausibly, with one
honest piece of noise (`CHANGELOG.md`). **On the kit's own repository this graph is inert; on a
real 9-year Rust project it is the only working blast-radius signal.** This is the first
evidence that co-change earns its place, and it arrived in six seconds of indexing.

**3. Planner on a backlog it did not author — CONFIRMED, and total.**
`kit-plan.sh --next 5` returns **nothing at all**. With 0 tasks there is nothing to order. So
brownfield adoption yields a useful co-change graph and **no plan whatsoever** until a human
builds a task inventory. The adoption path's real first step is inventory, not planning.

**4. Trailer discipline reports honestly.** *"1420 of 1420 non-trivial commits carry no
`Task-Id` (53 trivial excluded)."* 100%, stated plainly, no false comfort.

## Findings

### Kit defects (to be filed)

**T-1 · major · `§0` of the protocol is uncomputable.** The pre-flight requires "no task at
`progress` carrying an unfixed critical". The `finding` table has no column expressing *fixed* —
`vindicated` means real-vs-false-positive, not addressed. On the kit's own repo the query
returns **16 criticals**, including ones fixed hours earlier. **The gate blocks forever or is
ignored.** It was ignored here, deliberately and recorded, because CI was green and the tree
clean.

**T-2 · major · `§0`'s spend pre-flight cannot pass, exactly as the re-review predicted.**
Confirmed in the field: spend was never captured, and the trial produced no cost data at all.
The re-review found this by reading; the trial confirms the consequence — **the entire cost half
of a trial is silently absent.**

**T-3 · minor · the empty-spend notice is wrong in this case, as the re-review said.** It reads
*"almost always means the kit's hooks were not active"* — true here, but this is also a fresh
adoption where no work has happened yet, so the wording asserts a cause it cannot know. The
re-review's minor finding is confirmed by execution.

**T-4 · minor · `kit-init.sh` leaves a footprint with no removal step.** In the copy:
`M .gitignore`, `?? .claude/`, `?? .gitattributes`. Nothing in the protocol says to strip these
before delivering a proposal to the subject's owner.

**T-5 · minor · 104 commits are unaccounted for.** `git rev-list --count --no-merges` is 1577;
the trailer report accounts for 1473 (1420 non-trivial + 53 trivial). The gap is unexplained and
nothing reports it. Not necessarily a defect — but a number that does not add up and says
nothing about itself is the shape this kit exists to refuse.

### Subject defects

**None sought.** No agent reviewed `fd`; this trial exercised machinery only.

### Methodology

**The protocol's §4 clone path WORKS.** `git clone --no-hardlinks` → `git remote remove origin`
→ `git remote -v` printed nothing. The one control that was rewritten after the first review
held up in the field.

**§0's ordering is wrong.** It names "the copy" in the instruments block *before* the block that
creates it. Executing top-to-bottom, the instrument checks have nothing to run against.

**A time-box of 1h was generous.** The machinery half took ~25 minutes including a 33s baseline
and 6s of indexing. The expensive half — agents — was not reached.

## Not exercised

- **Every agent.** No `coder`, no reviewer, no `tier-classify`. The whole quality claim is
  untested here.
- **Cost measurement.** Follows from T-2.
- **Task inventory from an existing roadmap** — `fd` has no roadmap document, so the input the
  adoption path is designed to consume was absent. A subject with one is needed.
- **Accelerators**, **polyglot binding** (fd is Rust-dominant, not genuinely polyglot),
  **`ingest.tasks`**.
- **Tests** — only `cargo check`, not `cargo test`.

## Disputed

None. No findings were delivered to the subject's owner.

## What this trial changes

Three review rounds argued about the protocol. **Twenty-five minutes of execution produced two
major kit defects neither round found** (T-1, T-5), confirmed two the last round predicted
(T-2, T-3), and delivered the first positive evidence for co-change on brownfield.

The protocol's remaining defects are best fixed **by executing it again**, not by reviewing it a
fourth time.
