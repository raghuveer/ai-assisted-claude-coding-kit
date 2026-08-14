# Security posture

**Summary.** The kit treats **agent output as untrusted input**, never as privileged code. Five
things are enforced mechanically: reviewers hold read-only tools, one module serialises all JSON,
every field is sanitised before it reaches the append-only log and the invariant re-checked after,
accelerator export selects aggregates only so it *cannot* return project text, and no model output
is ever executed. Four things are convention rather than mechanism and are named as such — the
write-guard never sees `Bash`, nothing stops a committer self-certifying their own work, prompt
text is behavioural shaping and not access control, and SQL takes escaped values rather than bound
parameters. Five things are simply absent, listed in §4, of which the sandbox gap for the two
Bash-holding agents is the largest. §5 is the rule set for anyone extending the kit.

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
| Ingest adapter output | **no** | An executable named in the profile; the kit runs it and reads what it prints |
| Externally supplied accelerator content | **no** | Enters as a hypothesis (`[seeded]`), never as authority |
| The project profile | **partly** | Authored by the operator, but its values are interpolated into globs and queries |

The single most important line: **agent output is untrusted input, not privileged code.** It is
handled with the posture given to a form field on a public web page, never more.

---

## 2. What is enforced mechanically

**Reviewers cannot write.** `approach-reviewer`, `implementation-reviewer` and
`security-reviewer` are granted `Read, Grep, Glob` and nothing else. This is enforced at
invocation (`--allowedTools`), not requested in prose. A reviewer that can edit what it reviews
is not an independent check.

**One JSON writer.** Every event line is serialised by `kit_findings.py` with `json.dumps`. The
shell builds no JSON. This is the fix for a critical found twice: `printf`-built JSON
interpolated `lang`, `pattern`, `domain` and `file` unescaped into an append-only committed log,
and because the reader takes the first match, a crafted field could inject a key the indexer
would then prefer over the real one.

**Fields are sanitised before serialisation, and the invariant is checked after.** Every string
reaching the log is reduced to one printable line with no quote and no backslash; `_assert_flat()`
then verifies that on the finished line rather than trusting the sanitiser.

**Accelerator export is aggregate-only by construction.** The export queries select
`lang / domain / pattern`, `class`, a count and a vindication sum — nothing else. The query
*cannot* select finding text, file paths, task ids or titles, because those columns are not in
it. This is structural, not a filter someone remembers to apply, and it is what makes
cross-project promotion safe to run against client work.

**A solution overlay is never exported.** Client architecture is project-scoped and excluded by
construction, the same way instance data is.

**No model output is executed.** There is no `eval`, `exec` or shell interpolation of agent
output anywhere in `tooling/`. The one `eval` in `kit-index.sh` expands a hardcoded literal list
of variable *names* from the script itself. The one `sh -c` in `kit-review-record.sh` runs the
**caller's** reviewer command — supplied by the operator, never by a model.

**Writes are confined to the project root.** `kit-guard.sh` refuses `Write`, `Edit` and
`NotebookEdit` outside it.

---

## 3. What is convention, not mechanism — stated plainly

**The guard does not see Bash.** The hook matcher is `Write|Edit|NotebookEdit`. No `git push`,
no `rm`, no shell redirect is intercepted. Anything relying on "the agent will not run that
command" is procedure. For trial work this is why the subject copy must have **no remote** —
`kit-preflight.sh --isolated` checks the property rather than trusting the intention.

**Nothing stops an actor with commit access writing `Via: kit`,** or marking their own findings
fixed. Both are conventions the operator enforces. The kit records *who* — fix marks carry an
actor — so the claim is auditable after the fact, which is the most a text-file system can offer.

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

- **No threat model per component.** This document names boundaries; it does not enumerate
  attacks against each script.
- **No secret scanning** over agent definitions, task files or the event log.
- **No sandbox for tool-using agents.** `coder` and `tester` hold `Bash` and run in the
  operator's environment with the operator's permissions. There is no separate process, no
  resource limit, no restricted filesystem.
- **No capability allow-list enforced at a wrapper.** Tool grants live in agent frontmatter and
  are applied by the invoking command; nothing refuses an out-of-scope operation independently
  of how the agent was launched.
- **`.claude/settings.local.json` and hook configuration are unreviewed inputs.** Filed as
  `T-20260811-scan-the-harness-configuration-as-an-att`.

---

## 5. Rules for anyone extending this kit

1. **Never interpolate model output into a shell command, a glob, or a `case` pattern.** One
   metacharacter changes what is matched. This kit shipped that shape three times in one day and
   has an open task to lint for it.
2. **Never add a second JSON writer.** Validation and serialisation stay in `kit_findings.py`.
   The separation of "one module decides, another records" was itself the defect.
3. **Prefer a structured contract to parsing.** Every defect in the findings path came from
   parsing prose. If an agent must return data, give it a schema and validate before use.
4. **Make redaction structural.** If a query must not return client text, do not filter it out —
   do not select it.
5. **A control that cannot fail is not a control.** Prove it with a mutation before believing it.
6. **Default to recommendation, not auto-execute.** Anything that closes a gate, publishes, or
   writes outside the project is proposed by the agent and performed by the operator.

---

## Reporting

This is a development tool that runs locally against repositories the operator already controls.
It has no network service, no runtime dependency on a model provider, and stores nothing outside
the project directory. Issues that nevertheless carry security weight — a path traversal, an
injection into the committed log, a leak of project text into an aggregate export — should be
raised as a finding at `critical` severity so they enter the same gate as everything else.
