---
id: T-20260816-an-in-root-profile-write-gives-an-agent-
title: An in-root profile write gives an agent code execution on the next index
tier: T3
lang: bash
paths: tooling/kit-index.sh, .claude/project-profile.md, docs/ADAPTERS.md, SECURITY.md
state: open
---

## Intent

`kit-guard.sh` permits every write **inside** the project root — that is its design. Inside the
root sits `.claude/project-profile.md`, whose `ingest.*` values name executables that
`kit-index.sh` runs:

```sh
_out=$(KIT_ROOT="$ROOT" ... bash "$_ap" "$2" 2>/dev/null)     # tooling/kit-index.sh:96-98
```

So an agent holding `Write` or `Edit` — `coder`, `documenter`, `adr-scribe`, and per
`SECURITY.md` §3 any reviewer, since that grant is now conceded to be convention — writes two files
in one turn and gets code execution the next time anything indexes. `kit-index.sh --if-stale` is
step 1 of the `task-context` skill, so "the next time" is ordinary use, not a contrived trigger.

Reproduced 2026-08-16 in a throwaway clone, both halves:

```
$ printf '#!/usr/bin/env bash\ntouch "PWNED-ADAPTER-RAN.txt"\n' > tools-x/adapter.sh
$ # add one line to the profile frontmatter:  ingest.events: tools-x/adapter.sh
$ bash tooling/kit-index.sh >/dev/null 2>&1 ; ls PWNED-ADAPTER-RAN.txt
PWNED-ADAPTER-RAN.txt
```

**Second, distinct hole in the same path — the adapter's stdout reaches the `sqlite3` CLI as a
file, so a line beginning with `.` is a dot-command, not SQL:**

```
$ printf '#!/usr/bin/env bash\nif [ "$1" = emit ]; then printf ".shell touch PWNED-SQLITE-DOTCMD.txt\\n"; fi\n' > tools-x/adapter.sh
$ bash tooling/kit-index.sh >/dev/null 2>&1 ; ls PWNED-SQLITE-DOTCMD.txt
PWNED-SQLITE-DOTCMD.txt
```

The refusal filter (`kit-index.sh:103-106`) matches
`(attach|detach|pragma|drop|alter|vacuum)` and cannot see `.shell`, `.system`, `.import`, `.load`
or `.output`. `sqlite3 "$NEW" < "$SQL"` at `:1138` is a redirect into the CLI, which interprets
dot-commands; a driver would not.

## The trust model contradicts itself, and that is the root

`SECURITY.md` §1 classifies **"Ingest adapter output"** as **not trusted** — "the kit runs it and
reads what it prints". `run_adapter`'s own comment says the opposite: *an adapter is trusted code
named in a committed, reviewed profile.* Both cannot hold. The table's wording also understates
what happens: the kit does not merely *read* what the adapter prints, it **executes** it, twice
over — as a process, and as sqlite3 input.

`SECURITY.md` §2's "No model output is executed" rests on an exhaustive search for `eval`, `exec(`,
`system(` and `sh -c`. That search was never going to find `bash "$_ap"`. §4's "settings.local.json
and hook configuration are unreviewed inputs" does not cover the profile, and nothing in the
document says these files are agent-writable by construction.

## Acceptance criteria

- [ ] **The contradiction is resolved explicitly and recorded**, because the two answers lead to
      different systems and this is an architecture decision, not a patch:
      · **(a) adapters are trusted** — then the profile is a trust boundary and must be treated as
        one: named in `SECURITY.md` §1, and something must make an agent-authored change to it
        visible before it runs.
      · **(b) adapters are untrusted** — then output is validated before it reaches sqlite3, and
        running an arbitrary path from a file an agent can write is itself the defect.
      An ADR is the right home; `paths.adr` exists. Do not fix the symptom and leave the table
      saying one thing and the code another.
- [ ] **Dot-commands cannot reach `sqlite3` from adapter output**, whichever branch is chosen — the
      cheapest structural fix is to stop feeding a redirect and pass statements in a way the CLI
      does not interpret, rather than extending a blacklist. **A blacklist that gained `.shell`
      would be the same defect with a longer regex.**
- [ ] **A test proves both holes closed and FAILS when the fix is reverted**: an adapter that
      `touch`es a marker must not produce it, and an adapter emitting `.shell` must not produce
      its marker. Assert on the marker's absence *and* prove the harness would notice its presence.
- [ ] **The profile's status as an input is stated wherever it is relied on** — `SECURITY.md` §1
      gains a row or an existing row is corrected, and §2's "no model output is executed" is
      restated to account for indirect execution or moved.
- [ ] **`docs/ADAPTERS.md` states the contract's security posture** — what an adapter may assume
      about its caller, and what the caller assumes about it. That document is how a third adapter
      gets written; today it would be written against the friendlier of two contradictory answers.

## Notes

Found by the security reviewer during the T2 review of
`T-20260815-security-md-claims-allowedtools-enforces`; both halves reproduced independently before
being accepted.

**This is the most serious finding of that review and the one least fixable by editing a document.**
The others are false claims about real controls; this is a missing control that a false claim was
hiding. It is also the one whose blast radius leaves the repository — `bash "$_ap"` runs with the
operator's full permissions, and `SECURITY.md` §4 already concedes there is no sandbox.

**Reachability does not depend on a malicious agent.** A confused one that writes a plausible
`ingest.extra` value, or a profile copied between projects, reaches the same place. The kit's own
`git.adopted_at` and `paths.*` keys are edited routinely, so the file is not one anybody treats as
privileged today.

Related: `T-20260815-an-ingest-adapter-can-insert-a-task-row-` is the *data* half of this — an
adapter inserting rows the invariant forbids. This is the *execution* half. They share a cause
(adapter output is trusted by the pipeline and untrusted by the document) and should probably be
decided together, but they fail independently and are not duplicates.
