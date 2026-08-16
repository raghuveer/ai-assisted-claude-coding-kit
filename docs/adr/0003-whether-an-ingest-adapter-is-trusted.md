# ADR 0003: Whether an ingest adapter is trusted, and what the profile is

- **Date:** 2026-08-16   **Status:** **Accepted — Option C**   **Supersedes:** —   **Related:** [[0001-anchor-entry-facts-to-files]]

Serves AC1 of `T-20260816-an-in-root-profile-write-gives-an-agent-`, which asks for this decision
to be resolved **explicitly and recorded** rather than patched. The patch half (dot-commands) is
already done and is not what this ADR is about.

## Context

`kit-index.sh` runs an external ingester named in the project profile:

```sh
_out=$(KIT_ROOT=… bash "$_ap" "$2" 2>/dev/null)      # tooling/kit-index.sh
```

`_ap` comes from `ingest.tasks` / `ingest.events` / `ingest.extra` in
`.claude/project-profile.md`. That file sits **inside the project root, where `kit-guard.sh`
permits every write by design**. So an agent holding `Write` can author an adapter and a profile
line in one turn and get code execution on the next index — and `kit-index.sh --if-stale` is step
1 of the `task-context` skill, so "the next index" is ordinary use rather than a contrived
trigger. Demonstrated 2026-08-16 and **re-verified at `e0b9f28`**, where it still executes.

**The kit currently answers this question twice, in opposite directions.** `SECURITY.md` §1
classifies *ingest adapter output* as **not trusted**. `run_adapter`'s own comment said an adapter
is *trusted code named in a committed, reviewed profile*. Both cannot hold. That comment no longer
answers it — it now names the question and points here.

The trust table also understates the behaviour: the kit does not merely *read* what the adapter
prints, it **executes** it — once as a process, and again as input to the `sqlite3` CLI.

### The distinction that shapes this decision

Raised by the operator, and it is the right frame:

- **WHICH adapter a project uses is a per-project decision** — by the solution architect and lead
  developer, declared in the profile and referenced from the solution overlay. `docs/ADAPTERS.md`
  exists precisely so a project can swap a source (GitHub issues, a REST API, a CSV) without
  touching the indexer. **This should not become kit-level policy.**
- **WHETHER the kit can be made to run something nobody chose is a kit-level property.** Leaving
  that to per-project judgement files it alongside reviewer read-only, `Via: kit` and fix-marks —
  three properties this repository assumed were mechanical and found were not.

So: **the choice is the project's; the integrity of the choice is the kit's.**

### What any option here can and cannot buy — read before choosing

Stated first because it bounds every option and is easy to overclaim.

**`coder` and `tester` hold `Bash`.** For them the adapter path adds *nothing* — they can already
run anything, and `SECURITY.md` §4 concedes there is no sandbox. §3 further concedes that tool
grants are not known to bind at all, so no agent can be assumed not to hold `Bash`.

**Therefore no option below defends against a determined actor inside the session.** What they
differ on is whether the kit *states its own posture consistently*, and whether a **confused**
agent — one writing a plausible-looking `ingest.extra` value, or copying a profile between
projects — silently acquires execution. That is a smaller claim than "we closed an RCE", and this
ADR should not be read as making the larger one.

## Options

### Option A — adapters are trusted; the profile is a privileged input

Accept that an adapter emits SQL and is inherently powerful, and move the protection to the
**declaration** rather than the execution.

- `SECURITY.md` §1 gains a row: the project profile is a privileged input, not merely "partly"
  trusted for its interpolated values.
- Something must make an agent-authored change to it visible before it runs — at minimum the
  indexer reporting that the adapter declaration changed since the last commit.
- `docs/ADAPTERS.md` states that authoring an adapter is equivalent to authoring code that runs
  with the operator's permissions.

*Cost:* friction when the operator edits their own profile mid-session. *Honest limit:* an agent
holding `Bash` can commit, so "changed since last commit" is a tripwire, not a gate.

### Option B — adapters are untrusted; running an arbitrary named path is the defect

Narrow what the profile may name.

- The profile may only name adapters from a fixed, committed location (e.g. `tooling/adapters/`),
  not an arbitrary path.
- Anything outside that is refused with a named cause rather than executed.

*Cost:* the `ADAPTERS.md` seam narrows — ad-hoc and out-of-tree adapters stop working, and a
project vendoring an adapter must place it where the kit expects. *Benefit:* the refusal is
**structural and checkable**, and it is the only option whose central property a conformance step
can prove without depending on git state.

### Option C — the hybrid this ADR recommends

Keep the per-project choice, make the integrity mechanical, and be explicit about the limit.

1. **The choice stays in the profile and the overlay.** No kit-level allowlist of *which* source a
   project may use.
2. **The path is constrained** (Option B's mechanism): the profile names an adapter relative to a
   committed location. This is the part a test can prove.
3. **`SECURITY.md` §1 is corrected either way** — the row must say the kit *executes* adapter
   output, not that it reads it. That correction is required under every option and should not
   wait for this decision.
4. **The limit is written down**, in `ADAPTERS.md` and `SECURITY.md` §4: this constrains a
   confused agent and a copied profile; it does not constrain an agent holding `Bash`, and
   nothing inside the repository can.

## Decision

**Option C, taken by the operator 2026-08-16 and implemented the same day.**

`run_adapter` now refuses, before executing anything:

1. **A path that is not repo-relative** — absolute, drive-qualified, or containing `..`. It names
   code this repository does not contain, so no review of this project can have seen it.
2. **A file not tracked by git.** This is the part that answers *"does the kit mandate the
   documented choice"*: a declaration an agent invented mid-session names an untracked file and
   does not run. Being tracked means it is in a diff someone can read.

Proved by the conformance step `only a committed, repo-relative adapter runs`, which asserts all
three directions — untracked refused, absolute refused, **and a committed adapter still running**.
The third is not padding: a guard that refused every adapter would satisfy both refusals while
silently deleting the `ADAPTERS.md` seam, which is a worse defect than the one being fixed.
Mutation-proven — making the tracked check unreachable turns the step red.

`SECURITY.md` §1 is corrected: the row now says the kit **executes** the adapter, as a process and
again by feeding stdout to the `sqlite3` CLI, and names the constraint.

### What is enforced, and what is still convention — the answer to "is this only prose"

| Property | How it holds |
|---|---|
| The adapter is repo-relative | **Mechanism.** Refused in `run_adapter`, conformance-proved |
| The adapter file is committed | **Mechanism.** Same |
| The *committed* adapter is the one the project intended | **Convention.** Nothing compares the profile against the overlay or an ADR |
| An agent cannot arrange for its own adapter to run | **Not held.** `git add && git commit` is a `Bash` call and the guard does not match `Bash` |

The third row is the one to build next and it is **not buildable yet**: the solution overlay does
not exist, so there is nothing for the profile to be checked against. When it does, the check is
"the `ingest.*` values match what the overlay declares" — the same overlay↔profile drift already
flagged as a risk. Until then, the documented choice binds by review, not by mechanism.

What must be true of whichever option is chosen:

- The contradiction between `SECURITY.md` §1 and the code is resolved in **one** direction and
  both are made to agree.
- The resulting property is proved by a test that **fails when the fix is reverted** — an adapter
  that `touch`es a marker must not produce it, and the harness must notice if it would.
- The claim made in `SECURITY.md` is bounded by the section above. "No model output is executed"
  was false because an exhaustive search for `eval`, `exec(`, `system(` and `sh -c` was never
  going to find `bash "$_ap"`; its replacement must not overclaim in the other direction.

## Consequences

- **Until this is decided the adapter still executes**, and it remains the open blocker on
  unattended operation. Three of the four safety items are done; this is the fourth.
- `T-20260815-an-ingest-adapter-can-insert-a-task-row-` is the *data* half of the same seam — an
  adapter inserting rows the indexer's invariant forbids. It shares a cause with this and should
  be decided in the same sitting, though the two fail independently.
- Option B or C narrows a documented contract. `docs/ADAPTERS.md` is the file a third-party
  adapter would be written against, so the narrowing must land there before anyone writes one.
