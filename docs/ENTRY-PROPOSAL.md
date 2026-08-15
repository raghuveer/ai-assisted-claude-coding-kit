# The entry proposal — format, and who writes it

A reference file, not an agent and not a skill. `docs/DESIGN-NOTES.md` §0: an agent is a permanent
context charge on every session; a reference file costs nothing until something reads it. Turning
a codebase into a candidate task list is a once-per-adoption act, so it gets a document.

ADR 0001 decided the split. `kit-entry.sh` produces facts. A model produces judgement. The
orchestrator writes files. Nothing files work.

## The procedure

1. **`kit-entry.sh`** — writes `entry-facts.tsv`, `entry-comment-runs.tsv` and `entry-report.md`
   under `paths.state`. All three are derived and gitignored.
2. **`researcher`** — given the report, the TSVs and a bounded, named file list, it **returns**
   the proposal text as its reply. It has `Read, Grep, Glob, WebFetch, WebSearch` and **no
   `Write`**; do not grant it one. Ask it for the format below rather than its usual design-input
   template, which is a different artefact with a different shape and a ~2000-word cap.
3. **The orchestrator** writes two files, because it is the actor that holds `Write`:
   - `<paths.state>/entry-candidates.md` — disposable, gitignored, overwritten by the next run.
   - `<paths.design_input>/YYYY-MM-DD-entry-questions.md` — **committed**. Questions are a durable
     record of what was asked; candidates are disposable once confirmed. Two lifetimes, two files.
4. **`kit-entry.sh --check <file>`** — validates the shape and refuses a candidate line that is
   unsafe to paste. Run it on what the model returned, before a human reads it.
5. **The operator** answers the questions, then runs the `kit-task.sh` lines they accept.
   `adr-scribe` turns an answered question into a decision record under `paths.adr`.

## The format

```markdown
## Open questions

1. Why is the retry count 7?
   evidence: src/retry.go:3, docs/note.md:5
   answer:

## Candidate tasks

- [ ] Document the retry budget
      evidence: src/retry.go:3
      kit-task.sh --title 'Document the retry budget' --tier T1

## Could not determine

- co-change: empty — indistinguishable from withheld / disabled / no history / no index
```

**Questions come first, and carry no checkbox.** A checkbox is a thing to be ticked and then done;
a question is a thing to be answered. The task this mechanism serves says an undocumented design
choice is a QUESTION, not a defect — putting a checkbox on one invites it to be closed rather than
answered, which is the failure the rule exists to prevent.

**Every question and every candidate cites evidence**, as `path` or `path:line`. A candidate with
no evidence is an opinion, and the point of the census is that opinions are separable from facts.

**Every candidate carries the literal `kit-task.sh` line** the operator would run. There is no code
path from this file to a task file: the operator copies the line, or does not. That is the whole of
the structural prevention and it is exactly as strong as that sentence.

## What `--check` does and does not enforce

It enforces: questions section present and before candidates; no checkbox on a question; every
candidate has a `kit-task.sh` line; a `Could not determine` section exists; and **every candidate
title is safe to paste** — single-quoted, with no quote, backtick, `$`, `;`, `|`, `&`, `<`, `>` or
newline in it.

That last one closes, mechanically, one of the two conventions ADR 0001 recorded. The ADR says the
charset restriction is enforced by nobody because "the tool never sees the titles". With this
check the tool does see them: the orchestrator writes the file, then the tool reads it. The ADR's
statement was true of the design as written and is now false, which is worth knowing when reading
it.

**It does not enforce the hold.** Nothing stops an operator, or an agent with `Bash`, running
`kit-task.sh` before answering a single question. That remains convention, as ADR 0001 says, and
`--check` does not change it. A check that validated shape and then let the list be filed anyway
would look like a gate while gating nothing.

**It does not check that cited paths exist.** `T-20260814-nothing-checks-that-a-finding-s-file-and`
is the same gap for findings and should be solved once, for both.
