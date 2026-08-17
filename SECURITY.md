# Security posture

**Summary.** The kit treats **agent output as untrusted input**, never as privileged code. Five
things are enforced mechanically, each demonstrated rather than argued: findings and fix-marks
have one JSON serialiser, every field is sanitised before it reaches the append-only log and the
invariant re-checked after, accelerator export selects aggregates only so it *cannot* return
project text, no model output is ever executed, and writes are confined to the project root.
Five things are convention rather than mechanism and are
named as such — **reviewer read-only**, the write-guard never seeing `Bash`, nothing stopping a
committer self-certifying their own work, prompt text being behavioural shaping and not access
control, and SQL taking escaped values rather than bound parameters. Eight things are simply
absent, listed in §4, of which the sandbox gap for the two Bash-holding agents is the largest.
§5 is the rule set for anyone extending the kit.

> **This document was wrong twice, and the corrections are dated.** Until 2026-08-16 the section
> below claimed reviewers were held read-only by `--allowedTools` and that one module serialised
> every event line. Both were false, and a false entry under *enforced mechanically* is worse than
> no entry at all: it stops the reader looking for the real control. What replaced them, and how
> each surviving claim was demonstrated, is in §2.

What this kit trusts, what it does not, what it enforces mechanically, and what it only asks
for. Written because the properties were real and scattered — across agent frontmatter, a hook
config, one design note and a trial protocol — so nothing stated the boundaries in one place.

**Every claim here is about behaviour in this repository, not intent.** Where a control is a
convention rather than a mechanism, it says so. A security document that cannot be told from a
wish list is worse than none.

---

## 1. Trust boundaries

| Input | Trusted? | Why it matters |
|---|---|---|
| The operator | **yes** | The only party that may close a task, publish an accelerator, or mark a finding fixed |
| Agent output (findings, verdicts, summaries) | **no** | Model text that reaches a log, a database, or a report |
| Git trailer text | **no** | Arbitrary text from history, written before any gate existed |
| Task files | **no** | Text files anyone with commit access may author |
| The plan (`.project/plans/*.tsv`) | **no** | Same class as task files, and read at the start of every session: `kit-index.sh` §3c parses it and emits SQL from its contents (ADR 0004). Two of its columns are not merely data — `goal_id` becomes a **directory name** that `skills/task-context` step 4 tells an agent to read "early and verbatim", and the numerics reach `sqlite3`. Validated at ingest per the row below, because `kit-guard.sh` permits `Write` anywhere inside the root, so an agent can author one. |
| Ingest adapter **process and output** | **no** | An executable named in the profile. The kit **executes** it — as a process, and again by feeding its stdout to the `sqlite3` CLI. It does not merely read what it prints. Constrained per ADR 0003: the path must be repo-relative and the file must be tracked by git, so an adapter an agent invented does not run. |
| Externally supplied accelerator content | **no** | Enters as a hypothesis (`[seeded]`), never as authority |
| The project profile | **partly** | Authored by the operator, but its values are interpolated into globs and queries |

The single most important line: **agent output is untrusted input, not privileged code.** It is
handled with the posture given to a form field on a public web page, never more.

---

## 2. What is enforced mechanically

> **Every claim in this section was re-checked on 2026-08-16**, and each entry names *how* — so
> the next reader re-runs the check instead of re-deriving the argument. Four were demonstrated
> by running the control against hostile input or mutating it and watching it refuse. One — "no
> model output is executed" — rests on an exhaustive search rather than a demonstration, and says
> so in its own entry, because a claim's evidence and a claim's confidence should not be
> separable. Two claims did not survive the sweep: reviewer read-only moved to §3, and the
> JSON-writer claim is narrowed below with its remainder recorded in §4.

**A plan file is validated before any of it becomes a row, and it is refused whole.**
`kit-index.sh` §3c requires a `#goal` header that is a safe path segment (`[A-Za-z0-9._-]` only),
requires **every row's first column to equal that header**, and requires `layer`, `rank`, `score`
and `cluster` to be plain numbers before they are coerced. Any failure refuses the entire file —
no partial plan — and records the reason in `plan_refused` / `plan_refused_text`, which
`kit-status.sh` renders. `kit-plan.sh` refuses the same charset on `--goal` rather than rewriting
it, so the value stored and the directory written are one value and not two.
*Demonstrated by running the attacks, not by reading the code:* a committed plan whose header said
`default` and whose row carried `goal_id = ../../docs` made step 4's own documented query resolve
to `<root>/docs/c1.md` — outside the packs directory, into a file an agent is told to load "early
and verbatim". A `score` of `1e999` emitted `+inf`, which `sqlite3` rejects, taking the whole
index build down and leaving a `.failed` mark every later run re-trips. A non-numeric `layer`
silently became `0` and collapsed the topology. All three are refused now; a valid plan still
loads. **What this does not cover:** the file is trusted to be *well-formed*, never to be
*correct* — a syntactically perfect plan that orders the wrong work is indistinguishable from a
right one, and no check here can say otherwise.

**The generic writer cannot mint a kind the indexer acts on.** `kit-index.sh` either **mutates a
row** for an event kind or merely **records** it. The four it mutates for — `finding`,
`finding-fixed`, `spend`, `vindication` — each have a writer that validates, and
`tooling/kit-event.sh`, which validates nothing, now refuses them.
*Demonstrated by a conformance step, and it can fail:* `the generic event writer cannot mint a
kind the indexer acts on` **derives** the list from the indexer's own `k=="…"` branches rather
than restating it, so teaching the indexer a fifth acting kind without guarding it goes red. It
asserts on the log being byte-identical, not on an exit code — a refusal that exits non-zero and
appends anyway is the failure worth catching — and it also requires an ordinary kind to still
record, so a guard that refused everything cannot pass.
*Corrected 2026-08-16.* The claim here was "every `finding`, `finding-gap` and `finding-fixed`
line is serialised by `kit_findings.py`". That was false:
`kit-event.sh T-x finding-fixed '{"finding":"<id>","fixed":1}'` set `fixed_at` on a real finding
after a reindex, forging the artefact `.claude/CLAUDE.md` reserves to the operator, with
`kit_findings.py` never invoked.
*Still true of `finding-gap`, and stated rather than glossed:* the indexer only records it, so it
is **not** in the refused set and the generic writer can still emit one. `kit-status.sh` counts
those rows, so a forged one inflates a reported figure. That is reporting integrity, not
privilege — and it is a smaller claim than the one this paragraph used to make.

**This is narrower than the claim it replaces.** The old wording — "every event line", "the shell
builds no JSON" — was false: `kit-event.sh`, `kit-checkpoint.sh`, `kit-spend.sh`,
`kit-vindicate.sh` and the accelerator export all build JSON with `printf`, and not all of them
escape. That gap is §4, not this section.

**Fields are sanitised before serialisation, and the invariant is checked after.** Every string
reaching the log is reduced to one printable line with no quote and no backslash; `_assert_flat()`
then verifies that on the finished line rather than trusting the sanitiser.
*Demonstrated:* a finding whose `lang` was `bash","kind":"spend","x":"` — a duplicate-key
injection — emitted as `bash','kind':'spend','x':'`, inert, with one `kind` in the line; quotes,
backslashes, a newline, a tab and a `\x07` in `summary` all collapsed. *And it can fail:* with
`sanitise()` mutated to `return text`, the same input was refused with "a backslash survived into
the event line; refusing to write" and nothing was recorded.

**Accelerator export is aggregate-only by construction.** The export queries select
`lang / domain / pattern`, `class`, a count and a vindication sum — nothing else. The query
*cannot* select finding text, file paths, task ids or titles, because those columns are not in
it. This is structural, not a filter someone remembers to apply, and it is what makes
cross-project promotion safe to run against client work.
*Demonstrated:* in a throwaway clone, all 316 finding rows were rewritten to carry
`ACMEBANK-SECRET-SUMMARY` in `summary`, `CLIENTNAME-ledger.ts` in `file_path` and
`T-ACMEBANK-CONFIDENTIAL` in `task_id`. The export ran and contains **zero** occurrences of any
of the three.

**No model output is executed.** There is no `eval`, `exec` or shell interpolation of agent
output anywhere in `tooling/`. The one `eval` in `kit-index.sh` expands a hardcoded literal list
of variable *names* from the script itself. The one `sh -c` in `kit-review-record.sh` runs the
**caller's** reviewer command — supplied by the operator, never by a model.
*Verified structurally, and the weakest entry here for it:* an exhaustive search of `tooling/` for
`eval`, `exec(`, `system(` and `sh -c` returns those two sites and no others, and the reviewer's
reply is redirected to a file and fed to the validator on stdin — `kit-review-record.sh` writes it
to `$WORKDIR/reply`, which is read, never run. **This is a search plus a reading, not a
demonstration against hostile input**, and it is weaker than the four entries above for exactly
that reason. It holds only for the absence it searched for: a construct not on that list, or one
added later, would not be caught by anything. A test that tried to execute a crafted finding and
observed it *not* run would be the real check, and does not exist.

**Writes are confined to the project root, for the three tools the hook matches.**
`kit-guard.sh` refuses `Write`, `Edit` and `NotebookEdit` outside it.
*Demonstrated by a conformance step, and it can fail:* `the write guard refuses every tool its
matcher fires on` drives all three tools in **both** directions — an absolute path outside the
root must exit **2**, one inside must exit **0**. A guard that refused everything would pass an
outside-only test and make the kit unusable, which is why both directions are asserted. Reverting
the fix turns the step red.
*Corrected 2026-08-16, and it was false when first written here.* The guard read only
`"file_path"`, while `NotebookEdit` names its target `"notebook_path"` — so extraction returned
empty, the documented no-target branch fail-opened, and `NotebookEdit` was waved through
unexamined anywhere on disk. The evidence line that stood here exercised `Write` and *inferred*
the other two. The check that was meant to cover it greps `hooks.json` for the matcher **string**,
which passes while the guard is broken; that assertion remains as a protocol check and is not
evidence for this claim.
*Its limit is in §3:* the matcher is `Write|Edit|NotebookEdit`, so a `Bash` payload deleting that
same outside path exits 0 unexamined — verified, not assumed.

---

## 3. What is convention, not mechanism — stated plainly

**Reviewer read-only is a convention.** `approach-reviewer`, `implementation-reviewer` and
`security-reviewer` declare `tools: Read, Grep, Glob` in their frontmatter and say "read-only by
design" in their prompts. **Neither binds.** Until 2026-08-16 this document claimed the grant was
"enforced at invocation (`--allowedTools`), not requested in prose". That is false: a reviewer
launched with exactly `--allowedTools "Read,Grep,Glob" --disallowedTools "ReportFindings"` ran
`Bash` — its transcript carries a `Bash` `tool_use` with `is_error: false` returning a real
directory listing, alongside 21 `Read` and 3 `Grep` calls.

Treat an agent's `tools:` frontmatter, and any `--allowedTools` list, as a **declaration of intent
that the harness may or may not honour**. Nothing in this kit verifies that the tool set an agent
declares matches the tool set it actually has, and the kit does not spawn reviewers itself —
`kit-review-record.sh --cmd` is the operator's command, so the grant is whatever that command and
that harness version do. A reviewer that can edit what it reviews is not an independent check;
today nothing stops one, so the independence rests on the model's compliance and on the operator
reading the diff.

**Do not read the disclosure as a mitigation.** That violation was noticed only because the
reviewer volunteered the tool use in its own "what I did not check" section. A control whose
violation is detected only when the violator reports it is not a control — it is an argument for
keeping that section, and nothing more.

**The guard does not see Bash.** The hook matcher is `Write|Edit|NotebookEdit`. No `git push`,
no `rm`, no shell redirect is intercepted. Anything relying on "the agent will not run that
command" is procedure. For trial work this is why the subject copy must have **no remote** —
`kit-preflight.sh --isolated` checks the property rather than trusting the intention.

**Nothing stops an actor with commit access writing `Via: kit`,** or marking their own findings
fixed. Both are conventions the operator enforces. The kit records *who* — fix marks carry an
actor — so the claim is auditable after the fact, which is the most a text-file system can offer.

**Narrowed, not solved, 2026-08-16.** The *back door* to a fix-mark is closed — `kit-event.sh`
refuses `finding-fixed`, so a forged one no longer reaches the database through the generic
writer (§2). The *front door* is untouched: `kit-resolve.sh --fixed` runs for whoever invokes it,
and `.claude/CLAUDE.md` and `skills/checkpoint/SKILL.md` both instruct an agent to propose the
mark and stop — instructions, not gates. The recorded actor comes from
`git config user.email`, which is the **repository's** identity rather than the party that ran the
command, so it does not distinguish an agent-applied mark from the operator's. Treat the audit
trail as evidence of *what* was marked, never of *who* decided it.

**A system prompt is not a security boundary.** Observed here directly: across four live reviewer
runs the output contract was ignored three times — a reporting tool was called, a reply arrived
in a code fence, a summary ran past the length cap. The fix was never stronger wording; it was a
validator that refuses and a retry that hands back its own diagnostics. Treat prompt text as
behavioural shaping, output-format direction and refusal contracts — never as access control,
and never as a place for credentials, client identity or anything whose disclosure would matter.

**SQL takes escaped values, not bound parameters.** Model text reaches SQLite through `q()`,
which doubles single quotes, on top of sanitisation that has already removed quotes and
backslashes. Two layers and an assertion, but it is escaping — if this ever moves to a driver
that supports binding, bind.

---

## 4. Absent, and known to be

- **No single JSON writer for the whole event log.** Findings go through `kit_findings.py`; the
  other kinds do not. `kit-event.sh`, `kit-checkpoint.sh`, `kit-spend.sh` and `kit-vindicate.sh`
  build their lines with `printf`, and the accelerator export builds its own. They are not equally
  exposed, and the difference is the point: **`kit-spend.sh` escapes** every interpolated field
  through its own `esc()`, in both the shell and the awk writer; **`kit-checkpoint.sh`** escapes
  nothing but interpolates only machine values (a timestamp, a SHA, a count); **`kit-event.sh`**
  escapes its two fields and then splices its third argument in as **raw JSON**; and
  **`kit-vindicate.sh` escapes nothing at all** while taking both its fields from the command
  line. That last one is the live hole.
  *Demonstrated:* `kit-vindicate.sh --task T-x --class 'style","kind":"spend",…'`
  appended a line carrying a second `kind` key and a fabricated `tok_in`. The two readers of that
  file then disagree about what it says — the awk indexer takes the first match and records a
  `vindication`, while a JSON parser takes the last and sees a `spend`; the same log reads as 11
  spend events or 12 depending on which reader you ask. This is the original critical surviving in
  the paths the fix did not cover.
- **No threat model per component.** This document names boundaries; it does not enumerate
  attacks against each script.
- **The solution-overlay exclusion is untested, because there is no overlay.** This document
  previously listed "a solution overlay is never exported" as an enforced mechanism. Nothing
  named `overlay` exists anywhere in `tooling/` — the component is unbuilt, so nothing produces
  one, stores one or could export one. The exclusion is not a control that holds; it is a
  property with nothing to hold against yet, and it must be demonstrated when the overlay is
  built rather than inherited from this line.
- **The write-tool inventory is enumerated, not assumed — and it is a moving target.** The guard
  covers the three tools in the matcher. `MultiEdit` is **not present in the harness this kit was
  last checked against** (2026-08-16) and is therefore not in the matcher; if a future version
  reintroduces it, it writes unguarded until added. The same applies to any write tool an MCP
  server contributes, which the kit cannot enumerate at all because the set is per-installation.
  A conformance step now fails when the matcher names a tool the guard has no key for, so drift
  in that direction is caught; **drift in the other direction — a new tool nobody adds to the
  matcher — is not, and cannot be from inside this repository.**
- **No secret scanning** over agent definitions, task files or the event log.
- **No sandbox for tool-using agents.** `coder` and `tester` hold `Bash` and run in the
  operator's environment with the operator's permissions. There is no separate process, no
  resource limit, no restricted filesystem.
- **No capability allow-list enforced anywhere.** Tool grants live in agent frontmatter and in
  the invoking command's flags, and **neither is known to bind** — see §3. Nothing refuses an
  out-of-scope operation, and nothing compares the tool set an agent declares against the tool
  set it turns out to have. The earlier wording here said grants "are applied by the invoking
  command", which was the same false claim §2 used to carry, in gentler words.
- **`.claude/settings.local.json` and hook configuration are unreviewed inputs.** Filed as
  `T-20260811-scan-the-harness-configuration-as-an-att`.

---

## 5. Rules for anyone extending this kit

1. **Never interpolate model output into a shell command, a glob, or a `case` pattern.** One
   metacharacter changes what is matched. This kit shipped that shape three times in one day and
   has an open task to lint for it.
2. **Never add a second JSON writer.** Validation and serialisation stay in `kit_findings.py`.
   The separation of "one module decides, another records" was itself the defect. Five writers
   predate this rule (§4) — that is a debt to pay down, never a precedent to cite.
3. **Prefer a structured contract to parsing.** Every defect in the findings path came from
   parsing prose. If an agent must return data, give it a schema and validate before use.
4. **Make redaction structural.** If a query must not return client text, do not filter it out —
   do not select it.
5. **A control that cannot fail is not a control.** Prove it with a mutation before believing it.
6. **Default to recommendation, not auto-execute.** Anything that closes a gate, publishes, or
   writes outside the project is proposed by the agent and performed by the operator.
7. **A tool grant is a declaration, not a boundary.** Frontmatter `tools:` and `--allowedTools`
   describe what an agent is *asked* to hold. Before writing that anything is enforced by one,
   launch the agent, ask it for the tool you believe it lacks, and read the session transcript
   for a `tool_use` with `is_error: false`. Do not take the agent's own account of what it ran.
8. **Nothing enters §2 on a reading.** A claim of mechanical enforcement is admitted only with
   the demonstration that produced it, named in the entry — ideally one that shows the control
   *refusing*, since a check that passes on hostile input and on benign input alike proves
   nothing. Two claims sat in §2 for weeks on plausibility alone; both were false.

---

## Reporting

This is a development tool that runs locally against repositories the operator already controls.
It has no network service, no runtime dependency on a model provider, and stores nothing outside
the project directory. Issues that nevertheless carry security weight — a path traversal, an
injection into the committed log, a leak of project text into an aggregate export — should be
raised as a finding at `critical` severity so they enter the same gate as everything else.
